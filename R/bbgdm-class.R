#' @useDynLib bbgdm
#' @importFrom Rcpp sourceCpp
NULL

#' @title bbgdm objects
#' @rdname bbgdm
#' @name bbgdm
#' @param form formula for bbgdm model
#' @param sp.dat presence absence matrix, sp as columns sites as rows.
#' @param env.dat environmental or spatial covariates at each site.
#' @param family a description of the error distribution and link function to be used in the model. Currently "binomial" suppported.
#' This can be a character string naming a family function, a family function or the result of a call to a family function.
#' @param link a character string that assigns the link function to apply within the binomial model.
#' Default is 'logit', but 'negexp' and other binomial link functions can be called.
#' @param dism_metric dissimilarity metric to calculate for model. "bray_curtis" or "number_non_shared" currently avaliable.
#' @param nboot number of Bayesian Bootstraps to run, this is used to estimate variance around GDM models. Default is 100 iterations.
#' @param spline_type type of spline to use in GDM model. Default is monotonic isplines. Options are: "ispline" or "bspline".
#' @param spline_df Number of spline degrees of freedom.
#' @param spline_knots Number of spline knots.
#' @param geo logical If true geographic distance is calculated if
#' @param geo.type type of geographic distance to estimate, can call 'euclidean','greater_circle' or 'least_cost'. If least_cost is called extra parameters are required (lc_data, minr and maxr).
#' @param coord.names character.vector names of coordinates, default is c("X","Y")
#' @param lc_data NULL lc_cost data layer, in the form of a raster.
#' @param minr NULL range of values for marine data within the scope of the lc_cost raster. eg. min depth.
#' @param maxr NULL range of values for marine data within the scope of the lc_cost raster. eg. max depth.
#' @param optim.meth optimisation method options avaliable are 'optim' and 'nlmnib'
#' @param est.var logical if true estimated parameter variance using optimiser.
#' @param trace logical print extra optimisation outputs
#' @param prior numeric vector of starting values for intercept and splines
#' @param control control options for gdm calls \link[bbgdm]{gdm_control} as default.
#' @return a bbgdm model object
#' @export
#' @examples
#' sp.dat <- matrix(rbinom(200,1,.6),20,10)# presence absence matrix
#' env.dat <- simulate_covariates(sp.dat,2)
#' form <- ~ 1 + covar_1 + covar_2
#' test.bbgdm <- bbgdm(form,sp.dat, env.dat,family="binomial",dism_metric="number_non_shared",nboot=10,
#'                     geo=FALSE,optim.meth='nlmnib')

bbgdm <- function(form, sp.dat, env.dat, family="binomial",link='logit',
                  dism_metric="number_non_shared", nboot=100,
                  spline_type="ispline",spline_df=2,spline_knots=1,
                  geo=TRUE,geo.type='euclidean',coord.names=c("X","Y"),lc_data=NULL,minr=0,maxr=NULL,
                  optim.meth="nlmnib", est.var=FALSE, trace=FALSE,prior=FALSE,control=bbgdm.control()){

  cat(family,"regression is on the way. \n")
    if (is.character(family))
      family <- get(family, mode = "function", envir = parent.frame())
    if (is.function(family))
      family <- family()
    if (is.null(family$family)) {
      print(family)
      stop("'family' not recognized")
    }
  if(dism_metric=="number_non_shared") left <- "cbind(nonsharedspp_ij,sumspp_ij)"
  if(dism_metric=="bray_curtis") left <- "cbind(dissimilarity,100)"
  if(geo) { form <- update.formula(form, ~ X + Y + .)
            if(!all(coord.names %in% colnames(env.dat)))
            {
              stop(cat("Coordinates are missing, add coordinate data as columns called 'X' & 'Y'\n"))
            }
  }
  env.dat <- model.frame(form, as.data.frame(env.dat))
  mean.env.dat <- sd.env.dat <- NA
  env.dat <- model.frame(as.data.frame(env.dat))
  dissim_dat <- dissim_table(sp.dat,env.dat,dism_metric=dism_metric,spline_type=spline_type,spline_df=spline_df,spline_knots=spline_knots,
                             geo=geo,geo.type=geo.type,lc_data=lc_data,minr=minr,maxr=maxr)
  dissim_dat_table <- as.data.frame(dissim_dat$diff_table)
  dissim_dat_params <- dissim_dat$diff_table_params
  if(dism_metric=="number_non_shared") preds <- colnames(dissim_dat_table[,3:ncol(dissim_dat_table)])
  else preds <- colnames(dissim_dat_table[,2:ncol(dissim_dat_table)])
  form <- update.formula(form, paste0(left," ~ ",paste(preds, collapse=" + ")))
  temp <- model.frame(form, as.data.frame(dissim_dat_table))
  y <- model.response(temp)
  X <- model.matrix(form, as.data.frame(dissim_dat_table))
  mod  <- bbgdm.fit(X,y,link=link,optim.meth=optim.meth,est.var=TRUE,trace=trace,prior=prior,control=control)
  Nsite <- nrow(sp.dat)
  nreps <- nboot
  boot_print <- nboot/10
  mods <- list()
    for (ii in 1:nreps){
      w <- gtools::rdirichlet(Nsite, rep(1/Nsite,Nsite))
      wij <- w%*%t(w)
      wij <- wij[upper.tri(wij)]
      mods[[ii]] <- bbgdm.fit(X,y,wt=wij,link=link,optim.meth=optim.meth,est.var=est.var,trace=trace,prior=prior,control=control)
      if(ii %% boot_print ==0 ) cat("Bayesian bootstrap ", ii, " iterations\n")
    }

  #summary stats
  all.stats.ll <- plyr::ldply(mods, function(x) c(ll=x$logl,AIC=x$AIC,BIC=x$BIC,x$null.deviance,x$gdm.deviance,x$deviance.explained))
  median.ll <- apply( plyr::ldply(mods, function(x) c(ll=x$logl,AIC=x$AIC,BIC=x$BIC,x$null.deviance,x$gdm.deviance,x$deviance.explained)),2,median,na.rm=T)
  quantiles.ll <- apply( plyr::ldply(mods, function(x) c(ll=x$logl,AIC=x$AIC,BIC=x$BIC,x$null.deviance,x$gdm.deviance,x$deviance.explained)),2,function(x)quantile(x,c(.05,.95),na.rm=T))
  all.coefs.se <-  plyr::ldply(mods, function(x) c(x$coef))
  median.coefs.se <- apply(plyr::ldply(mods, function(x) c(x$coef)),2,median,na.rm=T)
  quantiles.coefs.se <- apply(plyr::ldply(mods, function(x) c(x$coef)),2,function(x)quantile(x,c(.05,.95),na.rm=T))

  bbgdm.results <- list()
  bbgdm.results$starting_gdm <- mod
  bbgdm.results$bb_gdms <- mods
  bbgdm.results$all.stats.ll <- all.stats.ll
  bbgdm.results$median.ll <- median.ll
  bbgdm.results$quantiles.ll <- quantiles.ll
  bbgdm.results$all.coefs.se <- all.coefs.se
  bbgdm.results$median.coefs.se <- median.coefs.se
  bbgdm.results$quantiles.coefs.se <- quantiles.coefs.se
  bbgdm.results$nboots <-nboot
  bbgdm.results$formula <- form
  bbgdm.results$dism_metric <- dism_metric
  bbgdm.results$sp.dat <- sp.dat
  bbgdm.results$env.dat <- env.dat
  bbgdm.results$X <- X
  bbgdm.results$y <- y
  bbgdm.results$dissim_dat <- dissim_dat_table
  bbgdm.results$dissim_dat_params <- dissim_dat_params
  bbgdm.results$family <- as.character(family)[1]
  bbgdm.results$geo <- geo
  bbgdm.results$link <- link
  if(geo){
    bbgdm.results$geo.type <- geo.type
    bbgdm.results$lc_data=lc_data
    bbgdm.results$minr=minr
    bbgdm.results$maxr=maxr
  }
  class(bbgdm.results) <- "bbgdm"
  return(bbgdm.results)
}

#' @rdname bbgdm
#' @name plot.bbgdm
#' @param object As derived from bbgdm function
#' @export
#' @examples
#' #plot bbgdm fit
#' plot(test.bbgdm)
#'
## plotting
plot.bbgdm <- function(object,...){
  if(nrow(object$X)>200) pred_sample <- 200
  else pred_sample <- nrow(object$X)
  link <-object$link
  if(link=='negexp') link.fun <- bbgdm::negexp()
  else link.fun <- make.link(link=link)
  X <- object$X
  Y <- object$starting_gdm$y
  bb.eta <- X%*%object$median.coefs.se
  bb.eta.05 <- X%*%object$quantiles.coefs.se[1,]
  bb.eta.95 <- X%*%object$quantiles.coefs.se[2,]
  bb.pred <- link.fun$linkinv(bb.eta)
  plot(bb.eta,Y[,1]/Y[,2], xlab = "Linear Predictor",
       ylab = paste0("Observed ",object$dism_metric," dissimilarity"), type = "n",ylim=c(0,1),...)
  points(bb.eta,Y[,1]/Y[,2], pch = 20, cex = 0.25)
  y.pred <- Y[sample(pred_sample),]
  y.pred <- y.pred[order(y.pred[,2], y.pred[,1]),]
  overlayX.bb <- seq(from = min(bb.eta), to = max(bb.eta),
                     length = pred_sample)
  overlayY.bb <- link.fun$linkinv(overlayX.bb)
  lines(overlayX.bb, overlayY.bb,...)
}


#' @rdname bbgdm
#' @name predict.bbgdm
#' @param object As derived from bbgdm function
#' @param data raster stack of the same covariates used to fit model object for the region you wish to predict too.
#' @param neigbourhood int default is three, number of neighbouring cells to estimate mean dissimilarity.
#' @param outer logical default is FALSE, if TRUE only calculates the outer edge of neighbourhoods area.
#' @param uncertainty logical if TRUE predict will return a list with two rasters the mean estimate and the uncertainty (defined as the coefficent of variation)
#' @return raster of mean turnover estimated based on neighbourhood distance.
#' @export


predict.bbgdm <- function (object, data, neighbourhood=NULL, outer=FALSE, uncertainty=TRUE,...)
{
  options(warn.FPU = FALSE)
  if (class(data) != "RasterStack" & class(data) != "RasterLayer" &
      class(data) != "RasterBrick") {
    stop("Prediction data need to be a raster object")
  }
  if (nlayers(data) != ncol(object$env.dat)) {
    stop("Number of raster layers does not equal the number used to fit the model")
  }
  for (i in 1:nlayers(data)) {
    if (names(object$env.dat)[i] != names(data)[i]) {
      stop("Raster layers don't match variables used to fit the model - check they are in the correct order")
    }
  }
  if(is.null(neighbourhood)){
    cat('using default three cell neighbourhood to estimate dissimilarity')
    neighbourhood <- 3
  }
  #create neighbour matrix
  rel<-expand.grid(seq(-neighbourhood,neighbourhood,1),seq(-neighbourhood,neighbourhood,1))
  if (outer) rel <-rel[(rel[,1]==-neighbourhood | rel[,1]==neighbourhood | rel[,2]==-neighbourhood | rel[,2]==neighbourhood),]
  rel<-as.matrix(rel[,c(2,1)])
  max.dist<-max(rel)
  rel<-cbind(rel,(1-((sqrt((rel[,1]^2)+(rel[,2]^2))/max.dist))))

  #create updated i-spline rasters (transform layers to i-spline values)
  XYdata <- as.data.frame(na.omit(rasterToPoints(data,progress = "text")))
  cells <- cellFromXY(data[[1]], cbind(XYdata$x, XYdata$y))
  data_spline <- spline.trans(XYdata[,-1:-2],spline_type = "ispline",spline_df=2)
  st_data <- as.data.frame(cbind(XYdata[,1:2], data_spline$spline))
  coordinates(st_data) <- ~x+y
  suppressWarnings(gridded(st_data) <- TRUE)
  data_stack <- stack(st_data)

  beta.r <- data[[1]]
  beta.r[cells]<-1
  intercept <- beta.r
  rs <- stack(intercept,data_stack)
  bbgdm_coef <- as.vector(object$median.coefs.se)
  raster_data <- raster::as.array(rs)
  beta_mat <- raster::as.matrix(beta.r)
  beta.r[] <- bbgdm::pred_bbgdm_cpp(raster_data,beta_mat,rel,bbgdm_coef)
  if(uncertainty){
    beta.r.lw <- data[[1]]
    beta.r.up <- data[[1]]
    beta.r.lw[cells]<-1
    beta.r.up[cells]<-1
    bbgdm_coef.lw <- as.vector(object$quantiles.coefs.se[1,])
    bbgdm_coef.up <- as.vector(object$quantiles.coefs.se[2,])
    beta.r.lw[] <- bbgdm::pred_bbgdm_cpp(raster_data,beta_mat,rel,bbgdm_coef.lw)
    beta.r.up[] <- bbgdm::pred_bbgdm_cpp(raster_data,beta_mat,rel,bbgdm_coef.up)
    pred.se <- abs(beta.r.up-beta.r.lw)/beta.r
  }
  if(uncertainty) return(list(mean.beta=beta.r,se.beta=pred.se))
  else return(beta.r)
}