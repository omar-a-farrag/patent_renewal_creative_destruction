********************************************************************************
/* Shortcut: Update Master Regression File with Firm Size Bins
   Logic: Injects the new variables from Script 04 into the existing 
          regression file without recalculating the clone network.
*/
********************************************************************************
clear all
cls
cd "/if/research-eme/omar/Harun/code"

use "$clean/master_regression_file.dta", clear

* Drop the variables if they already exist from a previous partial run
capture drop is_big_p90 is_big_p75 is_small_p10 is_small_p25 firm_size_bin firm_size_bin_quartile is_breakthrough

* Merge ONLY the new columns from the updated Active Stock panel
merge 1:1 patent_id using "$clean/master_competition_measures.dta", ///
    keepusing(is_big_p90 is_big_p75 is_small_p10 is_small_p25 firm_size_bin firm_size_bin_quartile is_breakthrough) ///
    keep(master match) nogen

save "$clean/master_regression_file.dta", replace

di ">>> Shortcut Complete. Master Regression File is updated and ready for Scripts 01, 01b, 01c, 06d, and 08."
