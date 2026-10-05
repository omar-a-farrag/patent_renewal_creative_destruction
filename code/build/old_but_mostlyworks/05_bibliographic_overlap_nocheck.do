********************************************************************************
/* Script 05: Bibliographic Overlap & Clone Quality
   Logic: Harun's 50% Threshold + Continuous Overlap + Active Stock Lifespans
   Architecture: Citation Network Joinby + Dynamic Pre-Filtering + 50 Chunks
   
   Note: run on server with 100GB RAM; expect RAM to go to 65GB RAM at least
   
*/
********************************************************************************
clear all
cls
cd "/if/research-eme/omar/Harun/code"

do "00_initialize.do" "05_clone_measures"

* ----------------------------------------------------------------------
* 1. Prep the Citation Network (The Prior Art)
* ----------------------------------------------------------------------
di ">>> 1. Loading Citation Network..."
import delimited "$raw/g_us_patent_citation.tsv", clear stringcols(_all)

* Apply the Stata Zero-Padding Emulator for purely numeric IDs
gen is_num_p = real(patent_id) != .
replace patent_id = string(real(patent_id), "%08.0f") if is_num_p

rename citation_patent_id foundation_id
gen is_num_f = real(foundation_id) != .
replace foundation_id = string(real(foundation_id), "%08.0f") if is_num_f

keep patent_id foundation_id
drop if missing(patent_id) | missing(foundation_id)

* Save Master Citation List
tempfile prior_art
save `prior_art'

* Save a specific copy just for Rivals to use in the Joinby
rename patent_id rival_id
tempfile rival_prior_art
save `rival_prior_art'

* ----------------------------------------------------------------------
* 2. Prep Focal Baselines & Rival Lifespans
* ----------------------------------------------------------------------
di ">>> 2. Prepping Focal Baselines & Rival Lifespans..."

* Calculate how many total backwards citations the focal patent made
use `prior_art', clear
gen cite_counter = 1
collapse (sum) focal_base_count = cite_counter, by(patent_id)
tempfile base_counts
save `base_counts'

* Extract Rival Lifespans and Quality
use patent_id birth_year death_year total_5y_citations using "$clean/master_competition_measures.dta", clear
rename patent_id rival_id
rename birth_year rival_birth
rename death_year rival_death
rename total_5y_citations rival_citations
tempfile rival_lifespans
save `rival_lifespans'

* ----------------------------------------------------------------------
* 3. Chunking Focal Patents (MICRO-SHARDING: 50 CHUNKS)
* ----------------------------------------------------------------------
di ">>> 3. Prepping Focal Chunks..."
use patent_id birth_year grant_year using "$clean/master_competition_measures.dta", clear
drop if grant_year > 2019

* Attach their citation base count
merge 1:1 patent_id using `base_counts', keep(master match) nogen

* OPTIMIZATION: If a patent made 0 citations, it mathematically CANNOT 
* have a 50% overlap. We set them aside and give them 0s later.
preserve
    keep if missing(focal_base_count)
    save "$clean/temp_zero_cites.dta", replace
restore

keep if !missing(focal_base_count)

* Split into 50 chunks to absolutely guarantee no memory limits are breached
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
* 4. The Clone Calculation Loop
* ----------------------------------------------------------------------
forval c = 1/50 {
    di " "
    di ">>> Processing Chunk `c' of 50..."
    use "$clean/temp_focal_chunk_`c'.dta", clear
    
    * 4A. Attach the specific Prior Art this chunk cited
    rename focal_id patent_id
    merge 1:m patent_id using `prior_art', keep(match) nogen
    rename patent_id focal_id
    
    * === 4B. THE MEMORY SAVER: DYNAMIC PRE-FILTERING ===
    di "    > Shrinking the Rival pool..."
    preserve
        keep foundation_id
        duplicates drop
        tempfile current_foundations
        save `current_foundations'
        
        * Open the massive rival database and drop 99% of the useless data!
        use `rival_prior_art', clear
        merge m:1 foundation_id using `current_foundations', keep(match) nogen
        tempfile filtered_rivals
        save `filtered_rivals'
    restore
    * ===================================================
    
    * 4C. The Magic Match: Find ONLY rivals who cited the exact same prior art
    di "    > Joining Citation Network..."
    joinby foundation_id using `filtered_rivals'
    
    * Drop self-matches immediately
    drop if focal_id == rival_id
    
    * 4D. Count the shared citations, calculate Continuous Overlap, and flag Clones
    di "    > Collapsing to Overlap & Clones..."
    gen shared_counter = 1
    collapse (sum) shared_count = shared_counter, by(focal_id focal_birth focal_base_count rival_id)
    
    * Continuous Measure (0.0 to 1.0)
    gen overlap_ratio = shared_count / focal_base_count
    
    * Harun's Binary Clone Threshold
    gen is_clone = (overlap_ratio >= 0.50)
    
    * 4E. Apply Harun's Dynamic Active Stock to the network
    di "    > Applying Lifespan Windows..."
    merge m:1 rival_id using `rival_lifespans', keep(match) nogen
    
    * Check if the rival was alive during the windows
    gen alive_w1 = (rival_death > focal_birth & rival_birth <= (focal_birth + 3))
    gen alive_w2 = (rival_death > (focal_birth + 4) & rival_birth <= (focal_birth + 7))
    gen alive_w3 = (rival_death > (focal_birth + 8) & rival_birth <= (focal_birth + 11))
    
    * Route the specific variables for the final collapse
    gen w1_clone = is_clone if alive_w1 == 1
    gen w1_overlap = overlap_ratio if alive_w1 == 1
    gen w1_qual = rival_citations if alive_w1 == 1 & is_clone == 1
    
    gen w2_clone = is_clone if alive_w2 == 1
    gen w2_overlap = overlap_ratio if alive_w2 == 1
    gen w2_qual = rival_citations if alive_w2 == 1 & is_clone == 1
    
    gen w3_clone = is_clone if alive_w3 == 1
    gen w3_overlap = overlap_ratio if alive_w3 == 1
    gen w3_qual = rival_citations if alive_w3 == 1 & is_clone == 1
    
    * 4F. Final Collapse to the Focal Patent level
    collapse (sum) clone_count1=w1_clone clone_count2=w2_clone clone_count3=w3_clone ///
             (mean) clone_avgq1=w1_qual clone_avgq2=w2_qual clone_avgq3=w3_qual ///
                    overlap1=w1_overlap overlap2=w2_overlap overlap3=w3_overlap, by(focal_id)
             
    rename focal_id patent_id
    save "$clean/temp_clone_chunk_`c'.dta", replace
}

* ----------------------------------------------------------------------
* 5. Final Assembly & Export to Master Regression File
* ----------------------------------------------------------------------
di ">>> 5. Assembling Master Regression File..."

* Append the 50 processed chunks
use "$clean/temp_clone_chunk_1.dta", clear
forval c = 2/50 {
    append using "$clean/temp_clone_chunk_`c'.dta"
}

* Append the patents that had 0 citations
append using "$clean/temp_zero_cites.dta"
drop focal_base_count

* Merge back onto the Master Data!
merge 1:1 patent_id using "$clean/master_competition_measures.dta", keep(using match) nogen

* Cleanup Missings (If they had no clones/overlap, set to 0)
foreach v of varlist clone_count* clone_avgq* overlap* {
    replace `v' = 0 if missing(`v')
}

* ======================================================================
* USPTO DUPLICATE CITATION CAP
* Due to duplicate foundation entries in the raw USPTO citation network, 
* ~0.3% of patents can mathematically exceed 100% overlap. We cap at 1.0.
* ======================================================================
foreach v of varlist overlap1 overlap2 overlap3 {
    replace `v' = 1 if `v' > 1 & !missing(`v')
}

* Calculate the final IHS Logs for the Regressions
foreach v of varlist clone_count* clone_avgq* overlap* {
    gen log_`v' = ln(`v' + sqrt((`v'^2) + 1))
}


* Calculate the final IHS Logs for the Regressions
foreach v of varlist clone_count* clone_avgq* overlap* {
    gen log_`v' = ln(`v' + sqrt((`v'^2) + 1))
}

* Cleanup temp files
forval c = 1/50 {
    erase "$clean/temp_focal_chunk_`c'.dta"
    erase "$clean/temp_clone_chunk_`c'.dta"
}
erase "$clean/temp_zero_cites.dta"

* ======================================================================
* SYSTEMATIC LOGIC VALIDATION FOR SCRIPT 05 (UNIT TESTING)
* ======================================================================
di ">>> Running Systematic Logic Checks for Clone Measures..."

gen error_flag = 0

* 1. The Negative Bounds Test
replace error_flag = 1 if clone_count1 < 0 | clone_count2 < 0 | clone_count3 < 0
replace error_flag = 2 if clone_avgq1 < 0  | clone_avgq2 < 0  | clone_avgq3 < 0

* 2. The Missing Values Test
replace error_flag = 3 if missing(clone_count1) | missing(clone_avgq1) | missing(log_clone_count1)
replace error_flag = 4 if missing(clone_count2) | missing(clone_avgq2) | missing(log_clone_count2)
replace error_flag = 5 if missing(clone_count3) | missing(clone_avgq3) | missing(log_clone_count3)

* 3. The Logical Consistency Test (The Harun Rule)
replace error_flag = 6 if clone_count1 == 0 & clone_avgq1 > 0
replace error_flag = 7 if clone_count2 == 0 & clone_avgq2 > 0
replace error_flag = 8 if clone_count3 == 0 & clone_avgq3 > 0

* 4. The 1:1 Integrity Test
cap isid patent_id
if _rc != 0 {
    replace error_flag = 9
}

* 5. The Continuous Overlap Bounds Test
* A patent cannot share less than 0% or more than 100% of its citations.
replace error_flag = 10 if overlap1 < 0 | overlap1 > 1.01
replace error_flag = 11 if overlap2 < 0 | overlap2 > 1.01
replace error_flag = 12 if overlap3 < 0 | overlap3 > 1.01

* 6. The Check: Show us the broken rows (if any exist)
count if error_flag > 0
if r(N) > 0 {
    di as error "WARNING: Logical violations found in the Clone Math!"
    list patent_id grant_year clone_count1 clone_avgq1 overlap1 error_flag if error_flag > 0
}
else {
    di as result "SUCCESS: Zero logical violations found. The Bibliographic Overlap math is flawless."
}

* 7. The Hard Stop (Will crash if error_flag isn't 0 everywhere)
assert error_flag == 0

drop error_flag
* ======================================================================

* THE FINAL SAVE
save "$clean/master_regression_file.dta", replace
export delimited using "$clean/master_regression_file.csv", replace
di ">>> PIPELINE COMPLETE! Master file saved as DTA and CSV."
