********************************************************************************
/* Script 02: 5-Year Citations, Clusters, and Assignees
   Logic: Filters citations to a 5-year window and merges tech/owner data.
*/
********************************************************************************
clear all
cls
* 0. Adjust current directory as needed in order to run intilization script
cd "Z:/research-eme/omar/Harun/code"

do "00_initialize.do" "02_citations_clusters_assignees"

* --- Sub-routine: Uniform ID Cleaning (Ensures high match rates) ---
capture program drop clean_ids
program define clean_ids
    tostring patent_id, replace
    replace patent_id = trim(itrim(patent_id))
    replace patent_id = subinstr(patent_id, "US", "", .)
    replace patent_id = subinstr(patent_id, " ", "", .)
    * Force 8-digit padding for numeric IDs
    gen is_numeric_id = real(patent_id) != .
    replace patent_id = string(real(patent_id), "%08.0f") if is_numeric_id == 1
    drop is_numeric_id
end

********************************************************************************
* PART A: Process CPC Tech Clusters
********************************************************************************
di ">>> Processing CPC Tech Clusters..."
import delimited "$raw/g_cpc_current.tsv", delimiter(tab) clear 
clean_ids

* Tech Factors from your original logic
gen cpc_cluster = 1 if cpc_section=="A"
replace cpc_cluster = 2 if cpc_section=="B"
replace cpc_cluster = 3 if cpc_section=="C"
replace cpc_cluster = 4 if cpc_section=="D"
replace cpc_cluster = 5 if cpc_section=="E"
replace cpc_cluster = 6 if cpc_section=="F"
replace cpc_cluster = 7 if cpc_section=="G"
replace cpc_cluster = 8 if cpc_section=="H"
replace cpc_cluster = 9 if cpc_section=="Y"

label define cpc_cluster 1"Human Necessities" 2"Performing Operations" ///
    3"Chemistry" 4"Textiles" 5"Fixed Cons." 6"Mech. Eng." 7"Physics" ///
    8"Electricity" 9"General Tech"
label values cpc_cluster cpc_cluster

bysort patent_id cpc_sequence: keep if cpc_sequence == 0
sort patent_id
tempfile cpc_temp
save `cpc_temp'

********************************************************************************
* PART B: Process Assignees (HHI Foundation)
********************************************************************************
di ">>> Processing Assignee Data..."
import delimited "$raw/g_assignee_disambiguated.tsv", delimiter(tab) clear
bysort patent_id: keep if _n == 1 
clean_ids
tempfile assignee_temp
save `assignee_temp'

********************************************************************************
* PART C: Citation Counts (Fixed Native-Date Logic)
********************************************************************************
di ">>> Calculating Citation Metrics..."

* 1. Create a lookup of grant dates for ALL focal patents
preserve
    use "$clean/cleaned_renewals_wide.dta", clear
    keep patent_id grant_year  // Just need the year for a 5-year window
    tempfile grant_lookup
    save `grant_lookup'
restore

* 2. Process Citations
import delimited "$raw/g_us_patent_citation.tsv", delimiter(tab) clear
rename (patent_id citation_patent_id) (citing_id patent_id)
clean_ids

* A. Match CITED patent (me) to get my grant year
merge m:1 patent_id using `grant_lookup', keep(match) nogen
rename grant_year my_grant_year

* B. Calculate INCLUSIVE LIFETIME Count
bysort patent_id: gen total_citations_lifetime = _N

* C. Use native citation_date to get the Citing Year
tostring citation_date, replace
gen citing_year = real(substr(citation_date, 1, 4))

* D. Calculate Standardized 5-Year Window
gen cite_age = citing_year - my_grant_year

* Only count if the citation age is within 5 years (inclusive)
gen is_5y = (cite_age >= 0 & cite_age <= 5)
bysort patent_id: egen total_5y_citations = total(is_5y)

keep patent_id total_citations_lifetime total_5y_citations
duplicates drop
tempfile cites_final
save `cites_final'

********************************************************************************
* PART D: Master Merge
********************************************************************************
di ">>> Final Master Merge..."
use "$clean/cleaned_renewals_wide.dta", clear
clean_ids

merge 1:1 patent_id using `cpc_temp', keep(match master) nogen
merge 1:1 patent_id using `assignee_temp', keep(match master) nogen
merge 1:1 patent_id using `cites_final', keep(match master) nogen

foreach v in total_5y_citations total_citations_lifetime {
    replace `v' = 0 if `v' == .
}

count

count if total_citations_lifetime!=0

count if total_5y_citations!=0

save "$clean/master_merged.dta", replace
di ">>> Step 02 Complete. All metrics and tech factors integrated."
log close