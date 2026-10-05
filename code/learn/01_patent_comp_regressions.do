********************************************************************************
/* Script 01: Expanded Robustness Panel (Quallity, Volume, HHI, Overlap Competition measures)
   Logic: Runs 7 specifications per measure across 3 renewal windows.
   Updated: Includes dynamic routing for the continuous interaction term.
*/
********************************************************************************
clear all
cls
* 0. Adjust current directory as needed in order to run initialization script
cd "/if/research-eme/omar/Harun/code"

do "00_initialize.do" "01_baseline_regressions.do"

* ==============================================================================
* CLUSTERING CONFIGURATION
* Set the local macro 'cluster_mode' to choose your standard error clustering:
* 1 = Tech Level (Baseline: cpc_class or cpc_cluster)
* 2 = Two-Way (Tech Level AND Grant Year)
* 3 = Assignee Level (assignee_id)
local cluster_mode = 3
* ==============================================================================

capture which estout
if _rc ssc install estout
capture which ftools
if _rc ssc install ftools
capture which require
if _rc ssc install require
capture which reghdfe
if _rc ssc install reghdfe

use "$clean/master_regression_file_repaired.dta", clear

* Calculate Corrected IHS for Internal Quality
gen log_internal_quality = log(total_5y_citations + sqrt(total_5y_citations^2 + 1))
*local controls "log_internal_quality small_entity is_big_p90"
* ------------------------------------------------------------------------------
* CRITICAL FIX: Recalculate Dyads using IHS to prevent log(0) listwise deletion
* ------------------------------------------------------------------------------
foreach w in 1 2 3 {
    * 1. IHS transformation for all count variables
    replace log_clone_count`w' = log(clone_count`w' + sqrt(clone_count`w'^2 + 1))
    replace log_overlap_count`w' = log(overlap_count`w' + sqrt(overlap_count`w'^2 + 1))
    
    capture replace log_new_clone_count`w' = log(new_clone_count`w' + sqrt(new_clone_count`w'^2 + 1))
    capture replace log_new_overlap_count`w' = log(new_overlap_count`w' + sqrt(new_overlap_count`w'^2 + 1))
    
    * 2. Fix Quality Missing Values: If a patent has 0 clones, its quality is missing. 
    * We must set it to 0 so the interaction term cleanly evaluates to 0 instead of missing.
    replace log_clone_avgq`w' = 0 if missing(log_clone_avgq`w')
    capture replace log_new_clone_avgq`w' = 0 if missing(log_new_clone_avgq`w')
}
* ------------------------------------------------------------------------------

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
        * SUBSETTING: Only analyze patents that have actually reached the decision point
        if `w' == 3 {
            drop if grant_year > 2013
        }
        if `w' == 2 {
            drop if grant_year > 2017
        }
        if `w' == 1 {
            drop if grant_year > 2021
        }
        
        foreach lvl in "class" "cluster" {
            if "`lvl'" == "class" local cl_var "cpc_class"
            if "`lvl'" == "cluster" local cl_var "cpc_cluster"
            
            * ------------------------------------------------------------------
            * DYNAMIC CLUSTERING LOGIC
            * ------------------------------------------------------------------
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
            
 * Added "clone" to the loop
            foreach m in "avgq" "medq" "flowq" "hhi" "overlap" "clone" {
                
                * Ensure we only run overlap and clone once (they don't have class/cluster splits)
                if ("`m'" == "overlap" | "`m'" == "clone") & "`lvl'" == "cluster" continue
                
                * --------------------------------------------------------------
                * DYNAMIC VARIABLE ROUTING & FORMATTING
                * --------------------------------------------------------------
                local dec_fmt "3" // Default to 3 decimals for macro measures
                
/*
                if "`m'" == "clone" {
                    * The ## operator tells Stata to run the main effects AND the interaction
                    local reg_var "c.log_clone_count`w'##c.log_clone_avgq`w'"
                    * esttab needs the explicit internal matrix names to keep them
                    local keep_vars "log_clone_count`w' log_clone_avgq`w' c.log_clone_count`w'#c.log_clone_avgq`w'"
                    *local out_name "reg_clone`w'`suffix'"
		    local out_name "reg_clone`w'`suffix'`size_suffix'"
                    local dec_fmt "5" // Force 5 decimals to avoid the Zero Illusion!
                }
*/
		if "`m'" == "clone" {
                    * Generate interaction dynamically to avoid esttab factor variable bugs
                    capture gen log_clone_interaction`w' = log_clone_count`w' * log_clone_avgq`w'
                    local reg_var "log_clone_count`w' log_clone_avgq`w' log_clone_interaction`w'"
                    local keep_vars "`reg_var'"
                    local out_name "reg_clone`w'`suffix'`size_suffix'"
                    local dec_fmt "5" 
                }
                else if "`m'" == "overlap" {
                    local reg_var "log_overlap_count`w'" // CRITICAL FIX: Updated variable name
                    local keep_vars "`reg_var'"
                    *local out_name "reg_overlap`w'`suffix'"
		    local out_name "reg_overlap`w'`suffix'`size_suffix'"
                    local dec_fmt "5" // Force 5 decimals to avoid the Zero Illusion!
                }
                else {
                    local reg_var "log_`m'`w'_`lvl'"
                    local keep_vars "`reg_var'"
                    *local out_name "reg_`m'`w'_`lvl'`suffix'"
		    local out_name "reg_`m'`w'_`lvl'`suffix'`size_suffix'"
                }
                
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

                * Export for Python Formatter (Using Dynamic Formatting)
                esttab s* using "$output/baseline_regressions/csvs/`out_name'.csv", replace ///
                    cells(b(star fmt(`dec_fmt')) se(par fmt(`dec_fmt'))) ///
                    star(* 0.10 ** 0.05 *** 0.01) ///
                    stats(N r2, labels("Obs" "R2")) keep(`keep_vars' `controls' _cons) noobs nomtitles nonumbers
                    
                estimates clear
            }
        }
    restore
}

di ">>> Script Complete. All specifications exported."
