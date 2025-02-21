##' Currently assumes an exponential spatial dependency
##' 
##' can make gaussian by passing squared distance matrix
##' 
##' @name calcSpatialCov.list
##' @title calcSpatialCov.list 
##' @export
##'
##' @param d list of component spatial distance matrices
##' @param psi spatial corr
##' @param tau spatial var
##' 
##' @author Michael Dietze
`calcSpatialCov.list` <-
function(d,psi,tau){
  m <- length(d)
  nl <- nrow(d[[1]])
  H <- matrix(0,nl,nl)
  if(length(psi) == 1 && m > 1){
    ##apply same psi to all directions
    psi <- rep(psi,m)
  }
  #for(i in 1:nl){
  #  for(j in i:nl){
  #    tmp <- 0
  #    for(k in 1:m){tmp <- tmp - psi[k]*d[[k]][i,j]}
  #    H[i,j] <- tau*exp(tmp)
  #    H[j,i] <- H[i,j]
  #  }
  #}
  for(k in 1:m) H <- H - psi[k]*d[[k]]
  H <- tau*exp(H)
  return(H)
}

