********************************************************************************
/* Script 01: Cleaning Maintenance Fee Data
   Logic: Robust ID cleaning and patent-level collapse for 1:1 merging.
*/
********************************************************************************
clear all
cls
* 0. Adjust current directory as needed in order to run intilization script
cd "Z:/research-eme/omar/Harun/code"

do "00_initialize.do" "01_clean_renewals"

* 1. Import Data (Headerless space-delimited text) [cite: 228]
import delimited "$raw/MaintFeeEvents_20250317.txt", delimiter(" ") varnames(nonames) clear
rename (v1 v2 v3 v4 v5 v6 v7) (patent_id app_number small_entity filing_date grant_date maint_fee_date maint_fee_code)
drop v8-v12
duplicates drop 

* 2. Standardize Small Entity for Regressions [cite: 228]
replace small_entity = cond(small_entity=="Y", "1", cond(small_entity=="N", "0", ""))
destring small_entity, replace
gen is_small = (small_entity == 1)

* 3. Identify Renewals [cite: 228, 229]
sort patent_id maint_fee_date
foreach w in first second third {
    gen is_`w' = 0
}

local c1 "F170 F173 F273 M1551 M170 M173 M183 M2551 M273 M283 M3351"
local c2 "F171 F174 F274 M1552 M171 M174 M184 M2552 M274 M284 M3352 M1555 M181 M2555 M281"
local c3 "F172 F175 F275 M1553 M172 M175 M185 M2553 M275 M285 M3553 M1556 M182 M2556 M282"

foreach i in 1 2 3 {
    foreach c of local c`i' {
        local v = cond(`i'==1,"first",cond(`i'==2,"second","third"))
        replace is_`v' = 1 if maint_fee_code == "`c'"
    }
}

* 4. Missing Aggregation Logic (Calculate num_renewal)
* First, flag any event that is a renewal
gen is_any_renewal = (is_first == 1 | is_second == 1 | is_third == 1)


* Create final indicators (1 if the patent ever had this renewal)
bysort patent_id: egen ren1 = max(is_first)
bysort patent_id: egen ren2 = max(is_second)
bysort patent_id: egen ren3 = max(is_third)

* New Logic: Counts unique windows paid (max 3)
gen num_renewal = ren1 + ren2 + ren3

* 5. Bulletproof ID Cleaning (Fixes the ID format for Step 2 matches) 
tostring patent_id, replace
replace patent_id = trim(itrim(patent_id))
replace patent_id = subinstr(patent_id, "US", "", .)
replace patent_id = subinstr(patent_id, " ", "", .)

* Standardize: pad numeric IDs to 8 digits (e.g., "7608083" becomes "07608083")
gen is_numeric = real(patent_id) != .
replace patent_id = string(real(patent_id), "%08.0f") if is_numeric == 1
drop is_numeric

* 6. Date Formatting and Collapse
tostring grant_date, replace
gen g_date_cleaned = date(grant_date, "YMD")
gen grant_year = year(g_date_cleaned)
format g_date_cleaned %tdCCYY-NN-DD

* --- ELIGIBILITY LOGIC ---
* Calculate patent age as of the data date (March 17, 2025)
gen data_date = td(17mar2025)
gen patent_age = (data_date - g_date_cleaned) / 365.25

* Mark renewals as missing (.) if the patent hasn't reached the window yet
replace ren1 = . if patent_age < 4
replace ren2 = . if patent_age < 8
replace ren3 = . if patent_age < 12

* FIX: Recalculate num_renewal for eligible patents only
* We use 'rowtotal' because it treats missing values as 0, then we restrict
egen num_renewal_new = rowtotal(ren1 ren2 ren3)
replace num_renewal = num_renewal_new if ren1 != .
drop num_renewal_new
* -------------------------

* Collapse to exactly 1 row per patent for 1:1 merging in Step 2
bysort patent_id: keep if _n == 1

* Final Dataset Cleaning 
tab num_renewal
drop if num_renewal > 3
count

save "$clean/cleaned_renewals_wide.dta", replace
di ">>> Step 1 Complete. Patent IDs cleaned and num_renewal calculated."
log close

/* 
As of 2026-02-26
. count
  7,810,993

. tab num_renewal

num_renewal |      Freq.     Percent        Cum.
------------+-----------------------------------
          0 |  2,068,209       26.48       26.48
          1 |  2,253,632       28.85       55.33
          2 |  1,651,367       21.14       76.47
          3 |  1,837,785       23.53      100.00
------------+-----------------------------------
      Total |  7,810,993      100.00

      Total |  7,810,993      100.00
*/