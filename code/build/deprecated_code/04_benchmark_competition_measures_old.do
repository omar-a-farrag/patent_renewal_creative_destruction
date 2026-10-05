********************************************************************************
/* Script 04: Competition Measures & Benchmarking
   Logic: Calculates HHI, Weighted Flow, and Average/Median Quality.
   Windows: Window 1 [T, T+3], Window 2 [T+4, T+7], Window 3 [T+8, T+11]
*/
********************************************************************************
clear all
cls
cd "Z:/research-eme/omar/Harun/code"

*install package so we can run rangejoin command
set httpproxy on
set httpproxyhost wwwproxy.frb.gov
set httpproxyport 8080

capture ssc install rangejoin
capture ssc install rangestat

do "00_initialize.do" "04_competition_measures"

use "$clean/master_with_location.dta", clear
drop if grant_year > 2019

********************************************************************************
* PART A: Build Sector-Year Reference Tables (REWRITTEN)
********************************************************************************
* PREP: Save a streamlined version of the master data to speed up rangejoin
keep patent_id cpc_class cpc_cluster grant_year assignee_id total_5y_citations
gen vol_weight = 1 + total_5y_citations 
gen one = 1
tempfile raw_patents
save `raw_patents'

* Create a skeleton of all unique Class-Years and Cluster-Years to anchor the windows
keep cpc_class cpc_cluster grant_year
duplicates drop
tempfile anchor_years
save `anchor_years'

* ------------------------------------------------------------------------------
* 1. Class-Level Pooled Window Calculations
* ------------------------------------------------------------------------------
use `anchor_years', clear
rangejoin grant_year 0 3 using `raw_patents', by(cpc_class)

* a) The Class HHI
bysort cpc_class grant_year assignee_id: egen window_assignee_count = total(one)
bysort cpc_class grant_year: egen window_total_count = total(one)

preserve
    duplicates drop cpc_class grant_year assignee_id, force
    gen share_sq = (window_assignee_count / window_total_count)^2
    collapse (sum) hhi_class = share_sq, by(cpc_class grant_year)
    tempfile class_hhi
    save `class_hhi'
restore

* b) The Quality & Flow Metrics
collapse (sum) flowq_class = vol_weight ///
         (sum) s_cits = total_5y_citations (sum) s_cnt = one ///
         (median) medq_class = total_5y_citations, ///
         by(cpc_class grant_year)

gen avgq_class = s_cits / s_cnt
drop s_cits s_cnt

* Merge Class HHI back in
merge 1:1 cpc_class grant_year using `class_hhi', nogen
tempfile class_metrics
save `class_metrics'

* ------------------------------------------------------------------------------
* 2. Cluster-Level Pooled Window Calculations (FIXED)
* ------------------------------------------------------------------------------
use `anchor_years', clear

* ---> THE FIX: Reduce anchors to the true cluster level before rangejoin <---
keep cpc_cluster grant_year
duplicates drop

rangejoin grant_year 0 3 using `raw_patents', by(cpc_cluster)

* a) The Cluster HHI
bysort cpc_cluster grant_year assignee_id: egen window_assignee_count = total(one)
bysort cpc_cluster grant_year: egen window_total_count = total(one)

preserve
    duplicates drop cpc_cluster grant_year assignee_id, force
    gen share_sq = (window_assignee_count / window_total_count)^2
    collapse (sum) hhi_cluster = share_sq, by(cpc_cluster grant_year)
    tempfile cluster_hhi
    save `cluster_hhi'
restore

* b) The Quality & Flow Metrics
collapse (sum) flowq_cluster = vol_weight ///
         (sum) s_cits = total_5y_citations (sum) s_cnt = one ///
         (median) medq_cluster = total_5y_citations, ///
         by(cpc_cluster grant_year)

gen avgq_cluster = s_cits / s_cnt
drop s_cits s_cnt

* Merge Cluster HHI back in
merge 1:1 cpc_cluster grant_year using `cluster_hhi', nogen
tempfile cluster_metrics
save `cluster_metrics'

* ------------------------------------------------------------------------------
* 3. Finalize Reference Table
* ------------------------------------------------------------------------------
* Bring both Class and Cluster metrics back onto the master anchor grid
use `anchor_years', clear
merge m:1 cpc_class grant_year using `class_metrics', keep(match master) nogen
merge m:1 cpc_cluster grant_year using `cluster_metrics', keep(match master) nogen

* Save the perfectly pooled reference table (Now contains Flow, Avg, Med, AND HHI)
tempfile metrics_ref
save `metrics_ref'

********************************************************************************
* PART B: Map Metrics to Renewal Windows
********************************************************************************
use "$clean/master_with_location.dta", clear

foreach w in 1 2 3 {
    local offset = (`w' - 1) * 4
    gen g_year_offset = grant_year + `offset'
    
    * Merge all metrics (Quality, Volume, and HHI) in one go
    preserve
        use `metrics_ref', clear
        rename grant_year g_year_offset
        rename (flowq_class avgq_class medq_class hhi_class flowq_cluster avgq_cluster medq_cluster hhi_cluster) ///
               (flowq`w'_class avgq`w'_class medq`w'_class hhi`w'_class flowq`w'_cluster avgq`w'_cluster medq`w'_cluster hhi`w'_cluster)
        tempfile metrics_w`w'
        save `metrics_w`w''
    restore
    
    merge m:1 cpc_class cpc_cluster g_year_offset using `metrics_w`w'', keep(match master) nogen
    drop g_year_offset
}

********************************************************************************
* PART C: IHS Log Transformations
********************************************************************************
foreach v of varlist flowq* avgq* medq* hhi* {
    * Protect against missing values before logging
    replace `v' = 0 if missing(`v')
    gen log_`v' = log(`v' + sqrt(`v'^2 + 1))
}

save "$for_regs/master_regression_file.dta", replace
di ">>> Step 04 Complete. All benchmarking measures mapped."
log close
