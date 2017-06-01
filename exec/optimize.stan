data {
  
  //N = num obs
  
  int<lower=0> N;
  
  //J= num algorithms
  
  int<lower=0> J;
  
  // number of weights
  
  int weight_num;
  
  // weight data
  
  int w[N];
  
  //x = matrix of predicted algorithmic probabilities
  
  matrix[N,J] x;
  
  //y = vector of observed purchase/non-purchase
  
  int y[N];
  
  //number of points in [0,1] to evaluate ROC function
  int threshold_num;
  
  //same # but for calculation purposes
  real thresh_real;
  
  //whether model is hierachical (necessaray for loo calculation)
  
  int hier;
  
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
  simplex[weight_num] weights;
  real alpha;
}

model {
  real predict;
  
  //Relatively vague priors
  //We assume that the thetas come from a common distribution as they all should be 
  //measuring the same thing
  
  theta_raw ~ normal(0,5);
  //intercept can take any vague prior
    alpha ~ normal(0,5);
  
  //Model sampling statement -- bernoulli model with logit link function (equivalent to GLM with logit link)
  for(n in 1:N) {
    predict = inv_logit(alpha + x[n] * theta_raw);
  y ~ bernoulli(0.9 * predict + (1-(0.9*predict))*(weights[w[n]] - 0.3*pow(weights[w[n]],2)));  
  }
}
