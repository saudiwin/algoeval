#' @title Compare Algorithms
#' @param algos algorithm input as a matrix with each column corresponding to one matrix.
#' @param outcome outcome that the algorithms predict should be passsed in as a vector of the same length as the matrix.
#' @param budget amount in dollars that the client has to spend on algorithms
#' @param MC marginal cost of producing an additional unit for each outcome (constant value as a percentage of revenue)
#' @param int_price The minimum amount that a customer purchases given a successful outcome
#' Function to evaluate algorithm input. 
#' The function produces a list that includes the different LOO (leave-one-out predictive density) values for each
#' of the algorithm inputs and a comparable estimate based on the budget that looks at net revenues.
#' @import dplyr ggplot2 rstan tidyr rstantools Rcpp methods loo data.table
#' @useDynLib algoeval, .registration = TRUE
#' @export
algo_compare <- function(algos=NULL,outcome=NULL,budget=10000,
                         MC=.25,int_price=2) {
  print('Running models in Stan')
  full_model <- sampling(stanmodels$measure_v1,
                         data=list(N=length(outcome),
                                                 J=ncol(algos), 
                                                 X=algos, y=outcome),
                         iter=1500,chains=2,cores=2,thin=2,
                         control=list(adapt_delta=0.95),
                         seed=12062016)
  
  int_model <- sampling(stanmodels$measure_null,data=list(N=length(outcome), y=outcome),
                        iter=1500,thin=2,chains=2,cores=2,
                        show_messages=FALSE,seed=12062016)
  
  print('Calculating budget performance for full model.')
  all_algos <- .budget_perf(full=full_model,null=int_model,outcome=outcome,
                            N=length(outcome),budget=budget,MC=MC,int_price=int_price)
  print('Calculating budget performance for each individual algorithm against null model.')
  over_algos <- lapply(1:ncol(algos), function(a) {
    singleton <- sampling(stanmodels$measure_singleton,
                          data=list(N=length(outcome),J=1, x=as.matrix(algos[,a]), y=outcome),
                          iter=1500,chains=2,cores=2,thin=2,control=list(adapt_delta=0.95))
    this_algo <- .budget_perf(full=singleton,null=int_model,outcome=outcome,
                                           N=length(outcome),budget=budget,MC=MC,int_price=int_price)
    return(list(algo_data=this_algo,model=singleton))
  })
  just_algo_data <- lapply(over_algos,function(x) x$algo_data)
  algo_models <- lapply(over_algos,function(x) x$model)
  just_algo_data <- bind_rows(just_algo_data)
  just_algo_data <- mutate(just_algo_data,algo_num=paste0('Algorithm_',rep(1:ncol(algos),each=(1500/2))))
  
  print('Processing LOO for full model')
  full_loo <- .loo_calc(stanobj=full_model,outcome=outcome,algo_data=algos,num_iters=1500)
  print('Processing LOO for each algo model separately')
  each_loo <- lapply(1:length(algo_models), function(a) {
    output <- .loo_calc(algo_models[[a]],outcome=outcome,
                        algo_data=as.matrix(algos[,a]))
    return(output)
    })
  return(list(total_perf=all_algos,each_perf=over_algos,total_loo=full_loo,each_loo=each_loo,budget=budget))
  
}

#' @title Simulate Algorithms
#' Function that will produce example algorithms based on simulated data. The simulation assumes that the algorithms can be ranked on their average predictive performance for a binomial (0/1) distributed outcome. Coefficient values are on the logit scale.
#' @param N Number of observations to simulate for each algorithm
#' @param algo_num Number of algorithms to simulate
#' @param algo_coefs Vector of coefficient values for algorithms on the logit scale. If absent, the algorithms will be placed on an even scale from 0 to .25.
#' @param algo_errs Vector of SDs for each of the algorithms. Set at 0.25 if empty.
#' @param intercept  A numeric value reflecting the average outcome (on the logit scale)
#' Function produces a list with an outcome and a matrix of predictors for use in the `compare_algos` function.
#' @export
algo_sim <- function(N=1000,algo_num=3,algo_coefs=seq(0,0.5,length.out = algo_num),algo_errs=rep(0.25,algo_num),
                       intercept=-1) {
  raw_data <- rnorm(n=algo_num*N,algo_coefs,algo_errs) %>% matrix(nrow=N,ncol=algo_num,byrow=TRUE)
  outcome <- (runif(N,0,1) < plogis(-1 + rowSums(raw_data))) %>% as.numeric
  
  return(list(outcome=outcome,algos=raw_data))
}

#' @title Plot Algorithms
#' Function that generates plots showing either LOO (leave-one-out predictive density) for all algorithms or profit/loss figures for each of the algorithms.
#' @param input A list as produced by the `algo_compare` function.
#' @param plot_type "loo" for predictive density, "cash" for budget/profit differences
#' @export
algo_plot <- function(obj=NULL,plot_type='cash') {
  
  if(plot_type=='cash') {
  
  output_diff <- lapply(obj$each_perf,function(x) {
    x$algo_data$budget <- x$algo_data$budget - metrics$total_perf$budget
    x$algo_data$profit <- x$algo_data$profit - metrics$total_perf$profit 
    return(x)
  })
  
  plot_diff <- lapply(output_diff,function(x) {
    data_frame(budget_mean=mean(x$algo_data$budget),
               budget_high=quantile(x$algo_data$budget,probs=0.95),
               budget_low=quantile(x$algo_data$budget,probs=0.05),
               profit_mean=mean(x$algo_data$profit),
               profit_high=quantile(x$algo_data$profit,probs=0.95),
               profit_low=quantile(x$algo_data$profit,probs=0.05))
  })
  
  outplot <-  bind_rows(plot_diff) %>% 
    gather(type,diff) %>% 
    separate(type,into=c('type','suffix')) %>% 
    mutate(algo_type=rep(paste0('Algorithm_',seq(1,length(obj$each_perf))),times=n()/length(obj$each_perf))) %>% 
    spread(suffix,diff) %>% 
    ggplot(aes(y=mean,x=reorder(algo_type,-mean))) + 
    geom_errorbar(aes(ymin=low,ymax=high),width=0.25) + 
    facet_wrap(~type,scales='free_y') + theme_minimal() + 
    ylab('Dollars') + xlab('') + geom_point()
  
  return(outplot)
} else {
  compare_loos <- lapply(obj$each_loo,function(x) as.numeric(compare(obj$total_loo,x))) %>% unlist %>% 
    matrix(nrow = length(obj$each_loo),ncol=2,byrow=TRUE) %>% as_data_frame
  names(compare_loos) <- c('ELPD','SE')
  compare_loos <-  mutate(compare_loos,high_ci=ELPD + 1.96*SE,
                           low_ci=ELPD - 1.96*SE,
                           algos=paste0('Algorithm_',1:length(obj$each_loo)))
  
  outplot <- compare_loos %>% ggplot(aes(y=ELPD,x=reorder(algos,-ELPD))) + geom_errorbar(aes(ymin=low_ci,ymax=high_ci),width=0.2) + 
    geom_point(colour='red',size=2) + theme_minimal() + ylab("Performance Decrease Compared to Full Model") + xlab("")
  return(outplot)
  }
}

#' @title  Payment Calculation for Algorithms
#' This function produces estimates of how much to pay each algorithm based on the overall budget and available profits.
#' @param obj The list object from the `algo_compare` function
#' The function produces a data frame with calculations for each algorithm
#' @export
algo_pay <- function(obj=NULL) {
  
  output_diff <- lapply(obj$each_perf,function(x) {
    x$algo_data$budget <- x$algo_data$budget - metrics$total_perf$budget
    x$algo_data$profit <- x$algo_data$profit - metrics$total_perf$profit 
    return(x)
  })
  
  plot_diff <- lapply(output_diff,function(x) {
    data_frame(budget_mean=mean(x$algo_data$budget),
               budget_high=quantile(x$algo_data$budget,probs=0.95),
               budget_low=quantile(x$algo_data$budget,probs=0.05),
               profit_mean=mean(x$algo_data$profit),
               profit_high=quantile(x$algo_data$profit,probs=0.95),
               profit_low=quantile(x$algo_data$profit,probs=0.05))
  })
  
  calc_amount <- plot_diff %>% 
    bind_rows %>% 
    gather(type,diff) %>% 
    separate(type,into=c('type','suffix')) %>% 
    mutate(algo_type=rep(paste0('Algorithm_',seq(1,length(obj$each_perf))),times=n()/length(obj$each_perf))) %>% 
    spread(suffix,diff) %>% 
    filter(type=='profit') %>% 
    select(algo_type,mean) %>% 
    mutate(mean_diff=DMwR::SoftMax(mean),normalized=mean_diff/sum(mean_diff),payout=obj$budget*normalized) %>% 
    arrange(normalized)
  return(calc_amount)
}