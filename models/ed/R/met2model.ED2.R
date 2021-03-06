#-------------------------------------------------------------------------------
# Copyright (c) 2012 University of Illinois, NCSA.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the
# University of Illinois/NCSA Open Source License
# which accompanies this distribution, and is available at
# http://opensource.ncsa.illinois.edu/license.html
#-------------------------------------------------------------------------------

## R Code to convert from NACP intercomparison NETCDF met files into ED2 ascii met files

## It requires the rhdf5 library, which is not available on CRAN, but by can be installed locally:
## >source('http://bioconductor.org/biocLite.R')
## >biocLite('rhdf5')

## If files already exist in 'Outfolder', the default function is NOT to overwrite them and only
## gives user the notice that file already exists. If user wants to overwrite the existing files,
## just change overwrite statement below to TRUE.


##' met2model wrapper for ED2
##'
##' @title met2model for ED2
##' @export
##' @param in.path location on disk where inputs are stored
##' @param in.prefix prefix of input and output files
##' @param outfolder location on disk where outputs will be stored
##' @param start_date the start date of the data to be downloaded (will only use the year part of the date)
##' @param end_date the end date of the data to be downloaded (will only use the year part of the date)
##' @param lst timezone offset to GMT in hours
##' @param overwrite should existing files be overwritten
##' @param verbose should the function be very verbose
##' @importFrom ncdf4 ncvar_get ncdim_def ncatt_get ncvar_add
met2model.ED2 <- function(in.path, in.prefix, outfolder, start_date, end_date, lst = 0, lat = NA,
                          lon = NA, overwrite = FALSE, verbose = FALSE, ...) {
  overwrite <- as.logical(overwrite)

  # results are stored in folder prefix.start.end
  start_date <- as.POSIXlt(start_date, tz = "UTC")
  end_date   <- as.POSIXlt(end_date, tz = "UTC")
  met_folder <- outfolder
  met_header <- file.path(met_folder, "ED_MET_DRIVER_HEADER")

  results <- data.frame(file = c(met_header),
                        host = c(PEcAn.utils::fqdn()),
                        mimetype = c("text/plain"),
                        formatname = c("ed.met_driver_header files format"),
                        startdate = c(start_date),
                        enddate = c(end_date),
                        dbfile.name = "ED_MET_DRIVER_HEADER",
                        stringsAsFactors = FALSE)

  ## check to see if the outfolder is defined, if not create directory for output
  dir.create(met_folder, recursive = TRUE, showWarnings = FALSE)

  ### FUNCTIONS
  dm <- c(0, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366)
  dl <- c(0, 32, 61, 92, 122, 153, 183, 214, 245, 275, 306, 336, 367)
  month <- c("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC")
  mon_num <- c("01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12")
  day2mo <- function(year, day) {
    leap      <- lubridate::leap_year(year)
    mo        <- rep(NA, length(day))
    mo[leap]  <- findInterval(day[leap], dl)
    mo[!leap] <- findInterval(day[!leap], dm)
    return(mo)
  }

  # get start/end year since inputs are specified on year basis
  start_year <- lubridate::year(start_date)
  end_year <- lubridate::year(end_date)
  day_secs <- udunits2::ud.convert(1, "day", "seconds")

  ## loop over files
  for (year in start_year:end_year) {
    ncfile <- file.path(in.path, paste(in.prefix, year, "nc", sep = "."))

    ## extract file root name froot <- substr(files[i],1,28) print(c(i,froot))

    ## open netcdf
    nc <- ncdf4::nc_open(ncfile)

    # check lat/lon
    flat <- try(ncdf4::ncvar_get(nc, "latitude"), silent = TRUE)
    if (!is.numeric(flat)) {
      flat <- nc$dim[[1]]$vals[1]
    }
    if (is.na(lat)) {
      lat <- flat
    } else if (lat != flat) {
      PEcAn.logger::logger.warn("Latitude does not match that of file", lat, "!=", flat)
    }

    flon <- try(ncdf4::ncvar_get(nc, "longitude"), silent = TRUE)
    if (!is.numeric(flon)) {
      flat <- nc$dim[[2]]$vals[1]
    }
    if (is.na(lon)) {
      lon <- flon
    } else if (lon != flon) {
      PEcAn.logger::logger.warn("Longitude does not match that of file", lon, "!=", flon)
    }

    ## determine GMT adjustment lst <- site$LST_shift[which(site$acro == froot)]

    ## extract variables
    lat  <- eval(parse(text = lat))
    lon  <- eval(parse(text = lon))
    sec  <- nc$dim$time$vals
    Tair <- ncdf4::ncvar_get(nc, "air_temperature")
    Qair <- ncdf4::ncvar_get(nc, "specific_humidity")  #humidity (kg/kg)
    U    <- ncdf4::ncvar_get(nc, "eastward_wind")
    V    <- ncdf4::ncvar_get(nc, "northward_wind")
    Rain <- ncdf4::ncvar_get(nc, "precipitation_flux")
    pres <- ncdf4::ncvar_get(nc, "air_pressure")
    SW   <- ncdf4::ncvar_get(nc, "surface_downwelling_shortwave_flux_in_air")
    LW   <- ncdf4::ncvar_get(nc, "surface_downwelling_longwave_flux_in_air")
    CO2  <- try(ncdf4::ncvar_get(nc, "mole_fraction_of_carbon_dioxide_in_air"), silent = TRUE)

    useCO2 <- is.numeric(CO2)

    ## convert time to seconds
    sec <- udunits2::ud.convert(sec, unlist(strsplit(nc$dim$time$units, " "))[1], "seconds")

    ncdf4::nc_close(nc)

    dt <- PEcAn.utils::seconds_in_year(year) / length(sec)

    toff <- -as.numeric(lst) * 3600 / dt

    ## buffer to get to GMT
    slen <- length(SW)
    Tair <- c(rep(Tair[1], toff), Tair)[1:slen]
    Qair <- c(rep(Qair[1], toff), Qair)[1:slen]
    U    <- c(rep(U[1], toff), U)[1:slen]
    V    <- c(rep(V[1], toff), V)[1:slen]
    Rain <- c(rep(Rain[1], toff), Rain)[1:slen]
    pres <- c(rep(pres[1], toff), pres)[1:slen]
    SW   <- c(rep(SW[1], toff), SW)[1:slen]
    LW   <- c(rep(LW[1], toff), LW)[1:slen]
    if (useCO2) {
      CO2 <- c(rep(CO2[1], toff), CO2)[1:slen]
    }

    ## build time variables (year, month, day of year)
    skip <- FALSE
    nyr <- floor(udunits2::ud.convert(length(sec) * dt, "seconds", "years"))
    yr   <- NULL
    doy  <- NULL
    hr   <- NULL
    asec <- sec
    for (y in seq(year, year + nyr - 1)) {
      diy <- PEcAn.utils::days_in_year(y)
      ytmp <- rep(y, udunits2::ud.convert(diy / dt, "days", "seconds"))
      dtmp <- rep(seq_len(diy), each = day_secs / dt)
      if (is.null(yr)) {
        yr  <- ytmp
        doy <- dtmp
        hr  <- rep(NA, length(dtmp))
      } else {
        yr  <- c(yr, ytmp)
        doy <- c(doy, dtmp)
        hr  <- c(hr, rep(NA, length(dtmp)))
      }
      rng <- length(doy) - length(ytmp):1 + 1
      if (!all(rng >= 0)) {
        skip <- TRUE
        PEcAn.logger::logger.warn(paste(year, "is not a complete year and will not be included"))
        break
      }
      asec[rng] <- asec[rng] - asec[rng[1]]
      hr[rng]   <- (asec[rng] - (dtmp - 1) * day_secs) / day_secs * 24
    }
    mo <- day2mo(yr, doy)
    if (length(yr) < length(sec)) {
      rng <- (length(yr) + 1):length(sec)
      if (!all(rng >= 0)) {
        skip <- TRUE
        PEcAn.logger::logger.warn(paste(year, "is not a complete year and will not be included"))
        break
      }
      yr[rng]  <- rep(y + 1, length(rng))
      doy[rng] <- rep(1:366, each = day_secs / dt)[1:length(rng)]
      hr[rng]  <- rep(seq(0, length = day_secs / dt, by = dt / day_secs * 24), 366)[1:length(rng)]
    }
    if (skip) {
      print("Skipping to next year")
      next
    }


    ## calculate potential radiation in order to estimate diffuse/direct
    cosz <- PEcAn.data.atmosphere::cos_solar_zenith_angle(doy, lat, lon, dt)

    rpot <- 1366 * cosz
    rpot <- rpot[1:length(SW)]

    SW[rpot < SW] <- rpot[rpot < SW]  ## ensure radiation < max
    ### this causes trouble at twilight bc of missmatch btw bin avergage and bin midpoint
    frac <- SW/rpot
    frac[frac > 0.9] <- 0.9  ## ensure some diffuse
    frac[frac < 0] <- 0
    frac[is.na(frac)] <- 0
    frac[is.nan(frac)] <- 0
    SWd <- SW * (1 - frac)  ## Diffuse portion of total short wave rad

    ### convert to ED2.1 hdf met variables
    n      <- length(Tair)
    nbdsfA <- (SW - SWd) * 0.57  # near IR beam downward solar radiation [W/m2]
    nddsfA <- SWd * 0.48  # near IR diffuse downward solar radiation [W/m2]
    vbdsfA <- (SW - SWd) * 0.43  # visible beam downward solar radiation [W/m2]
    vddsfA <- SWd * 0.52  # visible diffuse downward solar radiation [W/m2]
    prateA <- Rain  # precipitation rate [kg_H2O/m2/s]
    dlwrfA <- LW  # downward long wave radiation [W/m2]
    presA  <- pres  # pressure [Pa]
    hgtA   <- rep(50, n)  # geopotential height [m]
    ugrdA  <- U  # zonal wind [m/s]
    vgrdA  <- V  # meridional wind [m/s]
    shA    <- Qair  # specific humidity [kg_H2O/kg_air]
    tmpA   <- Tair  # temperature [K]
    if (useCO2) {
      co2A <- CO2 * 1e+06  # surface co2 concentration [ppm] converted from mole fraction [kg/kg]
    }

    ## create directory if(system(paste('ls',froot),ignore.stderr=TRUE)>0)
    ## system(paste('mkdir',froot))

    ## write by year and month
    for (y in year + 1:nyr - 1) {
      sely <- which(yr == y)
      for (m in unique(mo[sely])) {
        selm <- sely[which(mo[sely] == m)]
        mout <- paste(met_folder, "/", y, month[m], ".h5", sep = "")
        if (file.exists(mout)) {
          if (overwrite == TRUE) {
            file.remove(mout)
            rhdf5::h5createFile(mout)
          }
          if (overwrite == FALSE) {
            PEcAn.logger::logger.warn("The file already exists! Moving to next month!")
            next
          }
        } else {
          rhdf5::h5createFile(mout)
        }
        dims  <- c(length(selm), 1, 1)
        nbdsf <- array(nbdsfA[selm], dim = dims)
        nddsf <- array(nddsfA[selm], dim = dims)
        vbdsf <- array(vbdsfA[selm], dim = dims)
        vddsf <- array(vddsfA[selm], dim = dims)
        prate <- array(prateA[selm], dim = dims)
        dlwrf <- array(dlwrfA[selm], dim = dims)
        pres  <- array(presA[selm], dim = dims)
        hgt   <- array(hgtA[selm], dim = dims)
        ugrd  <- array(ugrdA[selm], dim = dims)
        vgrd  <- array(vgrdA[selm], dim = dims)
        sh    <- array(shA[selm], dim = dims)
        tmp   <- array(tmpA[selm], dim = dims)
        if (useCO2) {
          co2 <- array(co2A[selm], dim = dims)
        }
        rhdf5::h5write(nbdsf, mout, "nbdsf")
        rhdf5::h5write(nddsf, mout, "nddsf")
        rhdf5::h5write(vbdsf, mout, "vbdsf")
        rhdf5::h5write(vddsf, mout, "vddsf")
        rhdf5::h5write(prate, mout, "prate")
        rhdf5::h5write(dlwrf, mout, "dlwrf")
        rhdf5::h5write(pres, mout, "pres")
        rhdf5::h5write(hgt, mout, "hgt")
        rhdf5::h5write(ugrd, mout, "ugrd")
        rhdf5::h5write(vgrd, mout, "vgrd")
        rhdf5::h5write(sh, mout, "sh")
        rhdf5::h5write(tmp, mout, "tmp")
        if (useCO2) {
          rhdf5::h5write(co2, mout, "co2")
        }
      }
    }

    ## write DRIVER file
    sites <- 1
    metgrid <- c(1, 1, 1, 1, lon, lat)
    metvar <- c("nbdsf", "nddsf", "vbdsf", "vddsf", "prate", "dlwrf",
                "pres", "hgt", "ugrd", "vgrd", "sh", "tmp", "co2")
    nmet <- length(metvar)
    metfrq <- rep(dt, nmet)
    metflag <- rep(1, nmet)
    if (!useCO2) {
      metflag[metvar == "co2"] <- 4
      metfrq[metvar == "co2"] <- 380
    }
    write.table("header", met_header, row.names = FALSE, col.names = FALSE)
    write.table(sites, met_header, row.names = FALSE, col.names = FALSE, append = TRUE)
    write.table(met_folder, met_header, row.names = FALSE, col.names = FALSE, append = TRUE,
                quote = FALSE)
    write.table(matrix(metgrid, nrow = 1), met_header, row.names = FALSE, col.names = FALSE,
                append = TRUE, quote = FALSE)
    write.table(nmet, met_header, row.names = FALSE, col.names = FALSE, append = TRUE, quote = FALSE)
    write.table(matrix(metvar, nrow = 1), met_header, row.names = FALSE, col.names = FALSE, append = TRUE)
    write.table(matrix(metfrq, nrow = 1), met_header, row.names = FALSE, col.names = FALSE, append = TRUE,
                quote = FALSE)
    write.table(matrix(metflag, nrow = 1), met_header, row.names = FALSE, col.names = FALSE,
                append = TRUE, quote = FALSE)
  }  ### end loop over met files

  print("Done with met2model.ED2")
  return(invisible(results))
} # met2model.ED2
