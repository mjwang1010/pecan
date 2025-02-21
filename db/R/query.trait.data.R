#-------------------------------------------------------------------------------
# Copyright (c) 2012 University of Illinois, NCSA.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the
# University of Illinois/NCSA Open Source License
# which accompanies this distribution, and is available at
# http://opensource.ncsa.illinois.edu/license.html
#-------------------------------------------------------------------------------
##--------------------------------------------------------------------------------------------------#
##' Queries data from the trait database and transforms statistics to SE
##'
##' Performs query and then uses \code{transformstats} to convert miscellaneous statistical summaries
##' to SE
##' @name fetch.stats2se
##' @title Fetch data and transform stats to SE
##' @param connection connection to trait database
##' @param query to send to databse
##' @return dataframe with trait data
##' @seealso used in \code{\link{query.trait.data}}; \code{\link{transformstats}} performs transformation calculations
##' @author <unknown>
fetch.stats2se <- function(connection, query){
  transformed <- transformstats(db.query(query, connection))
  return(transformed)
}
##==================================================================================================#


##--------------------------------------------------------------------------------------------------#
##'
##' Function to query data from database for specific species and convert stat to SE
##'
##' @name query.data
##' @title Query data and transform stats to SE by calling \code{\link{fetch.stats2se}};
##' @param trait trait to query from the database
##' @param spstr
##' @param extra.columns
##' @param con database connection
##' @param ... extra arguments
##' @seealso used in \code{\link{query.trait.data}}; \code{\link{fetch.stats2se}}; \code{\link{transformstats}} performs transformation calculations
##' @author David LeBauer, Carl Davidson
query.data <- function(trait, spstr, extra.columns='ST_X(ST_CENTROID(sites.geometry)) AS lon, ST_Y(ST_CENTROID(sites.geometry)) AS lat, ', con=NULL, store.unconverted=FALSE, ...) {
  if (is.null(con)) {
    logger.error("No open database connection passed in.")
    con <- db.open(settings$database$bety)
  }
  query <- paste("select
              traits.id, traits.citation_id, traits.site_id, traits.treatment_id,
              treatments.name, traits.date, traits.time, traits.cultivar_id, traits.specie_id,
              traits.mean, traits.statname, traits.stat, traits.n, variables.name as vname,
              extract(month from traits.date) as month,",
            extra.columns,
            "treatments.control, sites.greenhouse
              from traits
              left join treatments on  (traits.treatment_id = treatments.id)
              left join sites on (traits.site_id = sites.id)
              left join variables on (traits.variable_id = variables.id)
            where specie_id in (", spstr,")
            and variables.name in ('", trait,"');", sep = "")
  result <- fetch.stats2se(con, query)
  
  if(store.unconverted) {
    result$mean_unconverted <- result$mean
    result$stat_unconverted <- result$stat
  }
  
  return(result)
  db.close(con)
}
##==================================================================================================#


##--------------------------------------------------------------------------------------------------#
##'
##' Function to query yields data from database for specific species and convert stat to SE
##'
##' @name query.yields
##' @title Query yield data and transform stats to SE by calling \code{\link{fetch.stats2se}};
##' @param trait yield trait to query
##' @param spstr species to query for yield data
##' @param extra.columns
##' @param con database connection
##' @param ... extra arguments
##' @seealso used in \code{\link{query.trait.data}}; \code{\link{fetch.stats2se}}; \code{\link{transformstats}} performs transformation calculations
##' @author <unknown>
query.yields <- function(trait = 'yield', spstr, extra.columns='', con=NULL, ...){
  query <- paste("select
            yields.id, yields.citation_id, yields.site_id, treatments.name,
            yields.date, yields.time, yields.cultivar_id, yields.specie_id,
            yields.mean, yields.statname, yields.stat, yields.n,
            variables.name as vname,
            month(yields.date) as month,",
                 extra.columns,
                 "treatments.control, sites.greenhouse
          from yields
            left join treatments on  (yields.treatment_id = treatments.id)
            left join sites on (yields.site_id = sites.id)
            left join variables on (yields.variable_id = variables.id)
          where specie_id in (", spstr,");", sep = "")
  if(!trait == 'yield'){
    query <- gsub(");", paste(" and variables.name in ('", trait,"');", sep = ""), query)
  }

  return(fetch.stats2se(con, query))
}
##==================================================================================================#


######################## COVARIATE FUNCTIONS #################################

##--------------------------------------------------------------------------------------------------#
##'
##' @name append.covariate
##' @title Append covariate data as a column within a table
##' \code{append.covariate} appends a data frame of covariates as a new column in a data frame 
##'   of trait data.
##' In the event a trait has several covariates available, the first one found 
##'   (i.e. lowest row number) will take precedence
##'
##' @param data trait dataframe that will be appended to.
##' @param column.name name of the covariate as it will appear in the appended column
##' @param covariates.data one or more tables of covariate data, ordered by the precedence
##' they will assume in the event a trait has covariates across multiple tables.
##' All tables must contain an 'id' and 'level' column, at minimum.
##'
##' @author Carl Davidson, Ryan Kelly
##' @export
##--------------------------------------------------------------------------------------------------#
append.covariate<-function(data, column.name, covariates.data){
  # Keep only the highest-priority covariate for each trait
  covariates.data <- covariates.data[!duplicated(covariates.data$trait_id), ]

  # Select columns to keep, and rename the covariate column
  covariates.data <- covariates.data[, c('trait_id', 'level')]
  names(covariates.data) <- c('id', column.name)

  # Merge on trait ID
  merged <- merge(covariates.data, data, all = TRUE, by = "id")
  return(merged)
}
##==================================================================================================#


##--------------------------------------------------------------------------------------------------#
##'
##' @name query.covariates
##' @title Queries covariates from database for a given vector of trait id's
##'
##' @param trait.ids list of trait ids
##' @param con database connection
##' @param ... extra arguments
##'
##' @author <unknown>
query.covariates<-function(trait.ids, con = NULL, ...){
  covariate.query <- paste("select covariates.trait_id, covariates.level,variables.name",
                           "from covariates left join variables on variables.id = covariates.variable_id",
                           "where trait_id in (",vecpaste(trait.ids),")")
  covariates <- db.query(covariate.query, con)
  return(covariates)
}
##==================================================================================================#


##--------------------------------------------------------------------------------------------------#
##'
##' @name arrhenius.scaling.traits
##' @title Function to apply Arrhenius scaling to 25 degC for temperature-dependent traits
##' @param data data frame of data to scale, as returned by query.data()
##' @param covariates data frame of covariates, as returned by query.covariates().
##'   Note that data with no matching covariates will be unchanged. 
##' @param temp.covariates names of covariates used to adjust for temperature;
##'   if length > 1, order matters (first will be used preferentially)
##' @param new.temp the reference temperature for the scaled traits. Curerntly 25 degC
##' @param missing.temp the temperature assumed for traits with no covariate found. Curerntly 25 degC
##' @author Carl Davidson, David LeBauer, Ryan Kelly
arrhenius.scaling.traits <- function(data, covariates, temp.covariates, new.temp=25, missing.temp=25){
  # Select covariates that match temp.covariates
  covariates <- covariates[covariates$name %in% temp.covariates,]
    
  if(nrow(covariates)>0) {
    # Sort covariates in order of priority
    covariates <- do.call(rbind, 
      lapply(temp.covariates, function(temp.covariate) covariates[covariates$name == temp.covariate, ])
      )
  
    data <- append.covariate(data, 'temp', covariates)

    # Assign default value for traits with no covariates
    data$temp[is.na(data$temp)] <- missing.temp
    
    # Scale traits
    data$mean <- arrhenius.scaling(data$mean, old.temp = data$temp, new.temp=new.temp)
    data$stat <- arrhenius.scaling(data$stat, old.temp = data$temp, new.temp=new.temp)

    #remove temporary covariate column.
    data<-data[,colnames(data)!='temp']
  }
  return(data)
}
##==================================================================================================#


##--------------------------------------------------------------------------------------------------#
##'
##' @name filter.sunleaf.traits
##' @title Function to filter out upper canopy leaves
##' @param data input data
##' @param covariates covariate data
##'
##' @author <unknown>
filter.sunleaf.traits <- function(data, covariates){
  if(length(covariates)>0) {
    data <- append.covariate(data, 'canopy_layer',
                             covariates[covariates$name == 'canopy_layer',])
    data <-  data[data$canopy_layer >= 0.66 | is.na(data$canopy_layer),]
    
    # remove temporary covariate column
    data<-data[,colnames(data)!='canopy_layer']
  }
  return(data)
}
##==================================================================================================#


##--------------------------------------------------------------------------------------------------#
##'
##' @name rename.jags.columns
##'
##' @title \code{rename.jags.columns} renames the variables within output data frame trait.data
##'
##' @param data data frame to with variables to rename
##'
##' @seealso used with \code{\link{jagify}};
##' @export
rename.jags.columns <- function(data) {

                                        # Change variable names and calculate obs.prec within data frame
  transformed <-  transform(data,
                            Y        = mean,
                            se       = stat,
                            obs.prec = 1 / (sqrt(n) * stat) ^2,
                            trt      = trt_id,
                            site     = site_id,
                            cite     = citation_id,
                            ghs      = greenhouse)

                                        # Subset data frame
  selected <- subset(transformed, select = c('Y', 'n', 'site', 'trt', 'ghs', 'obs.prec',
                                    'se', 'cite'))
                                        # Return subset data frame
  return(selected)
}
##==================================================================================================#



##--------------------------------------------------------------------------------------------------#
##' Change treatments to sequential integers
##'
##' Assigns all control treatments the same value, then assigns unique treatments
##' within each site. Each site is required to have a control treatment.
##' The algorithm (incorrectly) assumes that each site has a unique set of experimental
##' treatments.
##' @name assign.treatments
##' @title assign.treatments
##' @param data input data
##' @return dataframe with sequential treatments
##' @export
##' @author David LeBauer, Carl Davidson
assign.treatments <- function(data){
  data$trt_id[which(data$control == 1)] <- 'control'
  sites <- unique(data$site_id)
  for(ss in sites){
    site.i <- data$site_id == ss
    #if only one treatment, it's control
    if(length(unique(data$trt_id[site.i])) == 1) data$trt_id[site.i] <- 'control'
    if(!'control' %in% data$trt_id[site.i]){
      logger.severe('No control treatment set for site_id:',
                   unique(data$site_id[site.i]),
                   'and citation id',
                   unique(data$citation_id[site.i]),
                   '\nplease set control treatment for this site / citation in database\n')
    }
  }
  return(data)
}
drop.columns <- function(data, columns){
  return(data[,which(!colnames(data) %in% columns)])
}
##==================================================================================================#


##--------------------------------------------------------------------------------------------------#
##' sample from normal distribution, given summary stats
##'
##' @name take.samples
##' @title Sample from normal distribution, given summary stats
##' @param trait data.frame with values of mean and sd
##' @param sample.size
##' @return sample of length sample.size
##' @author David LeBauer, Carl Davidson
##' @export
##' @examples
##' ## return the mean when stat = NA
##' take.samples(summary = data.frame(mean = 10, stat = NA))
##' ## return vector of length \code{sample.size} from N(mean,stat)
##' take.samples(summary = data.frame(mean = 10, stat = 10), sample.size = 10)
##'
take.samples <- function(summary, sample.size = 10^6){
  if(is.na(summary$stat)){
    ans <- summary$mean
  } else {
    set.seed(0)
    ans <- rnorm(sample.size, summary$mean, summary$stat)
  }
  return(ans)
}
##==================================================================================================#


##--------------------------------------------------------------------------------------------------#
##'
##' Performs an arithmetic function, FUN, over a series of traits and returns
##' the result as a derived trait.
##' Traits must be specified as either lists or single row data frames,
##' and must be either single data points or normally distributed.
##' In the event one or more input traits are normally distributed,
##' the resulting distribution is approximated by numerical simulation.
##' The output trait is effectively a copy of the first input trait with
##' modified mean, stat, and n.
##'
##' @name derive.trait
##' @title Performs an arithmetic function, FUN, over a series of traits and returns the result as a derived trait.
##' @param FUN arithmetic function
##' @param ... traits that will be supplied to FUN as input
##' @param sample.size number of random samples generated by rnorm for normally distributed trait input
##' @return a copy of the first input trait with mean, stat, and n reflecting the derived trait
##' @export
##' @examples
##' input <- list(x = data.frame(mean = 1, stat = 1, n = 1))
##' derive.trait(FUN = identity, input = input, var.name = 'x')
derive.trait <- function(FUN, ..., input=list(...), var.name=NA, sample.size=10^6){
  if(any(lapply(input, nrow) > 1)){
    return(NULL)
  }
  input.samples <- lapply(input, take.samples, sample.size=sample.size)
  output.samples <- do.call(FUN, input.samples)
  output<-input[[1]]
  output$mean<-mean(output.samples)
  output$stat<-ifelse(length(output.samples) > 1, sd(output.samples), NA)
  output$n <- min(sapply(input, function(trait){trait$n}))
  output$vname <- ifelse(is.na(var.name), output$vname, var.name)
  return(output)
}
##==================================================================================================#


##--------------------------------------------------------------------------------------------------#
##' Equivalent to derive.trait(), but operates over a series of trait datasets,
##' as opposed to individual trait rows. See \code{\link{derive.trait}}; for more information.
##'
##' @name derive.traits
##' @title Performs an arithmetic function, FUN, over a series of traits and returns the result as a derived trait.
##' @export
##' @param FUN arithmetic function
##' @param ... trait datasets that will be supplied to FUN as input
##' @param sample.size where traits are normally distributed with a given
##' @param match.columns in the event more than one trait dataset is supplied,
##'        this specifies the columns that identify a unique data point
##' @return a copy of the first input trait with modified mean, stat, and n
derive.traits <- function(FUN, ..., input=list(...),
                          match.columns=c('citation_id', 'site_id', 'specie_id'),
                          var.name=NA, sample.size=10^6){
  if(length(input) == 1){
    input<-input[[1]]
                                        #KLUDGE: modified to handle empty datasets
    for(i in (0:nrow(input))[-1]){
      input[i,]<-derive.trait(FUN, input[i,], sample.size=sample.size)
    }
    return(input)
  }
  else if(length(match.columns) > 0){
                                        #function works recursively to reduce the number of match columns
    match.column <- match.columns[[1]]
                                        #find unique values within the column that intersect among all input datasets
    columns <- lapply(input, function(data){data[[match.column]]})
    intersection <- Reduce(intersect, columns)

                                        #run derive.traits() on subsets of input that contain those unique values
    derived.traits<-lapply(intersection,
                           function(id){
                             filtered.input <- lapply(input,
                                                      function(data){data[data[[match.column]] == id,]})
                             derive.traits(FUN, input=filtered.input,
                                           match.columns=match.columns[-1],
                                           var.name=var.name,
                                           sample.size=sample.size)
                           })
    derived.traits <- derived.traits[!is.null(derived.traits)]
    derived.traits <- do.call(rbind, derived.traits)
    return(derived.traits)
  }
  else{
    return(derive.trait(FUN, input=input,
                        var.name=var.name, sample.size=sample.size))
  }
}
##==================================================================================================#


##--------------------------------------------------------------------------------------------------#
##' Extract trait data from database
##' @name query.trait.data
##' @title Extract trait data from database
##' Extracts data from database for a given trait and set of species,
##' converts all statistics to summary statistics, and prepares a dataframe for use in meta-analysis.
##' For Vcmax and SLA data, only data collected between  April and July are queried, and only data collected from the top of the canopy (canopy height > 0.66).
##' For Vcmax and root_respiration_rate, data are scaled
##' converted from measurement temperature to \eqn{25^oC} via the arrhenius equation.
##'
##' @param trait is the trait name used in the database, stored in variables.name
##' @param spstr is the species.id integer or string of integers associated with the species
##'
##' @return dataframe ready for use in meta-analysis
##' @export
##' @examples
##' \dontrun{
##' settings <- read.settings()
##' query.trait.data("Vcmax", "938", con = con)
##' }
##' @author David LeBauer, Carl Davidson, Shawn Serbin
query.trait.data <- function(trait, spstr, con = NULL, update.check.only=FALSE, ...){

  if(is.list(con)){
    print("query.trait.data")
    print("WEB QUERY OF DATABASE NOT IMPLEMENTED")
    return(NULL)
  }

  # print trait info
  if(!update.check.only) {
    print("---------------------------------------------------------")
    print(trait)
  }

### Query the data from the database for trait X.
  data <- query.data(trait, spstr, con=con, store.unconverted=TRUE)

### Query associated covariates from database for trait X.
  covariates <- query.covariates(data$id, con=con)
  canopy.layer.covs <- covariates[covariates$name == 'canopy_layer', ]

### Set small sample size for derived traits if update-checking only. Otherwise use default.
  if(update.check.only) {
    sample.size <- 10 
  } else {
    sample.size <- 10^6  ## Same default as derive.trait(), derive.traits(), and take.samples()
  }

  if(trait == 'Vcmax') {
#########################   VCMAX   ############################
### Apply Arrhenius scaling to convert Vcmax at measurement temp to that at 25 degC (ref temp).
    data <- arrhenius.scaling.traits(data, covariates, c('leafT', 'airT','T'))

### Keep only top of canopy/sunlit leaf samples based on covariate.
    if(nrow(canopy.layer.covs) > 0) data <- filter.sunleaf.traits(data, canopy.layer.covs)

    ## select only summer data for Panicum virgatum
    ##TODO fix following hack to select only summer data
    if (spstr == "'938'"){
      data <- subset(data, subset = data$month %in% c(0,5,6,7))
    }

  } else if (trait == 'SLA') {
#########################    SLA    ############################
    ## convert LMA to SLA
    data <- rbind(data,
                  derive.traits(function(lma){1/lma},
                                query.data('LMA', spstr, con=con, store.unconverted=TRUE),
                                sample.size=sample.size))

    ### Keep only top of canopy/sunlit leaf samples based on covariate.
    if(nrow(canopy.layer.covs) > 0) data <- filter.sunleaf.traits(data, canopy.layer.covs)

    ## select only summer data for Panicum virgatum
    ##TODO fix following hack to select only summer data
    if (spstr == "'938'"){
      data <- subset(data, subset = data$month %in% c(0,5,6,7,8,NA))
    }

  } else if (trait == 'leaf_turnover_rate'){
#########################    LEAF TURNOVER    ############################
    ## convert LMA to SLA
    data <- rbind(data,
                  derive.traits(function(leaf.longevity){1/leaf.longevity},
                                query.data('Leaf Longevity', spstr, con=con, store.unconverted=TRUE),
                                sample.size=sample.size))

  } else if (trait == 'root_respiration_rate') {
#########################  ROOT RESPIRATION   ############################
    ## Apply Arrhenius scaling to convert root respiration at measurement temp
    ## to that at 25 degC (ref temp).
    data <- arrhenius.scaling.traits(data, covariates, c('rootT', 'airT','soilT'))

  } else if (trait == 'leaf_respiration_rate_m2') {
#########################  LEAF RESPIRATION   ############################
    ## Apply Arrhenius scaling to convert leaf respiration at measurement temp
    ## to that at 25 degC (ref temp).
  data <- arrhenius.scaling.traits(data, covariates, c('leafT', 'airT','T'))

  } else if (trait == 'stem_respiration_rate') {
#########################  STEM RESPIRATION   ############################
    ## Apply Arrhenius scaling to convert stem respiration at measurement temp
    ## to that at 25 degC (ref temp).
    data <- arrhenius.scaling.traits(data, covariates, c('leafT', 'airT'))

  } else if (trait == 'c2n_leaf') {
#########################  LEAF C:N   ############################

    data <- rbind(data,
                  derive.traits(function(leafN){48/leafN},
                                query.data('leafN', spstr, con=con, store.unconverted=TRUE),
                                sample.size=sample.size))

  } else if (trait == 'fineroot2leaf') {
#########################  FINE ROOT ALLOCATION  ############################
    ## FRC_LC is the ratio of fine root carbon to leaf carbon
    data<-rbind(data, query.data('FRC_LC', spstr, con=con, store.unconverted=TRUE))
  }
  result <- data

  ## if result is empty, stop run

  if(nrow(result)==0) {
    return(NA)
    warning(paste("there is no data for", trait))
  } else {

    ## Do we really want to print each trait table?? Seems like a lot of
    ## info to send to console.  Maybe just print summary stats?
    ## print(result)
    if(!update.check.only) {
      print(paste("Median ",trait," : ",round(median(result$mean,na.rm=TRUE),digits=3),sep=""))
      print("---------------------------------------------------------")
    }
    # print list of traits queried and number by outdoor/glasshouse
    return(result)
  }
}
##==================================================================================================#


####################################################################################################
### EOF.  End of R script file.
####################################################################################################
