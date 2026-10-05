********************************************************************************
/* Script 01: Cleaning Maintenance Fee Data
   Logic: Identifies renewal events and counts total renewals per patent.
*/
********************************************************************************
clear all
cls
* 0. Adjust current directory as needed in order to run intilization script
cd "Z:/research-eme/omar/Harun/code"

* 1. Initialize and Log
do "00_initialize.do" "01_clean_renewals"

* 2. Import Data (Using the dynamic $raw path)
import delimited "$raw/MaintFeeEvents_20250317.txt", delimiter(space) clear

rename (v1 v2 v3 v4 v5 v6 v7) (patent_id app_number small_entity filing_date grant_date maint_fee_date maint_fee_code)
drop v8-v12
duplicates drop 

* 3. Identify Renewals [cite: 497-504]
sort patent_id maint_fee_date
gen is_first  = inlist(maint_fee_code, "F170", "F173", "F273", "M1551", "M170", "M173", "M183", "M2551", "M273", "M283", "M3351")
gen is_second = inlist(maint_fee_code, "F171", "F174", "F274", "M1552", "M171", "M174", "M184", "M2552", "M274", "M284", "M3352", "M1555", "M181", "M2555", "M281")
gen is_third  = inlist(maint_fee_code, "F172", "F175", "F275", "M1553", "M172", "M175", "M185", "M2553", "M275", "M285", "M3553", "M1556", "M182", "M2556", "M282")

* 4. Aggregate [cite: 527-539, 646-652]
gen is_renewal = (is_first + is_second + is_third) > 0
bysort patent_id is_first is_second is_third: keep if _n == 1 | is_renewal == 0
bysort patent_id: egen num_renewal = total(is_renewal)
bysort patent_id: gen act_seq = _n

replace patent_id = substr(patent_id, 6, 13) 
save "$clean/cleaned_renewals_long.dta", replace

keep if act_seq == 1
save "$clean/cleaned_renewals_wide.dta", replace

di ">>> Step 1 Complete."
log close
