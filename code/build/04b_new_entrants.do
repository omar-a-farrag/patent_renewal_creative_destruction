********************************************************************************
/* Script 04b: New Entrant Competition Measures (Flow)
   Logic: Isolates strictly NEW rival patents granted within the 4-year rolling windows.
   Architecture: Uses rangejoin to match focal grant year to recent entrant grant years.
*/
********************************************************************************
clear all
cls
cd "/if/research-eme/omar/Harun/code"

* Load rangejoin if not already installed
capture ssc install rangejoin
capture ssc install rangestat

do "00_initialize.do" "04b_new_entrant_measures"

* ----------------------------------------------------------------------
* 1. Prep the Raw Entrant Pool
* ----------------------------------------------------------------------
di ">>> 1. Prepping the New Entrant Pool..."
use patent_id cpc_class cpc_cluster grant_year assignee_id total_5y_citations using "$clean/master_with_location.dta", clear
drop if grant_year > 2019

* Calculate Harun's weighted flow
gen rival_weight = 1 + total_5y_citations 
tempfile raw_patents
save `raw_patents'

* Create a skeleton of all unique years to anchor the 4-year forward windows
keep cpc_class cpc_cluster grant_year
duplicates drop
tempfile anchor_years
save `anchor_years'

* ----------------------------------------------------------------------
* 2A. Calculate CLASS-Level New Entrants [T, T+3]
* ----------------------------------------------------------------------
di ">>> 2A. Running Rangejoin for CLASS-Level Entrants..."
use `anchor_years', clear
rangejoin grant_year 0 3 using `raw_patents', by(cpc_class)

* The Firm-Level HHI (Citation Weighted)
bysort cpc_class grant_year assignee_id: egen firm_weight = sum(rival_weight)
bysort cpc_class grant_year: egen window_total_weight = sum(rival_weight)

preserve
    duplicates drop cpc_class grant_year assignee_id, force
    gen hhi_component = ((firm_weight / window_total_weight) * 100)^2
    collapse (sum) new_hhi_class = hhi_component, by(cpc_class grant_year)
    tempfile class_hhi
    save `class_hhi'
restore

* Quality & Flow
collapse (sum) new_flowq_class = rival_weight ///
         (mean) new_avgq_class = total_5y_citations ///
         (median) new_medq_class = total_5y_citations, ///
         by(cpc_class grant_year)

merge 1:1 cpc_class grant_year using `class_hhi', nogen
tempfile class_metrics
save `class_metrics'

* ----------------------------------------------------------------------
* 2B. Calculate CLUSTER-Level New Entrants [T, T+3]
* ----------------------------------------------------------------------
di ">>> 2B. Running Rangejoin for CLUSTER-Level Entrants..."
use `anchor_years', clear
keep cpc_cluster grant_year
duplicates drop

rangejoin grant_year 0 3 using `raw_patents', by(cpc_cluster)

* The Firm-Level HHI (Citation Weighted)
bysort cpc_cluster grant_year assignee_id: egen firm_weight = sum(rival_weight)
bysort cpc_cluster grant_year: egen window_total_weight = sum(rival_weight)

preserve
    duplicates drop cpc_cluster grant_year assignee_id, force
    gen hhi_component = ((firm_weight / window_total_weight) * 100)^2
    collapse (sum) new_hhi_cluster = hhi_component, by(cpc_cluster grant_year)
    tempfile cluster_hhi
    save `cluster_hhi'
restore

* Quality & Flow
collapse (sum) new_flowq_cluster = rival_weight ///
         (mean) new_avgq_cluster = total_5y_citations ///
         (median) new_medq_cluster = total_5y_citations, ///
         by(cpc_cluster grant_year)

merge 1:1 cpc_cluster grant_year using `cluster_hhi', nogen
tempfile cluster_metrics
save `cluster_metrics'

* ----------------------------------------------------------------------
* 3. Finalize Reference Table & Map to Focal Windows
* ----------------------------------------------------------------------
di ">>> 3. Assembling Final Metrics & Mapping to Windows..."
use `anchor_years', clear
merge m:1 cpc_class grant_year using `class_metrics', keep(match master) nogen
merge m:1 cpc_cluster grant_year using `cluster_metrics', keep(match master) nogen
tempfile metrics_ref
save `metrics_ref'

use "$clean/master_with_location.dta", clear
drop if grant_year > 2019

* Loop through the 3 decision windows dynamically
foreach w in 1 2 3 {
    local offset = (`w' - 1) * 4
    gen g_year_offset = grant_year + `offset'
    
    preserve
        use `metrics_ref', clear
        rename grant_year g_year_offset
        rename (new_flowq_class new_avgq_class new_medq_class new_hhi_class new_flowq_cluster new_avgq_cluster new_medq_cluster new_hhi_cluster) ///
               (new_flowq`w'_class new_avgq`w'_class new_medq`w'_class new_hhi`w'_class new_flowq`w'_cluster new_avgq`w'_cluster new_medq`w'_cluster new_hhi`w'_cluster)
        tempfile metrics_w`w'
        save `metrics_w`w''
    restore
    
    merge m:1 cpc_class cpc_cluster g_year_offset using `metrics_w`w'', keep(match master) nogen
    drop g_year_offset
}

* ----------------------------------------------------------------------
* 4. IHS Transformations & Save
* ----------------------------------------------------------------------
di ">>> 4. Applying IHS Transforms..."
foreach v of varlist new_flowq* new_avgq* new_medq* new_hhi* {
    replace `v' = 0 if missing(`v')
    gen log_`v' = log(`v' + sqrt(`v'^2 + 1))
}

save "$clean/master_new_entrant_measures.dta", replace
di ">>> Script 04b Complete. New Entrant measures safely isolated."
