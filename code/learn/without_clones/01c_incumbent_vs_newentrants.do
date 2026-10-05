********************************************************************************
/* Script 06c: The Horse Race (Incumbent vs. New Entrant)
   Logic: Runs pairwise specifications pitting the historical active stock 
          directly against the newly granted entrants in the same equation.
*/
********************************************************************************
clear all
cls
cd "/if/research-eme/omar/Harun/code"

do "00_initialize.do" "06c_horserace_regressions"

local cluster_mode = 3

use "$clean/master_regression_file.dta", clear
gen log_internal_quality = log(total_5y_citations + sqrt(total_5y_citations^2 + 1))
local controls "log_internal_quality is_small"

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
            
            * Loop through the core metrics to pit them head-to-head
            foreach m in "avgq" "medq" "flowq" "hhi" {
                
                * Include BOTH the incumbent and new entrant variables
                local reg_vars "log_`m'`w'_`lvl' log_new_`m'`w'_`lvl'"
                local out_name "reg_horserace_`m'`w'_`lvl'`suffix'"
                
                di "========================================================"
                di "HORSE RACE: Window `w' | Measure: `m' | Level: `lvl'"
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
                    cells(b(star fmt(3)) se(par fmt(3))) ///
                    star(* 0.10 ** 0.05 *** 0.01) ///
                    stats(N r2, labels("Obs" "R2")) keep(`reg_vars' `controls' _cons) noobs nomtitles nonumbers
                    
                estimates clear
            }
        }
    restore
}

di ">>> Script 06c Complete. Horse Race specifications exported."
