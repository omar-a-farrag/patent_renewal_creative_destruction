********************************************************************************
/* 60-Second Data Rescue Patch
   Logic: Isolates the perfectly calculated clone/overlap variables and 
          re-merges the pristine master data to fix the missing grant_years.
*/
********************************************************************************
clear all
cls
cd "/if/research-eme/omar/Harun/code"

di ">>> Rescuing Master Regression File..."
use "$clean/master_regression_file.dta", clear

* 1. Keep ONLY the ID and the perfect variables Script 05 calculated
keep patent_id clone_count* clone_avgq* overlap_count* log_clone* log_overlap*

* 2. Re-merge the pristine master datasets (this restores all valid grant_years)
merge 1:1 patent_id using "$clean/master_competition_measures.dta", keep(using match) nogen
merge 1:1 patent_id using "$clean/master_new_entrant_measures.dta", keep(using match) nogen

save "$clean/master_regression_file.dta", replace
di ">>> RESCUE COMPLETE. Ready for 06d regressions!"
