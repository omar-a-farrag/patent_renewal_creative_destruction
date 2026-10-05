/*
Repair missing grant_year / birth_year introduced by Script 05 assembly.
Base Stata only. Does not rebuild or change competition measures.

Usage (after defining $clean in your usual initialization):
do "repair_patent_regression_years.do" ///
   "$clean/master_regression_file.dta" ///
   "$clean/master_regression_file_repaired.dta"

Alternatively pass two absolute file paths. Output must be a NEW filename.
After success, point regression scripts to the repaired file and rerun them.

PERMANENT FIX in BOTH 05_new_bibliographic_overlap.do and
05b_new_entrant_clones.do: immediately after
    append using "$clean/temp_zero_cites.dta"
retain only the key and the newly calculated measures before merging:
    Script 05:  keep patent_id clone_count* clone_avgq* overlap_count*
    Script 05b: keep patent_id new_clone_count* new_clone_avgq* new_overlap_count*
These keep statements REPLACE drop focal_base_count (and, in 05b,
capture drop grant_year). After each final merge, add:
    assert !missing(grant_year, birth_year)

Why: collapsed chunks contain no dates. Appending zero-citation rows
introduces date columns missing for the chunk rows. Default merge keeps
these master-side missing values. Stata's year cutoff then drops them.
*/
********************************************************************************
clear all
cls

cd "/if/research-eme/omar/Harun/code"
do "00_initialize.do" "repair_patent_regression_years"

local input_file  "$clean/master_regression_file.dta"
local output_file "$clean/master_regression_file_repaired.dta"

confirm file "`input_file'"
confirm new file "`output_file'"
use "`input_file'", clear

isid patent_id
display as text "Missing grant years BEFORE repair:"
count if missing(grant_year)
summarize clone_count1 overlap_count1 if !missing(grant_year)

* The uploaded source has string grant_date and a numeric Stata daily date.
confirm string variable grant_date
confirm numeric variable g_date_cleaned
tempvar year_from_string year_from_date
generate int `year_from_string' = year(date(trim(grant_date), "YMD"))
generate int `year_from_date' = year(g_date_cleaned)
assert !missing(`year_from_string', `year_from_date')
assert `year_from_string' == `year_from_date'
assert grant_year == `year_from_date' if !missing(grant_year)
assert birth_year == `year_from_date' if !missing(birth_year)

replace grant_year = `year_from_date' if missing(grant_year)
replace birth_year = `year_from_date' if missing(birth_year)
assert !missing(grant_year, birth_year)
assert grant_year == birth_year
drop `year_from_string' `year_from_date'

* Check that the existing transformations match IHS; do not change them.
foreach w in 1 2 3 {
    foreach stem in clone_count clone_avgq overlap_count new_clone_count new_clone_avgq new_overlap_count {
        assert !missing(`stem'`w', log_`stem'`w')
        assert `stem'`w' >= 0
        assert abs(log_`stem'`w' - asinh(`stem'`w')) < 0.00001
    }
}

* Run the simplest horse race as a diagnostic before saving.
* No fixed effects or clustering: this checks restoration of variation.
preserve
    assert !missing(grant_year)
    drop if grant_year > 2021
    tempvar own_quality
    generate double `own_quality' = asinh(total_5y_citations)
    regress ren1 c.log_clone_count1##c.log_clone_avgq1 ///
        c.log_new_clone_count1##c.log_new_clone_avgq1 ///
        `own_quality' small_entity is_big_p90
    foreach v in log_clone_count1 log_clone_avgq1 log_new_clone_count1 log_new_clone_avgq1 {
        summarize `v' if e(sample)
        assert r(N) > 1 & r(sd) > 0 & r(sd) < .
    }
    if e(rank) != 10 {
        display as error "Unexpected rank: inspect the diagnostic regression before proceeding."
        exit 459
    }
restore

save `"`output_file'"'
display as result "Repair saved. Point all regression scripts to this output and rerun."
display as text "Other research-design critiques are separate from this repair."
