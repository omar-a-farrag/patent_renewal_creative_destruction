********************************************************************************
/* Script 05 TEST: 10,000 Patent Sample Run
   Logic: Verifies that the ORIGINAL %08.0f padding + duplicates drop works,
          AND proves the regression won't drop due to collinearity.
*/
********************************************************************************
clear all
cls
cd "/if/research-eme/omar/Harun/code"

* ----------------------------------------------------------------------
* 1. Prep the Prior Art (ORIGINAL %08.0f PADDING)
* ----------------------------------------------------------------------
di ">>> 1. Loading Citation Network..."
import delimited "$raw/g_us_patent_citation.tsv", clear stringcols(_all)

* THE ORIGINAL, WORKING PADDING LOGIC
gen is_num_p = real(patent_id) != .
replace patent_id = string(real(patent_id), "%08.0f") if is_num_p

rename citation_patent_id foundation_id
gen is_num_f = real(foundation_id) != .
replace foundation_id = string(real(foundation_id), "%08.0f") if is_num_f

keep patent_id foundation_id
drop if missing(patent_id) | missing(foundation_id)

* THE DUPLICATE FIX
duplicates drop patent_id foundation_id, force

tempfile prior_art
save `prior_art'

rename patent_id rival_id
tempfile rival_prior_art
save `rival_prior_art'

* ----------------------------------------------------------------------
* 2. Prep Focal Baselines & Rival Lifespans
* ----------------------------------------------------------------------
use `prior_art', clear
gen cite_counter = 1
collapse (sum) focal_base_count = cite_counter, by(patent_id)
tempfile base_counts
save `base_counts'

use patent_id birth_year death_year total_5y_citations using "$clean/master_competition_measures.dta", clear
rename patent_id rival_id
rename birth_year rival_birth
rename death_year rival_death
rename total_5y_citations rival_citations
tempfile rival_lifespans
save `rival_lifespans'

* ----------------------------------------------------------------------
* 3. THE SAMPLE TEST (10,000 Patents)
* ----------------------------------------------------------------------
di ">>> 3. Pulling 10,000 Patent Test Sample..."
use patent_id birth_year grant_year ren2 small_entity total_5y_citations cpc_class using "$clean/master_competition_measures.dta", clear

* We must include historic patents to test ren2!
drop if grant_year > 2017

set seed 12345
sample 10000, count

* Attach citation base count
merge 1:1 patent_id using `base_counts', keep(master match) nogen

keep if !missing(focal_base_count)
rename patent_id focal_id
rename birth_year focal_birth

* ----------------------------------------------------------------------
* 4. The Calculation
* ----------------------------------------------------------------------
di ">>> 4. Running the Joinby Math..."
rename focal_id patent_id
merge 1:m patent_id using `prior_art', keep(match) nogen
rename patent_id focal_id

preserve
    keep foundation_id
    duplicates drop
    tempfile current_foundations
    save `current_foundations'
    
    use `rival_prior_art', clear
    merge m:1 foundation_id using `current_foundations', keep(match) nogen
    tempfile filtered_rivals
    save `filtered_rivals'
restore

joinby foundation_id using `filtered_rivals'
drop if focal_id == rival_id

gen shared_counter = 1
collapse (sum) shared_count = shared_counter, by(focal_id focal_birth focal_base_count rival_id)

gen overlap_ratio = shared_count / focal_base_count
gen is_clone = (overlap_ratio >= 0.50)

merge m:1 rival_id using `rival_lifespans', keep(match) nogen

gen alive_w2 = (rival_death > (focal_birth + 4) & rival_birth <= (focal_birth + 7))
gen w2_clone = is_clone if alive_w2 == 1
gen w2_overlap = overlap_ratio if alive_w2 == 1

collapse (sum) clone_count2=w2_clone (mean) overlap2=w2_overlap, by(focal_id)

* Re-merge the original data for the regression test
rename focal_id patent_id
merge 1:1 patent_id using "$clean/master_competition_measures.dta", keep(match) nogen

* Calculate IHS logs
gen log_clone_count2 = ln(clone_count2 + sqrt((clone_count2^2) + 1))
gen log_internal_quality = ln(total_5y_citations + sqrt((total_5y_citations^2) + 1))

* ----------------------------------------------------------------------
* 5. THE MOMENT OF TRUTH: Does the regression run?
* ----------------------------------------------------------------------
di " "
di "========================================================"
di "TEST RESULTS: REGRESSION COLLINEARITY CHECK"
di "========================================================"
reghdfe ren2 log_clone_count2 overlap2 small_entity log_internal_quality, absorb(cpc_class grant_year) vce(robust)
