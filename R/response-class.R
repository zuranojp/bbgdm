#' @title response objects
#' @rdname response
#' @name as.response
#' @description extracts spline reponses from \code{bbgdm} object and plots them.
#' @param object As derived from bbgdm function.
#' @param \dots pass further arguments to \code{plot()}.
#' @return values for plotting spline responses from bbgdm.
#' @export
#' @examples
#' # fit bbgdm and extract spline responses.
#' x <-matrix(rbinom(1:100,1,.6),10,10)# presence absence matrix
#' y <- simulate_covariates(x,2)
#' form <- ~ 1 + covar_1 + covar_2
#' test.bbgdm <- bbgdm(form, sp.dat=x, env.dat=y,family="binomial",
#'                    geo=FALSE,dism_metric="number_non_shared", nboot=10)
#' responses <- as.response(test.bbgdm)
#'


as.response <- function(object){
  Xold <- data.matrix(object$dissim_dat)
  splineLength <- sapply(object$dissim_dat_params, `[[`, "dim")[2,]
  betas <- object$median.coefs.se[2:length(object$median.coefs.se)]
  betas.quantiles <- object$quantiles.coefs.se[,2:length(object$starting_gdm$coef),drop=FALSE]
  if(object$geo){ k <- ncol(object$env.dat)-1
                  coords <- as.matrix(object$env.dat[,c("X","Y")])
                  geos <- calc_geo_dist(coords,geo.type=object$geo.type)
                  nr_df<-((nrow(object$sp.dat)^2)-nrow(object$sp.dat))/2
                  nc_dt<-ncol(object$env.dat)
                  ne<-ncol(object$env.dat)
                  diff_table <- diff_table_cpp(as.matrix( object$env.dat[-which(names(object$env.dat) %in% c("X","Y"))]))
                  diff_table <- as.data.frame(cbind(geos[,5],diff_table))
                  colnames(diff_table) <-c('geo',colnames(object$env.dat[-which(names(object$env.dat) %in% c("X","Y"))]))
  } else {
    k <- ncol(object$env.dat)
    nr_df<-((nrow(object$sp.dat)^2)-nrow(object$sp.dat))/2
    nc_dt<-ncol(object$env.dat)
    ne<-ncol(object$env.dat)
    diff_table <- diff_table_cpp(as.matrix(object$env.dat))
    colnames(diff_table) <-c(colnames(object$env.dat))
  }
      grid <- matrix(rep(seq(0, 1, length.out = 100), k), ncol = k)
      grid <- t(t(grid) * as.vector(diff(apply(diff_table, 2, range))) + apply(diff_table, 2, min))
      grid <- data.frame(grid)
      min_env <- apply(object$env.dat,2,function(x)min(abs(x)))
      max_env <- apply(object$env.dat,2,function(x)max(abs(x)))
      if(object$geo){
         min_env <- c(min(grid[,1]),min_env[-1:-2])
         max_env <- c(max(grid[,1]),max_env[-1:-2])
      }
      grid_real <- grid
      for(i in 1:ncol(grid)) grid_real[,i] <-  scales::rescale(grid[,i],to=c(min_env[i],max_env[i]))
      X <- mapply(spline_trans_for_pred, grid, attrib = object$dissim_dat_params,
                  SIMPLIFY = FALSE)
      l <- sapply(object$dissim_dat_params, `[[`, "dim")[2, ]
      at <- unlist(mapply(rep, 1:k, l))
      bspl <- lapply(1:k, function(i) betas[at == i])
      bspl.05 <- lapply(1:k, function(i) betas.quantiles[1,at == i])
      bspl.95 <- lapply(1:k, function(i) betas.quantiles[2,at == i])
      structure(list(bspl=bspl,bspl.05=bspl.05,bspl.95=bspl.95,X=X,
                     grid_real=grid_real,diff_table=diff_table),class='response')
      }

#' @rdname response
#' @name is.response
#' @export
#' @examples
#' # Did as.response work?
#' is.response(responses)
#'
is.response <- function (x) {
  # test whether x is a response x
  ans <- inherits(x, "response")
  # return the answer
  return (ans)

}

#' @rdname response
#' @method plot response
#' @param x response object created using \code{as.response}
#' @export
#' @examples
#' # plot responses
#' par(mfrow=c(1,2))
#' plot(responses)

plot.response <- function(x,...){
        Splinesum <- Spline.05 <- Spline.95 <- NULL
        # if(='list')x$X <- do.call(cbind, x$X)

        Splinessum <- mapply(`%*%`, x$X, x$bspl)
        Splines.05 <- mapply(`%*%`, x$X, x$bspl.05)
        Splines.95 <- mapply(`%*%`, x$X, x$bspl.95)
        # if(length(Splinessum[,1])>100){
        #   Splinessum<-Splinessum[sort(sample(length(Splinessum[,1]),100)),]
        #   Splines.05<-Splines.05[sort(sample(length(Splines.05[,1]),100)),]
        #   Splines.95<-Splines.95[sort(sample(length(Splines.95[,1]),100)),]
        # }
         for (i in 1:ncol(Splinessum)) {
              plot(x$grid_real[,i], Splinessum[,i],type='l', ylab = paste0("f(",colnames(x$diff_table)[i],")"),
                   xlab = colnames(x$diff_table)[i],ylim = range(c(Splinessum,Splines.05,Splines.95)))#,...)
              polygon(c(x$grid_real[, i],rev(x$grid_real[,i])),c(Splines.05[,i],rev(Splines.95[,i])),col="grey80",border=NA)
              lines(x$grid_real[,i], Splinessum[,i], col = "black",type = "l", lwd=2)
              mtext(paste0("(",letters[i],")"),adj = 0)
         }
}
