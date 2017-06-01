#' Function that calculates differences in budget performance.
.budget_perf <- function(full=NULL,null=NULL,outcome=NULL,N=NULL,budget=NULL,MC=NULL,int_price=NULL) {
  post_theta <- rstan::extract(full,pars='theta_prob')[[1]]
  post_null <- rstan::extract(null,pars='mu')[[1]]
  num_iters <- nrow(post_theta)
  output_budget_theta <- 1:num_iters
  output_profit_theta <- 1:num_iters
  
  for(i in 1:num_iters) {
    
    # Sort so we can segment the market
    out_data <- data_frame(latent = post_theta[i,],outcome=as.integer(outcome)) %>% arrange(desc(latent))
    out_data$groups <- factor(rep(1:100, each=N/100))
    out_sum <- group_by(out_data,groups) %>% summarize(soft_latent=mean(latent)) %>% ungroup 
    out_sum$soft_latent <- DMwR::SoftMax(out_sum$soft_latent)
    out_data <- left_join(out_data,out_sum,by='groups')
    
    max_value <- optimize(.exp_revenue,interval=c(0,budget),out_data=out_data,N=N,MC=MC,int_price=int_price,maximum=TRUE)
    
    output_budget_theta[i] <- max_value$maximum
    output_profit_theta[i] <- max_value$objective
  }
  
  output_budget_null <- 1:num_iters
  output_profit_null <- 1:num_iters
  
  for(i in 1:num_iters) {
    
    # Sort so we can segment the market
    out_data <- data_frame(latent = post_null[i],outcome=as.integer(outcome)) %>% arrange(desc(latent))
    out_data$groups <- factor(rep(1:100, each=N/100))
    out_sum <- group_by(out_data,groups) %>% summarize(soft_latent=mean(latent)) %>% ungroup 
    out_data <- left_join(out_data,out_sum,by='groups')
    
    max_value <- optimize(.exp_revenue,interval=c(0,budget),out_data=out_data,MC=MC,int_price=int_price,N=N,maximum=TRUE)
    
    output_budget_null[i] <- max_value$maximum
    output_profit_null[i] <- max_value$objective
  }
  
  output_budget_diff <- output_budget_theta - output_budget_null
  output_profit_diff <- output_profit_theta - output_profit_null
  return(data_frame(budget=output_budget_diff,profit=output_profit_diff))
}

#' Internal function for optimizing budgets
.exp_revenue <- function(budget=NULL,out_data=NULL,N=NULL,MC=.25,int_price=2) {
  out_data <- mutate(out_data,e_rev = outcome * (int_price + ((budget*soft_latent*10)/N) - ((budget*soft_latent)/N)^2))
  e_profit <- sum(out_data$e_rev) - budget - sum(out_data$e_rev)*MC
  return(e_profit)
}

#' Internal function for calculating loo given two stanfit objects
#' @import loo
.loo_calc <- function(stanobj=NULL,outcome=NULL,algo_data=NULL,num_iters=NULL) {
  out_log <- .get_log_lik(stan_sample=all_models[[x]],outcome=outcome,algo_data=algo_data,nwarmup=(num_iters)/2,niters=num_iters)
  mean_loo <- colMeans(out_log)
  # There is a problem with arithmetic underflow where very certain outcomes of the logit model come out as probability 1,
  # Which screws up the loo
  check_zeroes <- (mean_loo==0 | mean_loo>-200*.Machine$double.neg.eps)
  out_log[,check_zeroes] <- out_log[,check_zeroes] + runif(n=400,max=-100*.Machine$double.neg.eps,min=-200*.Machine$double.neg.eps)
  check_neg_inf <- mean_loo < log(100*.Machine$double.neg.eps)
  # It seems like smallest number you can log is 1e-300 (an infitesimal probability)
  #see if there is a number besides infinity
  # get the lowest non-infinite number (mean and sd)
  min_mean <- min(mean_loo[!is.infinite(mean_loo)])
  min_sd <- sd(out_log[,which(mean_loo==min_mean)])
  out_log[,check_neg_inf] <- apply(out_log[,check_neg_inf,drop=FALSE],2,function(x) {
    x <- log(runif(n=400,min=100*.Machine$double.neg.eps,max=200*.Machine$double.neg.eps))
    return(x)
  })
  
  out_loo <- loo(out_log)
  print(out_loo)
  return(out_loo)
}

#' calculate binomial log likelihood for a given stan model
#' @import data.table
.get_log_lik <- function(stan_sample=NULL,outcome=NULL,algo_data=NULL,nwarmup=NULL,
                        niters=NULL) {
  
  predictors <- rstan::extract(stan_sample,pars='theta_raw')[[1]][(nwarmup+1):niters,]
  intercept <- rstan::extract(stan_sample,pars='alpha')[[1]][(nwarmup+1):niters]
  raw_predict <- algo_data %*% t(predictors)
  rm(predictors)
  raw_predict <- apply(raw_predict,1,function(x) x + intercept) %>% t
  # apply loop is too memory hungry
  # switch to data.table to modify one column at a time in-place
  raw_predict <- as.data.table(raw_predict)
  
  #log_lik <- apply(raw_predict,2,function(x) dbinom(x=outcome,size=1,prob=plogis(x)))
  #increases memory by about double, but it still able to return the object
  #runs much faster than apply loop
  raw_predict <- raw_predict[,lapply(.SD,
                                     function(x) dbinom(x=outcome,size=1,prob=plogis(x),log=TRUE))]
  
  return(t(as.matrix(raw_predict)))
}