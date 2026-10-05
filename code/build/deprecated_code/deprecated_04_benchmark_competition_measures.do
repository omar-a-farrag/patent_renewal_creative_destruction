********************************************************************************
/* Script 04: Competition Measures & Benchmarking
   Logic: Calculates HHI, Weighted Flow, and Average/Median Quality.
   Windows: Window 1 [T, T+3], Window 2 [T+4, T+7], Window 3 [T+8, T+11]
*/
********************************************************************************
clear all
cls
cd "Z:/research-eme/omar/Harun/code"
do "00_initialize.do" "04_competition_measures"

use "$clean/master_with_location.dta", clear
drop if grant_year > 2019

********************************************************************************
* PART A: Build Sector-Year Reference Tables
********************************************************************************
* 1. Quality (Avg/Med) and Weighted Volume (Flow)
preserve
    gen vol_weight = 1 + total_5y_citations // 0-cite patents = 1
    gen one = 1
    
    collapse (sum) yr_vol = vol_weight (sum) yr_cits = total_5y_citations ///
             (count) yr_cnt = one (median) yr_med = total_5y_citations, ///
             by(cpc_class cpc_cluster grant_year)
    
    foreach level in class cluster {
        * Measure 2: Citation-Weighted Flow
        rangestat (sum) flowq_`level' = yr_vol, interval(grant_year 0 3) by(cpc_`level')
        
        * Measure 1: Average & Median Quality
        rangestat (sum) s_cits = yr_cits (sum) s_cnt = yr_cnt, interval(grant_year 0 3) by(cpc_`level')
        gen avgq_`level' = s_cits / s_cnt
        rangestat (mean) medq_`level' = yr_med, interval(grant_year 0 3) by(cpc_`level')
        drop s_cits s_cnt
    }
    keep cpc_class cpc_cluster grant_year flowq* avgq* medq*
    tempfile metrics_ref
    save `metrics_ref'
restore

* 2. Dynamic HHI (Vectorized calculation)
preserve
    bysort cpc_class cpc_cluster grant_year assignee_id: gen f_cnt = _N
    bysort cpc_class cpc_cluster grant_year: gen s_tot = _N
    gen share_sq = (f_cnt / s_tot)^2
    
    collapse (sum) ann_hhi_class = share_sq (mean) ann_hhi_cluster = share_sq, ///
             by(cpc_class cpc_cluster grant_year)
    
    foreach level in class cluster {
        rangestat (mean) hhi_`level' = ann_hhi_`level', interval(grant_year 0 3) by(cpc_`level')
    }
    keep cpc_class cpc_cluster grant_year hhi_class hhi_cluster
    tempfile hhi_ref
    save `hhi_ref'
restore

********************************************************************************
* PART B: Map Metrics to Renewal Windows
********************************************************************************
use "$clean/master_with_location.dta", clear

foreach w in 1 2 3 {
    local offset = (`w' - 1) * 4
    gen g_year_offset = grant_year + `offset'
    
    * Merge Quality/Volume
    preserve
        use `metrics_ref', clear
        rename grant_year g_year_offset
        rename (flowq_class avgq_class medq_class flowq_cluster avgq_cluster medq_cluster) ///
               (flowq`w'_class avgq`w'_class medq`w'_class flowq`w'_cluster avgq`w'_cluster medq`w'_cluster)
        tempfile metrics_w`w'
        save `metrics_w`w''
    restore
    merge m:1 cpc_class cpc_cluster g_year_offset using `metrics_w`w'', keep(match master) nogen

    * Merge HHI
    preserve
        use `hhi_ref', clear
        rename grant_year g_year_offset
        rename (hhi_class hhi_cluster) (hhi`w'_class hhi`w'_cluster)
        tempfile hhi_w`w'
        save `hhi_w`w''
    restore
    merge m:1 cpc_class cpc_cluster g_year_offset using `hhi_w`w'', keep(match master) nogen
    
    drop g_year_offset
}

********************************************************************************
* PART C: IHS Log Transformations
********************************************************************************
foreach v of varlist flowq* avgq* medq* hhi* {
    gen log_`v' = log(`v' + sqrt(`v'^2 + 1))
}

save "$for_regs/master_regression_file.dta", replace
log close