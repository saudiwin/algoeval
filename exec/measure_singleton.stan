data {
  
  //N = num obs
  
  int<lower=0> N;
  
  //J= num algorithms
  
  int<lower=0> J;
  
  //x = matrix of predicted algorithmic probabilities
  
  matrix[N,J] x;
  
  //y = vector of observed purchase/non-purchase
  
  int y[N];
  
  //number of points in [0,1] to evaluate ROC function
  
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
  
  
  vector[1] theta_raw;
  real alpha;
}

model {
  
  //Relatively vague priors
  //We assume that the thetas come from a common distribution as they all should be 
  //measuring the same thing
  
  theta_raw ~ normal(0,5);
  //intercept can take any vague prior
    alpha ~ normal(0,5);
  
  //Model sampling statement -- bernoulli model with logit link function (equivalent to GLM with logit link)
  
  y ~ bernoulli_logit(alpha + x*theta_raw);  
}

generated quantities {
  vector[N] theta_prob;
  
    for (n in 1:N) {
    theta_prob[n] = inv_logit(alpha + x[n]*theta_raw);
    }
}
