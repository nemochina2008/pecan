##-------------------------------------------------------------------------------------------------#
##' For each benchmark id, calculate metrics and update benchmarks_ensemble_scores
##'  
##' @name create_BRR
##' @title Create benchmark reference run and ensemble
##' @param ens_wf table made from joining ensemble and workflow tables 
##' @param con database connection
##' @export 
##' 
##' @author Betsy Cowdery 

create_BRR <- function(ens_wf, con, user_id = ""){
  
  cnd1 <- ens_wf$hostname == PEcAn.utils::fqdn() 
  cnd2 <- ens_wf$hostname == 'test-pecan.bu.edu' & PEcAn.utils::fqdn() == 'pecan2.bu.edu'
  cnd3 <- ens_wf$hostname == 'pecan2.bu.edu' & PEcAn.utils::fqdn() == 'test-pecan.bu.edu'
  db.query <- PEcAn.DB::db.query
  
 # if(cnd1|cnd2|cnd3){  # If the ensemble run was done on localhost, turn into a BRR
    
    settingsXML <- file.path(ens_wf$folder,"pecan.CHECKED.xml")
    
    # Automatically creates a new pecan.xml I think. Need to fix this. 
    clean <- PEcAn.settings::clean.settings(inputfile = settingsXML,write=FALSE)
    # Remove database & host information
    clean$database <- NULL 
    clean$host <- NULL
    clean$info <- NULL
    clean$outdir <- NULL
    clean$meta.analysis <- NULL
    clean$ensemble <- NULL
    str(clean)
    
    settings_xml <- toString(PEcAn.utils::listToXml(clean, "pecan"))
    
    ref_run <- db.query(paste0(" SELECT * from reference_runs where settings = '", settings_xml,"'"),con)
    
    if(length(ref_run) == 0){ # Make new reference run entry
      ref_run <- db.query(paste0("INSERT INTO reference_runs (model_id, settings, user_id)",
                                 "VALUES(",ens_wf$model_id,", '",settings_xml,"' , ",user_id,
                                 ") RETURNING *;"),con)
    }else if(dim(ref_run)[1] > 1){# There shouldn't be more than one reference run with the same settings
      PEcAn.logger::logger.error("There is more than one reference run in the database with these settings. Review for duplicates. ")
    }
    BRR <- ref_run %>% rename(.,reference_run_id = id)
    return(BRR)
  # }else{logger.error(sprintf("Cannot create a benchmark reference run for a run on hostname: %s", 
  #                            ens_wf$hostname))}
} #create_BRR
