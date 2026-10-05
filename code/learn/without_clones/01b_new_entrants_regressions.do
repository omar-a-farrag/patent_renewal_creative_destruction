********************************************************************************
/* Script 06b: New Entrant Regressions
   Logic: Runs 7 specifications for the New Entrant (Flow) competition measures.
   Variables: new_avgq, new_medq, new_flowq, new_hhi
*/
********************************************************************************
clear all
cls
* 0. Adjust current directory as needed
cd "/if/research-eme/omar/Harun/code"

do "00_initialize.do" "06b_new_entrant_regressions"

* ==============================================================================
* CLUSTERING CONFIGURATION
* 1 = Tech Level | 2 = Two-Way | 3 = Assignee Level
local cluster_mode = 3
* ==============================================================================
use "$clean/master_regression_file.dta", clear

* Calculate Corrected IHS for Internal Quality
gen log_internal_quality = log(total_5y_citations + sqrt(total_5y_citations^2 + 1))
local controls "log_internal_quality is_small"

foreach w in 1 2 3 {
    local dv ren`w'
    preserve
        * SUBSETTING: Only analyze patents that have actually reached the decision point
        if `w' == 3 drop if grant_year > 2013
        if `w' == 2 drop if grant_year > 2017
        if `w' == 1 drop if grant_year > 2021
        
        foreach lvl in "class" "cluster" {
            if "`lvl'" == "class" local cl_var "cpc_class"
            if "`lvl'" == "cluster" local cl_var "cpc_cluster"
            
            * Clustering Logic
            if `cluster_mode' == 1 {
                local cl_se_var "`cl_var'"
                local suffix ""
            }
            else if `cluster_mode' == 2 {
                local cl_se_var "`cl_var' grant_year"
                local suffix "_twoway"
            }
            else if `cluster_mode' == 3 {
                local cl_se_var "assignee_id"
                local suffix "_assignee"
            }
            
            * Loop through ONLY the New Entrant macro measures
            foreach m in "new_avgq" "new_medq" "new_flowq" "new_hhi" {
                
                local reg_var "log_`m'`w'_`lvl'"
                local keep_vars "`reg_var'"
                local out_name "reg_`m'`w'_`lvl'`suffix'"
                
                di "========================================================"
                di "Running Window `w' | Measure: `m' | Level: `lvl'..."
                di "Clustering by: `cl_se_var'"
                di "========================================================"
                
                * 1. OLS + controls
                eststo s1: reg `dv' `reg_var' `controls'
                * 2. OLS + controls, robust SEs
                eststo s2: reg `dv' `reg_var' `controls', vce(robust)
                * 3. Level FE (Absorb), robust SEs
                eststo s3: areg `dv' `reg_var' `controls', absorb(`cl_var') vce(robust)
                * 4. Year FE (Absorb), robust SEs
                eststo s4: areg `dv' `reg_var' `controls', absorb(grant_year) vce(robust)
                * 5. Dual FE (Level & Year), robust SEs
                eststo s5: reghdfe `dv' `reg_var' `controls', absorb(`cl_var' grant_year) vce(robust)
                * 6. Level FE (Absorb), cluster SEs by Year
                eststo s6: areg `dv' `reg_var' `controls', absorb(`cl_var') vce(cluster grant_year)
                * 7. Year FE (Absorb), cluster SEs by Selected Mode
                eststo s7: reghdfe `dv' `reg_var' `controls', absorb(grant_year) vce(cluster `cl_se_var')
                * 8. Dual FE (Level & Year), Clustered SEs by Selected Mode
                eststo s8: reghdfe `dv' `reg_var' `controls', absorb(`cl_var' grant_year) vce(cluster `cl_se_var')

                * Export for Python Formatter
                esttab s* using "$output/baseline_regressions/csvs/`out_name'.csv", replace ///
                    cells(b(star fmt(3)) se(par fmt(3))) ///
                    star(* 0.10 ** 0.05 *** 0.01) ///
                    stats(N r2, labels("Obs" "R2")) keep(`keep_vars' `controls' _cons) noobs nomtitles nonumbers
                    
                estimates clear
            }
        }
    restore
}

di ">>> Script 06b Complete. New Entrant specifications exported."
