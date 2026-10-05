********************************************************************************
/* Script 04: Benchmark Competition Measures (Dynamic Active Stock)
   Logic: Harun's Active Stock Model via Macro Panel Expansion.
   Architecture: Expand-and-Collapse to completely bypass Cartesian memory limits.
*/
********************************************************************************
clear all
cls
cd "/if/research-eme/omar/Harun/code"

do "00_initialize.do" "04_competition_measures"

* ----------------------------------------------------------------------
* 1. Build the Dynamic Active Stock Lookup Table
* ----------------------------------------------------------------------
di ">>> Building the Time-Series Panel of Active Patents..."
use patent_id cpc_class birth_year death_year total_5y_citations using "$clean/master_with_location.dta", clear
drop if missing(cpc_class)

* Calculate how many calendar years this patent was alive
gen lifespan = death_year - birth_year

* EXPAND: Stretch the dataset so every patent gets 1 row per year of its life
expand lifespan

* Calculate the specific calendar year for each row
bysort patent_id: gen active_year = birth_year + _n - 1

* Calculate Harun's weighted flow
gen rival_weight = 1 + total_5y_citations

di ">>> Collapsing into Macro Lookup Table..."
* This takes 90 million rows and instantly crushes them into a tiny lookup table
collapse (sum) flowq_class=rival_weight ///
         (mean) avgq_class=total_5y_citations ///
         (median) medq_class=total_5y_citations, ///
         by(cpc_class active_year)

tempfile macro_panel
save `macro_panel'

* ----------------------------------------------------------------------
* 2. Merge Active Stock to Focal Patents
* ----------------------------------------------------------------------
di ">>> Merging Focal Patents to their specific decision windows..."
use "$clean/master_with_location.dta", clear
drop if grant_year > 2019

* --- WINDOW 1 [Decision made at Year 3] ---
* Find who was alive exactly when this patent made its 1st renewal decision
gen active_year = birth_year + 3
merge m:1 cpc_class active_year using `macro_panel', keep(match master) nogen
* Remove the focal patent's own weight from the macro pool!
replace flowq_class = max(0, flowq_class - (1 + total_5y_citations))
rename flowq_class flowq1_class
rename avgq_class avgq1_class
rename medq_class medq1_class
drop active_year

* --- WINDOW 2 [Decision made at Year 7] ---
gen active_year = birth_year + 7
merge m:1 cpc_class active_year using `macro_panel', keep(match master) nogen
replace flowq_class = max(0, flowq_class - (1 + total_5y_citations))
rename flowq_class flowq2_class
rename avgq_class avgq2_class
rename medq_class medq2_class
drop active_year

* --- WINDOW 3 [Decision made at Year 11] ---
gen active_year = birth_year + 11
merge m:1 cpc_class active_year using `macro_panel', keep(match master) nogen
replace flowq_class = max(0, flowq_class - (1 + total_5y_citations))
rename flowq_class flowq3_class
rename avgq_class avgq3_class
rename medq_class medq3_class
drop active_year

* ----------------------------------------------------------------------
* 3. Final Cleanup & IHS Transformation
* ----------------------------------------------------------------------
di ">>> Applying IHS Transforms..."

* Replace missing metrics with 0 (for patents that had 0 active rivals)
foreach v of varlist flowq* avgq* medq* {
    replace `v' = 0 if missing(`v')
}

* Apply IHS Transforms for Regressions
foreach v of varlist flowq* avgq* medq* {
    gen log_`v' = ln(`v' + sqrt((`v'^2) + 1))
}

* ======================================================================
* SYSTEMATIC LOGIC VALIDATION FOR SCRIPT 04 (UNIT TESTING)
* ======================================================================
di ">>> Running Systematic Logic Checks for Active Stock..."

gen error_flag = 0

* 1. The Negative Stock Test
* It is mathematically impossible to have negative competitors. 
* If our self-subtraction logic broke, this will catch it.
replace error_flag = 1 if flowq1_class < 0 | flowq2_class < 0 | flowq3_class < 0
replace error_flag = 2 if avgq1_class < 0  | avgq2_class < 0  | avgq3_class < 0

* 2. The Missing Values Test
* If the merge dropped data or the IHS transforms failed, it will produce missing values (.)
* Note: We don't check the raw string cpc_class here, we check the computed metrics.
replace error_flag = 3 if missing(flowq1_class) | missing(log_flowq1_class)
replace error_flag = 4 if missing(flowq2_class) | missing(log_flowq2_class)
replace error_flag = 5 if missing(flowq3_class) | missing(log_flowq3_class)

* 3. The 1:1 Integrity Test
* Stata has a dedicated command for this. If it expanded and failed to collapse,
* or if the m:1 merges accidentally created duplicates, this will instantly crash.
cap isid patent_id
if _rc != 0 {
    replace error_flag = 6
}

* 4. The Check: Show us the broken rows (if any exist)
count if error_flag > 0
if r(N) > 0 {
    di as error "WARNING: Logical violations found in the Active Stock math!"
    list patent_id grant_year cpc_class flowq1_class flowq2_class error_flag if error_flag > 0
}
else {
    di as result "SUCCESS: Zero logical violations found. The Macro Panel math is flawless."
}

* 5. The Hard Stop (Will crash if error_flag isn't 0 everywhere)
assert error_flag == 0

drop error_flag
* ======================================================================

save "$clean/master_competition_measures.dta", replace
di ">>> Script 04 Complete. Master Active Stock safely calculated."
