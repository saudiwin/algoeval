#' @title Compare Algorithms
#' @param algos algorithm input as a matrix with each column corresponding to one matrix.
#' @param outcome outcome that the algorithms predict should be passsed in as a vector of the same length as the matrix.
#' @param budget amount in dollars that the client has to spend
#' @param revenue amount that the client will gain for each successful conversion (outcome==1)
#' @param compare_with Should the comparison model be a "full" model or a "null" model with only an intercept?
#' @param MC marginal cost of producing an additional unit for each outcome (constant value as a percentage of revenue)
#' @param int_price The minimum amount that a customer purchases given a successful outcome
#' Function to evaluate algorithm input. 
#' The function produces a list that includes the different LOO (leave-one-out predictive density) values for each
#' of the algorithm inputs and a comparable estimate based on the budget that looks at net revenues.
#' @import dplyr ggplot2 rstan tidyr rstantools Rcpp methods
#' @useDynLib algoeval, .registration = TRUE
#' @export
algo_compare <- function(algos=NULL,outcome=NULL,budget=1000,revenue=10,compare_with='full',
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
  just_algo_data <- lapply(over_algos,function(x) x$this_algo)
  algo_models <- lapply(over_algos,function(x) x$singleton)
  over_algos <- bind_rows(just_algo_data)
  over_algos <- mutate(over_algos,algo_num=paste0('Algorithm_',rep(1:ncol(algos),each=nrow(over_algos[[1]]))))
  
  print('Processing LOO for full model')
  full_loo <- .loo_calc(stanobj=full_model,outcome=outcome,algo_data=algos,num_iters=1500)
  print('Processing LOO for each algo model separately')
  each_loo <- lapply(1:length(algo_models), function(a) {
    output <- .loo_calc(algo_models[[a]],outcome=outcome,
                        algo_data=as.matrix(algos[,a]))
    return(output)
    })
  return(list(total_perf=all_algos,each_perf=over_algos,total_loo=full_loo,each_loo=each_loo))
  
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
algo_sim <- function(N=1000,algo_num=3,algo_coefs=seq(0,0.25,length.out = algo_num),algo_errs=rep(0.25,algo_num),
                       intercept=-1) {
  raw_data <- rnorm(n=algo_num*N,algo_coefs,algo_errs) %>% matrix(nrow=N,ncol=algo_num,byrow=TRUE)
  outcome <- (runif(N,0,1) < plogis(-1 + rowSums(raw_data))) %>% as.numeric
  
  return(list(outcome=outcome,algos=raw_data))
}

#' @title Plot Algorithms
#' Function that generates plots showing either LOO (leave-one-out predictive density) for all algorithms or profit/loss figures for each of the algorithms.
#' @param input A list as produced by the `algo_compare` function.
#' @param plot_type "loo" for predictive density and "budget" for profit/loss
#' @export
algo_plot <- function(input=NULL) {
  
}