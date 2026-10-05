********************************************************************************
/* Script 02: Citations, Clusters, and Assignees
   Logic: Merges technology classes, citation counts, and corporate owners.
*/
********************************************************************************
clear all
cls
* 0. Adjust current directory as needed in order to run intilization script
cd "Z:/research-eme/omar/Harun/code"

do "00_initialize.do" "02_citations_clusters_assignees"

* 1. Process CPC Tech Clusters
import delimited "$raw/g_cpc_current.tsv", delimiter(tab) clear
keep if cpc_sequence == 0 // Keep primary classification
gen cpc_cluster = cond(cpc_section=="A", 1, cond(cpc_section=="B", 2, cond(cpc_section=="C", 3, ///
                  cond(cpc_section=="D", 4, cond(cpc_section=="E", 5, cond(cpc_section=="F", 6, ///
                  cond(cpc_section=="G", 7, cond(cpc_section=="H", 8, 9))))))))
tempfile cpc_temp
save `cpc_temp'

* 2. Process Assignees (The New HHI Foundation)
import delimited "$raw/g_assignee_disambiguated.tsv", delimiter(tab) clear
* Standard rule: keep primary assignee to ensure shares sum to 100% per class
bysort patent_id: keep if _n == 1 
tempfile assignee_temp
save `assignee_temp'

* 3. Process Citations
import delimited "$raw/g_us_patent_citation.tsv", delimiter(tab) clear
* Calculate total citations received by the patent (Forward Citations)
bysort cited_patent_id: gen total_citations = _N
keep cited_patent_id total_citations
duplicates drop
rename cited_patent_id patent_id
tempfile cites_temp
save `cites_temp'

* 4. Master Merge
use "$clean/cleaned_data_step1B_wide.dta", clear
merge 1:1 patent_id using `cpc_temp', keep(match master) nogen
merge 1:1 patent_id using `assignee_temp', keep(match master) nogen
merge 1:1 patent_id using `cites_temp', keep(match master) nogen

* Final clean
replace total_citations = 0 if total_citations == .
save "$clean/cleaned_master_with_assignees.dta", replace

di ">>> Step 2 Complete. Master file contains Assignee IDs for HHI calculation."
log close