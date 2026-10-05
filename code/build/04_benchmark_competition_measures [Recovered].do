********************************************************************************
/* Script 04: Benchmark Competition Measures (Dynamic Active Stock)
   Logic: Harun's Active Stock Model via Macro Panel Expansion.
   Architecture: Expand-and-Collapse to completely bypass Cartesian memory limits.
   Updates: Corrected Firm-level HHI calculation + cpc_cluster level expansion.
*/
********************************************************************************
clear all
cls
cd "/if/research-eme/omar/Harun/code"

do "00_initialize.do" "04_competition_measures"

* ----------------------------------------------------------------------
* 1. Build the Expanded Base Panel
* ----------------------------------------------------------------------
di ">>> 1. Building the Time-Series Panel of Active Patents..."
* LOAD BOTH CLASS AND CLUSTER PLUS ASSIGNEE
use patent_id assignee_id cpc_class cpc_cluster birth_year death_year total_5y_citations using "$clean/master_with_location.dta", clear

* Calculate how many calendar years this patent was alive
gen lifespan = death_year - birth_year

* EXPAND: Stretch the dataset so every patent gets 1 row per year of its life
expand lifespan

* Calculate the specific calendar year for each row
bysort patent_id: gen active_year = birth_year + _n - 1

* Calculate Harun's weighted flow
gen rival_weight = 1 + total_5y_citations

* Save to hard drive to avoid RAM explosion during the double-collapse
tempfile expanded_base
save `expanded_base'

* ----------------------------------------------------------------------
* 2A. Collapse the CLASS Macro Panel
* ----------------------------------------------------------------------
di ">>> 2A. Collapsing CLASS Macro Lookup Table..."
use `expanded_base', clear
drop if missing(cpc_class)

* 1. Get total class weight
bysort cpc_class active_year: egen total_class_weight = sum(rival_weight)

* 2. Get the total weight for EACH FIRM in that class-year
bysort cpc_class active_year assignee_id: egen firm_weight = sum(rival_weight)

* 3. Tag exactly ONE row per firm so we don't double-count their squared share
egen firm_tag = tag(cpc_class active_year assignee_id)

* 4. Calculate Firm Share and Square it (Only on the tagged rows)
gen firm_share = firm_weight / total_class_weight
gen hhi_component = (firm_share * 100)^2 if firm_tag == 1

* --- REVISED BLOCK: Extract Firm Market Shares & Size Bins (Decile + Quartile) ---
preserve
    keep if firm_tag == 1
    keep cpc_class active_year assignee_id firm_share
    
    * Cohort-specific share thresholds (Deciles & Quartiles)
    bysort cpc_class active_year: egen share_p10 = pctile(firm_share), p(10)
    bysort cpc_class active_year: egen share_p25 = pctile(firm_share), p(25)
    bysort cpc_class active_year: egen share_p75 = pctile(firm_share), p(75)
    bysort cpc_class active_year: egen share_p90 = pctile(firm_share), p(90)
    
    * 1. Primary Cutoffs (Top/Bottom Decile vs. Middle 80%)
    gen is_big_p90   = (firm_share >= share_p90) & !missing(firm_share)
    gen is_small_p10 = (firm_share <= share_p10) & !missing(firm_share)
    gen firm_size_bin = 2
    replace firm_size_bin = 3 if is_big_p90 == 1
    replace firm_size_bin = 1 if is_small_p10 == 1

    * 2. Robustness Cutoffs (Top/Bottom Quartile vs. Middle 50%)
    gen is_big_p75   = (firm_share >= share_p75) & !missing(firm_share)
    gen is_small_p25 = (firm_share <= share_p25) & !missing(firm_share)
    gen firm_size_bin_quartile = 2
    replace firm_size_bin_quartile = 3 if is_big_p75 == 1
    replace firm_size_bin_quartile = 1 if is_small_p25 == 1
    
    keep cpc_class active_year assignee_id is_big_p90 is_big_p75 is_small_p10 is_small_p25 firm_size_bin firm_size_bin_quartile firm_share
    rename active_year grant_year // To match focal patent's grant year
    save "$clean/firm_size_lookup.dta", replace
restore

collapse (sum) flowq_class=rival_weight hhi_class=hhi_component ///
         (mean) avgq_class=total_5y_citations ///
         (median) medq_class=total_5y_citations, ///
         by(cpc_class active_year)

tempfile macro_class
save `macro_class'

* ----------------------------------------------------------------------
* 2B. Collapse the CLUSTER Macro Panel
* ----------------------------------------------------------------------
di ">>> 2B. Collapsing CLUSTER Macro Lookup Table..."
use `expanded_base', clear
drop if missing(cpc_cluster)

* 1. Get total cluster weight
bysort cpc_cluster active_year: egen total_cluster_weight = sum(rival_weight)

* 2. Get the total weight for EACH FIRM in that cluster-year
bysort cpc_cluster active_year assignee_id: egen firm_weight = sum(rival_weight)

* 3. Tag exactly ONE row per firm
egen firm_tag = tag(cpc_cluster active_year assignee_id)

* 4. Calculate Firm Share and Square it (Only on the tagged rows)
gen firm_share = firm_weight / total_cluster_weight
gen hhi_component = (firm_share * 100)^2 if firm_tag == 1

collapse (sum) flowq_cluster=rival_weight hhi_cluster=hhi_component ///
         (mean) avgq_cluster=total_5y_citations ///
         (median) medq_cluster=total_5y_citations, ///
         by(cpc_cluster active_year)

tempfile macro_cluster
save `macro_cluster'

* ----------------------------------------------------------------------
* 3. Merge Active Stock to Focal Patents
* ----------------------------------------------------------------------
di ">>> 3. Merging Focal Patents to their specific decision windows..."
use "$clean/master_with_location.dta", clear
drop if grant_year > 2019

* --- WINDOW 1 [Decision made at Year 3] ---
gen active_year = birth_year + 3
* Merge Class
merge m:1 cpc_class active_year using `macro_class', keep(match master) nogen
replace flowq_class = max(0, flowq_class - (1 + total_5y_citations))
rename flowq_class flowq1_class
rename avgq_class avgq1_class
rename medq_class medq1_class
rename hhi_class hhi1_class
* Merge Cluster
merge m:1 cpc_cluster active_year using `macro_cluster', keep(match master) nogen
replace flowq_cluster = max(0, flowq_cluster - (1 + total_5y_citations))
rename flowq_cluster flowq1_cluster
rename avgq_cluster avgq1_cluster
rename medq_cluster medq1_cluster
rename hhi_cluster hhi1_cluster
drop active_year

* --- WINDOW 2 [Decision made at Year 7] ---
gen active_year = birth_year + 7
merge m:1 cpc_class active_year using `macro_class', keep(match master) nogen
replace flowq_class = max(0, flowq_class - (1 + total_5y_citations))
rename flowq_class flowq2_class
rename avgq_class avgq2_class
rename medq_class medq2_class
rename hhi_class hhi2_class

merge m:1 cpc_cluster active_year using `macro_cluster', keep(match master) nogen
replace flowq_cluster = max(0, flowq_cluster - (1 + total_5y_citations))
rename flowq_cluster flowq2_cluster
rename avgq_cluster avgq2_cluster
rename medq_cluster medq2_cluster
rename hhi_cluster hhi2_cluster
drop active_year

* --- WINDOW 3 [Decision made at Year 11] ---
gen active_year = birth_year + 11
merge m:1 cpc_class active_year using `macro_class', keep(match master) nogen
replace flowq_class = max(0, flowq_class - (1 + total_5y_citations))
rename flowq_class flowq3_class
rename avgq_class avgq3_class
rename medq_class medq3_class
rename hhi_class hhi3_class

merge m:1 cpc_cluster active_year using `macro_cluster', keep(match master) nogen
replace flowq_cluster = max(0, flowq_cluster - (1 + total_5y_citations))
rename flowq_cluster flowq3_cluster
rename avgq_cluster avgq3_cluster
rename medq_cluster medq3_cluster
rename hhi_cluster hhi3_cluster
drop active_year

* ----------------------------------------------------------------------
* 4. Final Cleanup & IHS Transformation
* ----------------------------------------------------------------------
di ">>> 4. Applying IHS Transforms..."

* The wildcards (*) will automatically catch both _class and _cluster!
foreach v of varlist flowq* avgq* medq* hhi* {
    replace `v' = 0 if missing(`v')
}

foreach v of varlist flowq* avgq* medq* hhi* {
    gen log_`v' = ln(`v' + sqrt((`v'^2) + 1))
}

* ======================================================================
* SYSTEMATIC LOGIC VALIDATION FOR SCRIPT 04 (UNIT TESTING)
* ======================================================================
di ">>> Running Systematic Logic Checks for Active Stock..."

gen error_flag = 0

* 1. The Negative Stock Test (Class & Cluster)
replace error_flag = 1 if flowq1_class < 0 | flowq2_class < 0 | flowq3_class < 0
replace error_flag = 2 if flowq1_cluster < 0 | flowq2_cluster < 0 | flowq3_cluster < 0
replace error_flag = 3 if avgq1_class < 0  | avgq1_cluster < 0

* 2. The Missing Values Test
replace error_flag = 4 if missing(flowq1_class) | missing(log_flowq1_cluster)
replace error_flag = 5 if missing(flowq2_class) | missing(log_flowq2_cluster)

* 3. The 1:1 Integrity Test
cap isid patent_id
if _rc != 0 {
    replace error_flag = 6
}

* 4. The HHI Bounds Test (Class & Cluster)
replace error_flag = 7 if hhi1_class < 0 | hhi1_class > 10001
replace error_flag = 8 if hhi1_cluster < 0 | hhi1_cluster > 10001

* 5. The Check: Show us the broken rows (if any exist)
count if error_flag > 0
if r(N) > 0 {
    di as error "WARNING: Logical violations found in the Active Stock math!"
    list patent_id grant_year cpc_class flowq1_class flowq1_cluster hhi1_class error_flag if error_flag > 0
}
else {
    di as result "SUCCESS: Zero logical violations found. The Multi-Level Macro Panel math is flawless."
}

assert error_flag == 0
drop error_flag
* ======================================================================
* ======================================================================
* NEW MERGE: Attach Firm Size and Breakthrough Quality to Focal Patents
* ======================================================================
merge m:1 cpc_class grant_year assignee_id using "$clean/firm_size_lookup.dta", keep(master match) nogen

* Fill missing for firms that didn't match (assumed competitive fringe)
replace is_big_p90   = 0 if missing(is_big_p90)
replace is_big_p75   = 0 if missing(is_big_p75)
replace is_small_p10 = 0 if missing(is_small_p10)
replace is_small_p25 = 0 if missing(is_small_p25)
replace firm_size_bin          = 2 if missing(firm_size_bin)
replace firm_size_bin_quartile = 2 if missing(firm_size_bin_quartile)

* Create Breakthrough Indicator (Top 5% citations in Class-Year)
bysort cpc_class grant_year: egen p95_cites = pctile(total_5y_citations), p(95)
gen is_breakthrough = (total_5y_citations >= p95_cites) & !missing(total_5y_citations)
drop p95_cites
* ======================================================================

save "$clean/master_competition_measures.dta", replace
di ">>> Script 04 Complete. Multi-Level Master Active Stock safely calculated."
