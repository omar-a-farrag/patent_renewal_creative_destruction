********************************************************************************
/* Script 05: Bibliographic Overlap (Foundation Crowding)
   Logic: Measures crowding on your foundation using rolling 4-year windows.
*/
********************************************************************************
clear all
cls
* 0. Adjust current directory as needed in order to run intilization script
cd "Z:/research-eme/omar/Harun/code"

do "00_initialize.do" "05_bibliographic_overlap"

********************************************************************************
/* Script 05: Bibliographic Overlap (Foundation Crowding)
   Logic: Counts new rivals citing your prior art foundations.
   Fix: Changed 'gen' to 'replace' for grant_year to avoid r(110).
*/
********************************************************************************
do "00_initialize.do" "05_bibliographic_overlap"

* --- Sub-routine: Uniform ID Cleaning ---
capture program drop clean_ids
program define clean_ids
    tostring patent_id, replace
    replace patent_id = trim(itrim(patent_id))
    replace patent_id = subinstr(patent_id, "US", "", .)
    replace patent_id = subinstr(patent_id, " ", "", .)
    gen is_num_tmp = real(patent_id) != .
    replace patent_id = string(real(patent_id), "%08.0f") if is_num_tmp == 1
    drop is_num_tmp
end

* 1. Create Reference Table (Foundation Popularity)
import delimited "$raw/g_us_patent_citation.tsv", delimiter(tab) clear
keep patent_id citation_patent_id // Hygiene: Drop 5 unused columns immediately
rename (patent_id citation_patent_id) (citing_id patent_id)
clean_ids

preserve
    use "$clean/cleaned_renewals_wide.dta", clear
    keep patent_id grant_year
    rename patent_id citing_id
    tempfile rival_years
    save `rival_years'
restore

merge m:1 citing_id using `rival_years', keep(match) nogen
drop citing_id

gen one = 1
collapse (sum) yr_cite_count = one, by(patent_id grant_year)
sort patent_id grant_year
rangestat (sum) overlap_roll = yr_cite_count, interval(grant_year 0 3) by(patent_id)

rename patent_id foundation_id
tempfile overlap_ref
save `overlap_ref'
clear 

********************************************************************************
* 2. Sequential Window Processing
********************************************************************************
forval w = 1/3 {
    di ">>> Processing Window `w'..."
    
    import delimited "$raw/g_us_patent_citation.tsv", delimiter(tab) clear
    keep patent_id citation_patent_id
    rename (patent_id citation_patent_id) (master_id foundation_id)
    
    preserve
        use "$for_regs/master_regression_file.dta", clear
        local offset = (`w' - 1) * 4
        * FIX: Use 'replace' because grant_year already exists in the master file
        replace grant_year = grant_year + `offset' 
        keep patent_id grant_year
        rename patent_id master_id
        tempfile years_w`w'
        save `years_w`w''
    restore
    
    merge m:1 master_id using `years_w`w'', keep(match) nogen
    merge m:1 foundation_id grant_year using `overlap_ref', keep(match master) nogen
    
    replace overlap_roll = 0 if overlap_roll == .
    bysort master_id: egen overlap`w' = sum(overlap_roll)
    
    keep master_id overlap`w'
    duplicates drop
    rename master_id patent_id
    tempfile final_w`w'
    save `final_w`w''
    
    clear 
}

********************************************************************************
* 3. Final Integration
********************************************************************************
use "$for_regs/master_regression_file.dta", clear

foreach w in 1 2 3 {
    merge 1:1 patent_id using `final_w`w'', keep(match master) nogen
    replace overlap`w' = 0 if overlap`w' == .
    gen log_overlap`w' = log(overlap`w' + sqrt(overlap`w'^2 + 1))
}

save "$for_regs/master_regression_file.dta", replace
di ">>> Step 05 Complete. Master regression file finalized."
log close
