********************************************************************************
/* Script 03: Patent Country of Origin
   Logic: Identifies the geographic origin of each patent using disambiguated location data.
*/
********************************************************************************
clear all
cls
* 0. Adjust current directory as needed in order to run intilization script

cd "/if/research-eme/omar/Harun/code"

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

********************************************************************************
** Check if we merged the data properly
use "$clean/master_with_location.dta", clear

* 1. The Ultimate Test: Is the dataset still exactly 1 row per patent?
* (If this line errors out, we have accidental duplicates!)
isid patent_id

* 2. Did the variables survive the merges? Let's count missing values.
di ">>> Missing Value Check:"
count if missing(death_year)
count if missing(cpc_class)
count if missing(total_5y_citations)

* 3. Let's look at the actual data
list patent_id grant_year death_year cpc_class total_5y_citations in 1/15
********************************************************************************
/*
. * 1. The Ultimate Test: Is the dataset still exactly 1 row per patent?

. * (If this line errors out, we have accidental duplicates!)

. isid patent_id

. 
. * 2. Did the variables survive the merges? Let's count missing values.

. di ">>> Missing Value Check:"
>>> Missing Value Check:

. count if missing(death_year)
  0

. count if missing(cpc_class)
  16,335

. count if missing(total_5y_citations)
  0

. 
. * 3. Let's look at the actual data

. list patent_id grant_year death_year cpc_class total_5y_citations in 1/15

     +-----------------------------------------------------------+
     |     patent_id   grant_~r   death_~r   cpc_cl~s   total_~s |
     |-----------------------------------------------------------|
  1. | 0000000T12345       2007       2011                     0 |
  2. | 0000000T21340       2007       2011                     0 |
  3. | 0000000T21342       2005       2009                     0 |
  4. | 000000H000634       1989       1993                     0 |
  5. | 000000H000773       1990       1994                     0 |
     |-----------------------------------------------------------|
  6. | 000000H001531       1996       2000                     0 |
  7. | 000000H001805       1999       2003                     0 |
  8. | 000000H001816       1999       2003                     0 |
  9. | 000000H001904       2000       2004                     0 |
 10. | 000000H001922       2000       2004                     0 |
     |-----------------------------------------------------------|
 11. | 000000H001949       2001       2005                     0 |
 12. | 000000H001953       2001       2005                     0 |
 13. | 000000H001960       2001       2005                     0 |
 14. | 000000H001965       2001       2005                     0 |
 15. | 000000H001975       2001       2005                     0 |
     +-----------------------------------------------------------+
*/

save "$clean/master_with_location.dta", replace
di ">>> Step 03 Complete. Locations merged."
log close
