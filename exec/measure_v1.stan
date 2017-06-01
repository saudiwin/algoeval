functions {
  //Define an ROC function to handle prediction of success/failure in a Bayesian context
  //The ROC is a posterior-predictive test quantity and reflects uncertainty in the posterior
  //In other words, it is an ROC curve with a confidence interval
  //Inputs are predicted probabilities (pred_success), the actual observed data (obs_success), the number of observations,
  // and the number of thresholds to consider in the [0,1] interval
  
  matrix roc_curve(vector pred_success, vector obs_success, int num_obs, int threshold_num,vector quantiles) {
    
    //need matrix to hold false positive and true positive rates
  
    matrix[threshold_num+1,2] tpr_fpr_rates;
    real num_pos;
    real num_neg;
    
    num_pos = sum(obs_success);
    num_neg = num_elements(obs_success) - sum(obs_success);
    
    //Loop over thresholds to form ROC curve
    
    for(i in 1:(threshold_num+1)) {
      
      real q;
      
      vector[num_obs] fpr;
      vector[num_obs] tpr;
      
      q = quantiles[i];
      
      for(n in 1:num_obs) {
        if(pred_success[n]>q && obs_success[n]==1) {
          tpr[n] = 1;
          fpr[n] = 0;
        } else if (pred_success[n]>q && obs_success[n]==0) {
          tpr[n] = 0;
          fpr[n] = 1;
        } else {
          tpr[n] = 0;
          fpr[n] = 0;
        }
      
      tpr_fpr_rates[i,1] = sum(tpr) / num_pos;
      tpr_fpr_rates[i,2] = sum(fpr) / num_neg;
        
        
      }
      
    }
    
    return tpr_fpr_rates;
    
  }
  
}


data {
  
  //N = num obs
  
  int<lower=0> N;
  
  //J= num algorithms
  
  int<lower=0> J;
  
  //x = matrix of predicted algorithmic probabilities
  
  matrix[N,J] X;
  
  //y = vector of observed purchase/non-purchase
  
  int y[N];
  
 /* //number of points in [0,1] to evaluate ROC function
  int threshold_num;
  
  //same # but for calculation purposes
  real thresh_real;
  
  //whether model is hierachical (necessaray for loo calculation)
  
  int hier; */
  
}

transformed data {
  /* vector[threshold_num+1] quantiles;
  vector[N] obs_success;
  real step_size;
  
  //integer array to vector conversion for ROC function
  
  for(n in 1:N) {  
    obs_success[n] = y[n];
  }
  
  //generate quantiles for ROC curve
  // zero always equals zero for an ROC curve at the origin
  
  quantiles[1] = 0;
  step_size = 1 / thresh_real;
  for(r in 1:threshold_num) {
    quantiles[r+1] = quantiles[r] + step_size;
  } */
}

parameters {
  
  // Estimate a single parameter for each algorithm indexed by J
  // Will permit us to discriminate between algorithms
  // Higher coefficients should indicate better models. 
  // Lower standard errors also equal better-performing models
  // Per Carpenter (2015), the centered parameterization is more efficient given large data,
  // While a non-centered parameterization would be optimal for small data 
  // See http://mc-stan.org/documentation/case-studies/pool-binary-trials.html
  
  // To reduce correlation between the lower-level and upper-level parameters, we are using a 
  // 'non-centered parameterization'. It just means that the predictor variables are standardized
  // relative to the population-level variance to reduce correlation in the posterior
  
  
  vector[J] theta_raw;
  real mu;
  real<lower=0> tau;
  real alpha;
}

transformed parameters {
  
  //vector[J] theta;
  //this equation defines the relationship between the model coefficients and the higher-level (population)
  //parameters in a non-centered method
  //theta = mu + tau*theta_raw;
}

model {
  
  //Relatively vague priors
  //We assume that the thetas come from a common distribution as they all should be 
  //measuring the same thing
    
  //On the inverse logit scale, this hyperprior on mu covers the full probability range [0,1]
    mu ~ normal(0,5);
  //tau variance (common-wisdom) prior covers a wide variance on the logit scale
    tau ~ normal(0,5);
  //if non-centered, theta receives a standard unit normal prior to decouple the upper-level from lower-level parameters (non-centered
  
  theta_raw ~ normal(mu,tau);
  //intercept can take any vague prior
    alpha ~ normal(0,5);
  
  //Model sampling statement -- bernoulli model with logit link function (equivalent to GLM with logit link)
  
  y ~ bernoulli_logit(alpha + X*theta_raw);  
}


generated quantities {

    vector[N] theta_prob;  // chance of success converted from logit scale
    //int pred_success[N]; // Sample from binomial distribution regarding whether the customer bought the product or not

//    matrix[threshold_num+1,2] roc_graph;

  for (n in 1:N) {
    theta_prob[n] = inv_logit(alpha + X[n,]*theta_raw);
  //  pred_success[n] = bernoulli_rng(theta_prob[n]);
  }
/*  
  roc_graph = roc_curve(theta_prob,obs_success,N,threshold_num,quantiles);
  */
  
  // Create log-likelihood for use with loo
  // First pull from hyperprior, then generate bernoulli log density
  //even this is too big to run in Rstan with any efficiency
  //need to save model estimates and predictions separately
  /*
  vector[N] log_lik;
  vector[J] theta_rep;
  
  if(hier==1) {
  for(j in 1:J) {
      //Need to include uncertainty over the hyperprior on theta
      theta_rep[j] = normal_rng(mu,tau);
  }
  for(n in 1:N) {
    log_lik[n] = bernoulli_logit_lpmf(y[n] | alpha + x[n]*theta_rep);
  } 
  } else {
    for(n in 1:N) {
    log_lik[n] = bernoulli_logit_lpmf(y[n] | alpha + x[n]*theta_raw);
    }
  } */
    
}
