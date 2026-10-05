
********************************************************************************
/* Script 01: Expanded Robustness Panel
   Logic: Runs 7 specifications per measure across 3 renewal windows.
   Updated: Includes dynamic standard error clustering and CSV suffix routing.
*/
********************************************************************************
clear all
cls
* 0. Adjust current directory as needed in order to run intilization script
*cd "Z:/research-eme/omar/Harun/code"
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
if _rc {
    ssc install estout
}

capture which ftools
if _rc {
    ssc install ftools
}

capture which require
if _rc {
    ssc install require
}

capture which reghdfe
if _rc {
    ssc install reghdfe
}

use "$for_regs/master_regression_file.dta", clear

* Calculate Corrected IHS for Internal Quality
gen log_internal_quality = log(total_5y_citations + sqrt(total_5y_citations^2 + 1))
local controls "log_internal_quality is_small"

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
            
            foreach m in "avgq" "medq" "flowq" "hhi" "overlap" {
                
                * Ensure we only run overlap at the class level
                if "`m'" == "overlap" & "`lvl'" == "cluster" continue
                
                local var "log_`m'`w'_`lvl'"
                
		if "`m'" == "overlap" {
                    local var "log_overlap`w'"
                }
		
                di "========================================================"
                di "Running Window `w' | `var' (`lvl' level)..."
                di "Clustering by: `cl_se_var'"
                di "========================================================"
                
                * 1. OLS + controls
                eststo s1: reg `dv' `var' `controls'
                
                * 2. OLS + controls, robust SEs
                eststo s2: reg `dv' `var' `controls', vce(robust)
                
                * 3. Level FE (Absorb), robust SEs
                eststo s3: areg `dv' `var' `controls', absorb(`cl_var') vce(robust)
                
                * 4. Year FE (Absorb), robust SEs
                eststo s4: areg `dv' `var' `controls', absorb(grant_year) vce(robust)
                
                * 5. Dual FE (Level & Year), robust SEs
                eststo s5: reghdfe `dv' `var' `controls', absorb(`cl_var' grant_year) vce(robust)
                
                * 6. Level FE (Absorb), cluster SEs by Year
                eststo s6: areg `dv' `var' `controls', absorb(`cl_var') vce(cluster grant_year)
                
                * 7. Year FE (Absorb), cluster SEs by Selected Mode
                eststo s7: reghdfe `dv' `var' `controls', absorb(grant_year) vce(cluster `cl_se_var')

                * 8. Dual FE (Level & Year), Clustered SEs by Selected Mode
                eststo s8: reghdfe `dv' `var' `controls', absorb(`cl_var' grant_year) vce(cluster `cl_se_var')

                * Export for Python Formatter
                esttab s* using "$output/baseline_regressions/csvs/reg_`m'`w'_`lvl'`suffix'.csv", replace ///
                    cells(b(star fmt(3)) se(par fmt(3))) ///
                    star(* 0.10 ** 0.05 *** 0.01) ///
                    stats(N r2, labels("Obs" "R2")) keep(`var' `controls' _cons) noobs nomtitles nonumbers
                    
                estimates clear // <--- THE FIX
            }
        }
    restore
}

di ">>> Script 01 Complete. All specifications exported."
