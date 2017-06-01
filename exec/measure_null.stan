data {
  int N;
  int y[N];
}


parameters {
  
  
  real<lower=0,upper=1> mu;
}

model {
  
    mu ~ normal(0,5);
  
  //Model sampling statement -- bernoulli model with logit link function (equivalent to GLM with logit link)
  
  y ~ bernoulli(mu);  
}
