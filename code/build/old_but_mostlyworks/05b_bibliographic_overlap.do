********************************************************************************
/* Script 05: Bibliographic Overlap (Foundation Crowding)
   Logic: Measures both raw summation of shared foundations AND the 50% clone threshold.
   Architecture: Sequential sharding (10 chunks) + Double Collapse.
*/
********************************************************************************
clear all
cls

* Adjust current directory as needed
cd "/if/research-eme/omar/Harun/code"

capture which rangejoin
if _rc {
    ssc install rangejoin
}

do "00_initialize.do" "05_bibliographic_overlap"

* --- Sub-routine: Uniform ID Cleaning ---
capture program drop clean_ids
program define clean_ids
    args id_var
    tostring `id_var', replace
    replace `id_var' = trim(itrim(`id_var'))
    replace `id_var' = subinstr(`id_var', "US", "", .)
    replace `id_var' = subinstr(`id_var', " ", "", .)
    gen is_num_tmp = real(`id_var') != .
    replace `id_var' = string(real(`id_var'), "%08.0f") if is_num_tmp == 1
    drop is_num_tmp
end

********************************************************************************
* 1. Create the Universe of "Rival Arrivals" (Un-Collapsed to preserve ID)
********************************************************************************
di ">>> Building Rival Arrivals database..."
import delimited "$raw/g_us_patent_citation.tsv", delimiter(tab) clear
keep patent_id citation_patent_id

clean_ids patent_id
clean_ids citation_patent_id
rename (patent_id citation_patent_id) (citing_id foundation_id)

preserve
    use "$for_regs/master_regression_file.dta", clear
    keep patent_id grant_year
    rename patent_id citing_id
    tempfile rival_years
    save `rival_years'
restore

merge m:1 citing_id using `rival_years', keep(match) nogen

gen rival_year = grant_year
keep foundation_id citing_id rival_year

* Save as a physical file so it persists during the chunking loop
save "$clean/temp_rival_cites_full.dta", replace
clear 

********************************************************************************
* 2. Prep Focal Patents and Assign Chunks (Get Baseline Denominator)
********************************************************************************
di ">>> Prepping Focal Patents for Chunking..."

import delimited "$raw/g_us_patent_citation.tsv", delimiter(tab) clear
keep patent_id citation_patent_id

clean_ids patent_id
clean_ids citation_patent_id
rename (patent_id citation_patent_id) (focal_id foundation_id)

preserve
    use "$for_regs/master_regression_file.dta", clear
    keep patent_id grant_year
    rename patent_id focal_id
    tempfile focal_years
    save `focal_years'
restore

merge m:1 focal_id using `focal_years', keep(match) nogen

* Calculate the baseline denominator (total foundations cited by focal patent)
bysort focal_id: gen focal_base_count = _N

* Instant Chunking Trick: Use the last digit of the focal patent ID (1 to 10)
gen chunk_id = mod(real(focal_id), 10) + 1

* Save the chunked master list
save "$clean/temp_focal_master.dta", replace
clear

********************************************************************************
* 3. The Sequential Sharding Loop (Rangejoin & Double Collapse)
********************************************************************************
di ">>> Beginning Rangejoin Loop..."

forval c = 1/10 {
    di "--- Processing Chunk `c' of 10 ---"
    
    * Load only the current chunk into memory
    use "$clean/temp_focal_master.dta" if chunk_id == `c', clear
    drop chunk_id
    
    * Execute rangejoin on this manageable slice
    rangejoin grant_year 0 11 using "$clean/temp_rival_cites_full.dta", by(foundation_id)

    * ---------------------------------------------------------
    * COLLAPSE 1: Focal-to-Rival Pair Level
    * ---------------------------------------------------------
    collapse (count) shared_count=foundation_id (max) focal_base_count, ///
        by(focal_id citing_id rival_year grant_year)

    * Define the Strict Clone Threshold
    gen overlap_ratio = shared_count / focal_base_count
    gen is_clone = (overlap_ratio >= 0.50)

    * ---------------------------------------------------------
    * BIFURCATION: Route into the 3 Windows
    * ---------------------------------------------------------
    gen overlap_sum1 = shared_count if (rival_year >= grant_year & rival_year <= grant_year + 3)
    gen overlap_thresh1 = is_clone if (rival_year >= grant_year & rival_year <= grant_year + 3)
    
    gen overlap_sum2 = shared_count if (rival_year >= grant_year + 4 & rival_year <= grant_year + 7)
    gen overlap_thresh2 = is_clone if (rival_year >= grant_year + 4 & rival_year <= grant_year + 7)
    
    gen overlap_sum3 = shared_count if (rival_year >= grant_year + 8 & rival_year <= grant_year + 11)
    gen overlap_thresh3 = is_clone if (rival_year >= grant_year + 8 & rival_year <= grant_year + 11)

    foreach v of varlist overlap_sum* overlap_thresh* {
        replace `v' = 0 if missing(`v')
    }

    * ---------------------------------------------------------
    * COLLAPSE 2: Final Focal Level
    * ---------------------------------------------------------
    collapse (sum) overlap_sum* overlap_thresh*, by(focal_id)
    
    * Save the processed slice
    save "$clean/temp_overlap_chunk_`c'.dta", replace
    clear
}

********************************************************************************
* 4. Final Integration & Cleanup
********************************************************************************
di ">>> Appending Chunks and Integrating..."

* Append all 10 chunks together
forval c = 1/10 {
    if `c' == 1 {
        use "$clean/temp_overlap_chunk_`c'.dta", clear
    }
    else {
        append using "$clean/temp_overlap_chunk_`c'.dta"
    }
}

rename focal_id patent_id
tempfile final_overlaps
save `final_overlaps'

* Delete the temporary processing files to keep the directory clean
erase "$clean/temp_rival_cites_full.dta"
erase "$clean/temp_focal_master.dta"
forval c = 1/10 {
    erase "$clean/temp_overlap_chunk_`c'.dta"
}

* Final Merge
use "$for_regs/master_regression_file.dta", clear

* Purge any old overlap columns before merging
capture drop overlap1 overlap2 overlap3
capture drop log_overlap1 log_overlap2 log_overlap3
capture drop overlap_sum* overlap_thresh* capture drop log_overlap_sum* log_overlap_thresh*

merge 1:1 patent_id using `final_overlaps', keep(match master) nogen

foreach w in 1 2 3 {
    replace overlap_sum`w' = 0 if overlap_sum`w' == .
    replace overlap_thresh`w' = 0 if overlap_thresh`w' == .
    
    gen log_overlap_sum`w' = log(overlap_sum`w' + sqrt(overlap_sum`w'^2 + 1))
    gen log_overlap_thresh`w' = log(overlap_thresh`w' + sqrt(overlap_thresh`w'^2 + 1))
}

save "$for_regs/master_regression_file.dta", replace
di ">>> Step 05 Complete. Master regression file finalized."
log close
