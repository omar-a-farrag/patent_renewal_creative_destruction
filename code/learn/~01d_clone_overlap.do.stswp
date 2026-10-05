********************************************************************************
/* Script 06d: Clone and Overlap Regressions
   Logic: Runs 8 specifications for the patent-level dyad measures.
   Variables: log_overlap_count, log_clone_count, log_clone_avgq, and interaction.
*/
********************************************************************************
clear all
cls
cd "/if/research-eme/omar/Harun/code"

do "00_initialize.do" "06d_clone_overlap_regressions"

* ==============================================================================
* CLUSTERING CONFIGURATION (3 = Assignee Level)
local cluster_mode = 3
* ==============================================================================

use "$clean/master_regression_file_repaired.dta", clear

* Calculate Corrected IHS for Internal Quality
gen log_internal_quality = log(total_5y_citations + sqrt(total_5y_citations^2 + 1))
*local controls "log_internal_quality small_entity is_big_p90"

* --- FIRM SIZE TOGGLE: "p90" (Baseline) or "p75" (Robustness) ---
local size_mode = "p90"

if "`size_mode'" == "p90" {
    local size_var "is_big_p90"
    local size_suffix ""
}
else if "`size_mode'" == "p75" {
    local size_var "is_big_p75"
    local size_suffix "_p75"
}
local controls "log_internal_quality small_entity `size_var'"

foreach w in 1 2 3 {
    local dv ren`w'
    preserve
        * SUBSETTING
        if `w' == 3 drop if grant_year > 2013
        if `w' == 2 drop if grant_year > 2017
        if `w' == 1 drop if grant_year > 2021
        
        * Generate the Clone Interaction Term dynamically
        gen log_clone_interaction`w' = log_clone_count`w' * log_clone_avgq`w'
        
        * Fixed Effects & Clustering Setup (Absorbing by cpc_class for tech fixed effects)
        local cl_var "cpc_class"
        
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
        
        * ---------------------------------------------------------
        * 1. OVERLAP REGRESSIONS (Using overlap_count)
        * ---------------------------------------------------------
        *local out_name "reg_overlap`w'`suffix'"
        *local reg_var "log_overlap_count`w'"
	local out_name "reg_overlap`w'`suffix'`size_suffix'"
        local out_name "reg_clone`w'`suffix'`size_suffix'"
        
        di "========================================================"
        di "Running OVERLAP | Window `w'"
        di "========================================================"
        
        eststo s1: reg `dv' `reg_var' `controls'
        eststo s2: reg `dv' `reg_var' `controls', vce(robust)
        eststo s3: areg `dv' `reg_var' `controls', absorb(`cl_var') vce(robust)
        eststo s4: areg `dv' `reg_var' `controls', absorb(grant_year) vce(robust)
        eststo s5: reghdfe `dv' `reg_var' `controls', absorb(`cl_var' grant_year) vce(robust)
        eststo s6: areg `dv' `reg_var' `controls', absorb(`cl_var') vce(cluster grant_year)
        eststo s7: reghdfe `dv' `reg_var' `controls', absorb(grant_year) vce(cluster `cl_se_var')
        eststo s8: reghdfe `dv' `reg_var' `controls', absorb(`cl_var' grant_year) vce(cluster `cl_se_var')

        esttab s* using "$output/baseline_regressions/csvs/`out_name'.csv", replace ///
            cells(b(star fmt(5)) se(par fmt(5))) star(* 0.10 ** 0.05 *** 0.01) ///
            stats(N r2, labels("Obs" "R2")) keep(`reg_var' `controls' _cons) noobs nomtitles nonumbers
            
        estimates clear

        * ---------------------------------------------------------
        * 2. CLONE REGRESSIONS (Main Effects + Interaction)
        * ---------------------------------------------------------
        local out_name "reg_clone`w'`suffix'"
        local reg_vars "log_clone_count`w' log_clone_avgq`w' log_clone_interaction`w'"
        
        di "========================================================"
        di "Running CLONES | Window `w'"
        di "========================================================"
        
        eststo s1: reg `dv' `reg_vars' `controls'
        eststo s2: reg `dv' `reg_vars' `controls', vce(robust)
        eststo s3: areg `dv' `reg_vars' `controls', absorb(`cl_var') vce(robust)
        eststo s4: areg `dv' `reg_vars' `controls', absorb(grant_year) vce(robust)
        eststo s5: reghdfe `dv' `reg_vars' `controls', absorb(`cl_var' grant_year) vce(robust)
        eststo s6: areg `dv' `reg_vars' `controls', absorb(`cl_var') vce(cluster grant_year)
        eststo s7: reghdfe `dv' `reg_vars' `controls', absorb(grant_year) vce(cluster `cl_se_var')
        eststo s8: reghdfe `dv' `reg_vars' `controls', absorb(`cl_var' grant_year) vce(cluster `cl_se_var')

        esttab s* using "$output/baseline_regressions/csvs/`out_name'.csv", replace ///
            cells(b(star fmt(5)) se(par fmt(5))) star(* 0.10 ** 0.05 *** 0.01) ///
            stats(N r2, labels("Obs" "R2")) keep(`reg_vars' `controls' _cons) noobs nomtitles nonumbers
            
        estimates clear
        
    restore
}

di ">>> Script 06d Complete. Clone and Overlap CSVs generated."
