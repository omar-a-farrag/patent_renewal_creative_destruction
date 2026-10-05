********************************************************************************
/* Script 03: Patent Country of Origin
   Logic: Identifies the geographic origin of each patent using disambiguated location data.
*/
********************************************************************************
clear all
cls
* 0. Adjust current directory as needed in order to run intilization script

cd "Z:/research-eme/omar/Harun/code"

do "00_initialize.do" "03_patent_location"

* --- Sub-routine: Uniform ID Cleaning ---
capture program drop clean_ids
program define clean_ids
    tostring patent_id, replace
    replace patent_id = trim(itrim(patent_id))
    replace patent_id = subinstr(patent_id, "US", "", .)
    replace patent_id = subinstr(patent_id, " ", "", .)
    gen is_num = real(patent_id) != .
    replace patent_id = string(real(patent_id), "%08.0f") if is_num == 1
    drop is_num
end

* 1. Process Locations
import delimited "$raw/g_location_disambiguated.tsv", delimiter(tab) clear
keep location_id disambig_country
tempfile loc_temp
save `loc_temp'

* 2. Process Inventors (Primary)
import delimited "$raw/g_inventor_disambiguated.tsv", delimiter(tab) clear
keep if inventor_sequence == 0
keep patent_id location_id
clean_ids // The critical fix for high match rates
merge m:1 location_id using `loc_temp', keep(match master) nogen
tempfile inventor_loc
save `inventor_loc'

* 3. Merge with Master Merge (Output of Script 02)
use "$clean/master_merged.dta", clear
clean_ids
merge 1:1 patent_id using `inventor_loc', keep(match master) nogen

* Handle missing locations for foreign/domestic regressions
gen is_us = (disambig_country == "US")
replace is_us = 0 if is_us == .

save "$clean/master_with_location.dta", replace
di ">>> Step 03 Complete. Locations merged."
log close
