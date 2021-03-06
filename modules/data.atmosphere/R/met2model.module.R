##' @export
.met2model.module <- function(ready.id, model, con, host, dir, met, str_ns, site, start_date, end_date, 
                              browndog, new.site, overwrite = FALSE, exact.dates,spin) {
  
  # Determine output format name and mimetype
  model_info <- PEcAn.DB::db.query(paste0("SELECT f.name, f.id, mt.type_string from modeltypes as m", " join modeltypes_formats as mf on m.id = mf.modeltype_id", 
                                " join formats as f on mf.format_id = f.id", " join mimetypes as mt on f.mimetype_id = mt.id", 
                                " where m.name = '", model, "' AND mf.tag='met'"), con)
  
  if (model_info[1] == "CF Meteorology") {
    model.id <- ready.id
    outfolder <- file.path(dir, paste0(met, "_site_", str_ns))
  } else {
    PEcAn.logger::logger.info("Begin Model Specific Conversion")
    
    formatname <- model_info[1]
    mimetype <- model_info[3]
    
    print("Convert to model format")
    
    input.id <- ready.id$input.id[1]
    if(host$name == "localhost"){
      outfolder <- file.path(dir, paste0(met, "_", model, "_site_", str_ns))
    } else {
      if(is.null(host$folder)){
        PEcAn.logger::logger.severe("host$folder required when running met2model.module for remote servers")
      } else {
        outfolder <- file.path(host$folder, paste0(met, "_", model, "_site_", str_ns))
      }
    }
    
    pkg <- paste0("PEcAn.", model)
    fcn <- paste0("met2model.", model)
    lst <- site.lst(site, con)
    
    model.id <- PEcAn.utils::convert.input(input.id = input.id, 
                              outfolder = outfolder,
                              formatname = formatname, mimetype = mimetype, 
                              site.id = site$id, 
                              start_date = start_date, end_date = end_date, 
                              pkg = pkg, fcn = fcn, con = con, host = host, browndog = browndog,
                              write = TRUE,
                              lst = lst, 
                              lat = new.site$lat, lon = new.site$lon, 
                              overwrite = overwrite,
                              exact.dates = exact.dates,
                              spin_nyear = spin$nyear,
                              spin_nsample = spin$nsample,
                              spin_resample = spin$resample)
  }
  
  PEcAn.logger::logger.info(paste("Finished Model Specific Conversion", model.id[1]))
  return(list(outfolder = outfolder, model.id = model.id))
} # .met2model.module
