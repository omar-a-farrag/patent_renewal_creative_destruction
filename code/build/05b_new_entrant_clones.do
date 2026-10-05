********************************************************************************
/* Script 05b: New Entrant Bibliographic Overlap & Clones
   Logic: Isolates clones that are granted AFTER the focal patent (Displacement).
   Updates: Corrected to use %08.0f padding!
*/
********************************************************************************
clear all
cls
cd "/if/research-eme/omar/Harun/code"

do "00_initialize.do" "05b_new_entrant_clones"

* ======================================================================
* 0. PURGE BROKEN DATA FROM MASTER
* Safely drop the ghost columns so the merge can replace them cleanly
* ======================================================================
di ">>> 0. Purging corrupted New Entrant columns from Master..."
use "$clean/master_regression_file.dta", clear
capture drop new_clone_count* new_clone_avgq* new_overlap_count* log_new_clone* log_new_overlap*
save "$clean/master_regression_file.dta", replace
* ======================================================================

* ----------------------------------------------------------------------
* 1. Prep the Citation Network (The Prior Art)
* ----------------------------------------------------------------------
di ">>> 1. Loading Citation Network..."
import delimited "$raw/g_us_patent_citation.tsv", clear stringcols(_all)

* Apply the CORRECT Zero-Padding Emulator for historic IDs!
gen is_num_p = real(patent_id) != .
replace patent_id = string(real(patent_id), "%08.0f") if is_num_p

rename citation_patent_id foundation_id
gen is_num_f = real(foundation_id) != .
replace foundation_id = string(real(foundation_id), "%08.0f") if is_num_f

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
di ">>> 2. Prepping Focal Baselines & Rival Lifespans..."

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
* 3. Chunking Focal Patents
* ----------------------------------------------------------------------
di ">>> 3. Prepping Focal Chunks..."
use patent_id birth_year grant_year using "$clean/master_competition_measures.dta", clear
drop if grant_year > 2019

merge 1:1 patent_id using `base_counts', keep(master match) nogen

preserve
    keep if missing(focal_base_count)
    save "$clean/temp_zero_cites.dta", replace
restore

keep if !missing(focal_base_count)

set seed 12345
gen rand = runiform()
xtile chunk = rand, n(50)
drop rand

forval c = 1/50 {
    preserve
    keep if chunk == `c'
    rename patent_id focal_id
    rename birth_year focal_birth
    save "$clean/temp_focal_chunk_`c'.dta", replace
    restore
}
drop chunk

* ----------------------------------------------------------------------
* 4. The NEW ENTRANT Calculation Loop
* ----------------------------------------------------------------------
forval c = 1/50 {
    di " "
    di ">>> Processing Chunk `c' of 50..."
    use "$clean/temp_focal_chunk_`c'.dta", clear
    
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
    
    * ==================================================================
    * THE NEW ENTRANT TRAPDOOR
    * Only count rivals that are granted STRICTLY AFTER the focal patent
    * ==================================================================
    gen new_w1 = (rival_birth > focal_birth & rival_birth <= (focal_birth + 3))
    gen new_w2 = (rival_birth > (focal_birth + 4) & rival_birth <= (focal_birth + 7))
    gen new_w3 = (rival_birth > (focal_birth + 8) & rival_birth <= (focal_birth + 11))
    
    gen w1_new_clone = is_clone if new_w1 == 1
    gen w1_new_overlap = shared_count if new_w1 == 1
    gen w1_new_qual = rival_citations if new_w1 == 1 & is_clone == 1
    
    gen w2_new_clone = is_clone if new_w2 == 1
    gen w2_new_overlap = shared_count if new_w2 == 1
    gen w2_new_qual = rival_citations if new_w2 == 1 & is_clone == 1
    
    gen w3_new_clone = is_clone if new_w3 == 1
    gen w3_new_overlap = shared_count if new_w3 == 1
    gen w3_new_qual = rival_citations if new_w3 == 1 & is_clone == 1
    
    collapse (sum) new_clone_count1=w1_new_clone new_clone_count2=w2_new_clone new_clone_count3=w3_new_clone ///
                   new_overlap_count1=w1_new_overlap new_overlap_count2=w2_new_overlap new_overlap_count3=w3_new_overlap ///
             (mean) new_clone_avgq1=w1_new_qual new_clone_avgq2=w2_new_qual new_clone_avgq3=w3_new_qual, by(focal_id)
             
    rename focal_id patent_id
    save "$clean/temp_new_clone_chunk_`c'.dta", replace
}

* ----------------------------------------------------------------------
* 5. Final Assembly & Master Merge
* ----------------------------------------------------------------------
di ">>> 5. Assembling and Merging onto Master Regression File..."

use "$clean/temp_new_clone_chunk_1.dta", clear
forval c = 2/50 {
    append using "$clean/temp_new_clone_chunk_`c'.dta"
}

append using "$clean/temp_zero_cites.dta"
*capture drop grant_year 
*drop focal_base_count
keep patent_id new_clone_count* new_clone_avgq* new_overlap_count*

merge 1:1 patent_id using "$clean/master_regression_file.dta", keep(using match) nogen

foreach v of varlist new_clone_count* new_clone_avgq* new_overlap_count* {
    replace `v' = 0 if missing(`v')
}

foreach v of varlist new_clone_count* new_clone_avgq* new_overlap_count* {
    gen log_`v' = ln(`v' + sqrt((`v'^2) + 1))
}

forval c = 1/50 {
    erase "$clean/temp_focal_chunk_`c'.dta"
    erase "$clean/temp_new_clone_chunk_`c'.dta"
}
erase "$clean/temp_zero_cites.dta"

assert !missing(grant_year, birth_year)

save "$clean/master_regression_file.dta", replace
di ">>> SCRIPT 05B COMPLETE! Corrected New Entrant Clones added to Master Data."
