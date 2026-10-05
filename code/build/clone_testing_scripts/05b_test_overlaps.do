********************************************************************************
/* Script 05 TEST: 1,000 Patent Sample Run
   Logic: Verifies that stripping leading zeros fixes the historic patent match!
*/
********************************************************************************
clear all
cls
cd "/if/research-eme/omar/Harun/code"

* ----------------------------------------------------------------------
* 1. Prep the Prior Art (STRIPPING LEADING ZEROS)
* ----------------------------------------------------------------------
di ">>> 1. Loading Citation Network..."
import delimited "$raw/g_us_patent_citation.tsv", clear stringcols(_all)

* STRIP LEADING ZEROS (The True Match Fix)
gen is_num_p = real(patent_id) != .
replace patent_id = trim(string(real(patent_id), "%15.0f")) if is_num_p

rename citation_patent_id foundation_id
gen is_num_f = real(foundation_id) != .
replace foundation_id = trim(string(real(foundation_id), "%15.0f")) if is_num_f

keep patent_id foundation_id
drop if missing(patent_id) | missing(foundation_id)

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
* 3. THE SAMPLE TEST (1,000 Patents Only)
* ----------------------------------------------------------------------
di ">>> 3. Pulling 1,000 Patent Test Sample..."
use patent_id birth_year grant_year using "$clean/master_competition_measures.dta", clear
drop if grant_year > 2019

set seed 12345
sample 1000, count

* ======================================================================
* THE MOMENT OF TRUTH: Does it match the historic patents?
* ======================================================================
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

gen alive_w1 = (rival_death > focal_birth & rival_birth <= (focal_birth + 3))
gen w1_clone = is_clone if alive_w1 == 1
gen w1_overlap = overlap_ratio if alive_w1 == 1

collapse (sum) clone_count1=w1_clone (mean) overlap1=w1_overlap, by(focal_id)

di " "
di "========================================================"
di "TEST RESULTS: Do we have non-zero variance?"
di "========================================================"
summarize clone_count1 overlap1, detail
