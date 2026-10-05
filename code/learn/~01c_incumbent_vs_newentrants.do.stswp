********************************************************************************
/* Script 01c: The Horse Race (Incumbent vs. New Entrant)
   Logic: Runs pairwise specifications pitting the historical active stock 
          directly against the newly granted entrants in the same equation.
   Updated: Integrates micro patent-level dyad measures (Overlap & Clones).
*/
********************************************************************************
clear all
cls
cd "/if/research-eme/omar/Harun/code"

do "00_initialize.do" "01c_horserace_regressions"

local cluster_mode = 3

use "$clean/master_regression_file_repaired.dta", clear
gen log_internal_quality = log(total_5y_citations + sqrt(total_5y_citations^2 + 1))

* CRITICAL FIX: is_small changed to small_entity
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
        if `w' == 3 drop if grant_year > 2013
        if `w' == 2 drop if grant_year > 2017
        if `w' == 1 drop if grant_year > 2021
        
        foreach lvl in "class" "cluster" {
            if "`lvl'" == "class" local cl_var "cpc_class"
            if "`lvl'" == "cluster" local cl_var "cpc_cluster"
            
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
            
            * Loop through BOTH macro and micro metrics
            foreach m in "avgq" "medq" "flowq" "hhi" "overlap" "clone" {
                
                * Bypass cluster iteration for patent-level dyad measures
                if ("`m'" == "overlap" | "`m'" == "clone") & "`lvl'" == "cluster" continue
                
                * --------------------------------------------------------------
                * DYNAMIC VARIABLE ROUTING & FORMATTING
                * --------------------------------------------------------------
                local dec_fmt "3" // Default to 3 decimals for macro measures
                
//                 if "`m'" == "clone" {
//                     * Include BOTH the incumbent and new entrant main effects + interactions
//                     local reg_vars "c.log_clone_count`w'##c.log_clone_avgq`w' c.log_new_clone_count`w'##c.log_new_clone_avgq`w'"
//                     local keep_vars "log_clone_count`w' log_clone_avgq`w' c.log_clone_count`w'#c.log_clone_avgq`w' log_new_clone_count`w' log_new_clone_avgq`w' c.log_new_clone_count`w'#c.log_new_clone_avgq`w'"
//                     *local out_name "reg_horserace_clone`w'`suffix'"
// 		    local out_name "reg_horserace_clone`w'`suffix'`size_suffix'"
//                     local dec_fmt "5" // Prevent the Zero Illusion
//                 }
		if "`m'" == "clone" {
                    * Generate interactions dynamically to avoid esttab factor variable bugs
                    capture gen log_clone_interaction`w' = log_clone_count`w' * log_clone_avgq`w'
                    capture gen log_new_clone_interaction`w' = log_new_clone_count`w' * log_new_clone_avgq`w'
                    local reg_vars "log_clone_count`w' log_clone_avgq`w' log_clone_interaction`w' log_new_clone_count`w' log_new_clone_avgq`w' log_new_clone_interaction`w'"
                    local keep_vars "`reg_vars'"
                    local out_name "reg_horserace_clone`w'`suffix'`size_suffix'"
                    local dec_fmt "5" 
                }
                else if "`m'" == "overlap" {
                    * Include BOTH incumbent and new entrant overlap volumes
                    local reg_vars "log_overlap_count`w' log_new_overlap_count`w'"
                    local keep_vars "`reg_vars'"
                    *local out_name "reg_horserace_overlap`w'`suffix'"
		    local out_name "reg_horserace_overlap`w'`suffix'`size_suffix'"
                    local dec_fmt "5" // Prevent the Zero Illusion
                }
                else {
                    * Standard macro measures
                    local reg_vars "log_`m'`w'_`lvl' log_new_`m'`w'_`lvl'"
                    local keep_vars "`reg_vars'"
                    *local out_name "reg_horserace_`m'`w'_`lvl'`suffix'"
		    local out_name "reg_horserace_`m'`w'_`lvl'`suffix'`size_suffix'"
                }
                
                di "========================================================"
                di "HORSE RACE: Window `w' | Measure: `m' | Level: `lvl'"
                di "Clustering by: `cl_se_var'"
                di "========================================================"
                
                eststo s1: reg `dv' `reg_vars' `controls'
                eststo s2: reg `dv' `reg_vars' `controls', vce(robust)
                eststo s3: areg `dv' `reg_vars' `controls', absorb(`cl_var') vce(robust)
                eststo s4: areg `dv' `reg_vars' `controls', absorb(grant_year) vce(robust)
                eststo s5: reghdfe `dv' `reg_vars' `controls', absorb(`cl_var' grant_year) vce(robust)
                eststo s6: areg `dv' `reg_vars' `controls', absorb(`cl_var') vce(cluster grant_year)
                eststo s7: reghdfe `dv' `reg_vars' `controls', absorb(grant_year) vce(cluster `cl_se_var')
                eststo s8: reghdfe `dv' `reg_vars' `controls', absorb(`cl_var' grant_year) vce(cluster `cl_se_var')

                * Export to a dedicated horserace CSV file
                esttab s* using "$output/baseline_regressions/csvs/`out_name'.csv", replace ///
                    cells(b(star fmt(`dec_fmt')) se(par fmt(`dec_fmt'))) ///
                    star(* 0.10 ** 0.05 *** 0.01) ///
                    stats(N r2, labels("Obs" "R2")) keep(`keep_vars' `controls' _cons) noobs nomtitles nonumbers
                    
                estimates clear
            }
        }
    restore
}

di ">>> Script 01c Complete. Horse Race specifications exported."
