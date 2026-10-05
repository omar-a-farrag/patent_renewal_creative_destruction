********************************************************************************
/* Step 00b: Create 5% Debugging Samples (Corrected)
   Logic: Fixes the .txt "muddied" column issue and adds skip-logic flags.
*/
********************************************************************************
clear all
cls
* 0. Adjust current directory as needed in order to run intilization script
cd "Z:/research-eme/omar/Harun/code"

do "00_initialize.do" "00b_create_samples"

* --- USER FLAGS ---
local do_txt  1    // Set to 1 to process the Maintenance Fee .txt file
local do_tsv  0    // Set to 0 to skip the large .tsv files
* ------------------

capture mkdir "$sample"
local files "MaintFeeEvents_20250317.txt g_cpc_current.tsv g_us_patent_citation.tsv g_assignee_disambiguated.tsv g_location_disambiguated.tsv g_inventor_disambiguated.tsv"

set seed 12345 

foreach f of local files {
    local is_tsv = strmatch("`f'", "*.tsv")
    
    * Check user flags to save time
    if (`is_tsv' == 1 & `do_tsv' == 0) continue
    if (`is_tsv' == 0 & `do_txt' == 0) continue
    
    di ">>> Sampling 5% of `f'..."
    
    if `is_tsv' == 1 {
        * TSV Path: Always has headers, use tab delimiter
        import delimited "$raw_full/`f'", delimiter(tab) varnames(1) clear
        quietly sample 5
        export delimited using "$sample/`f'", delimiter(tab) replace
    }
    else {
        * TXT Path: MaintFeeEvents has no headers, use literal space " "
        * varnames(nonames) prevents the first row of data from becoming column names [cite: 136]
        import delimited "$raw_full/`f'", delimiter(" ") varnames(nonames) clear
        quietly sample 5
        * novarnames ensures the exported file is pure data with no header row
        export delimited using "$sample/`f'", delimiter(" ") novarnames replace
    }
    di "    SUCCESS: Saved to $sample/`f'"
}

di ">>> 5% Sandbox sampling complete."
log close