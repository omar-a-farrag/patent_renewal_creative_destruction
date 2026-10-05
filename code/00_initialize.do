********************************************************************************
/* Master Initialization Script
   Updates: User-dependent paths, 5% Sample Flag, and Dynamic Logging
   Omar Farrag and Harun Alp
   Created on: 2026-02-23
   Last Edited: 
*/
********************************************************************************
clear all
set more off

* --- USER SELECTION ---
local user = 2 // 1 = windows, 2 = linux
global use_sample = 0 // 1 = Use 5% Sample for debugging; 0 = Use Full Data

* --- PATH DEFINITIONS (User-Dependent) ---
if `user' == 1 {
    global project_root "REPLACE WITH YOUR PATH"
}
else if `user' == 2 {
    global project_root "REPLACE WITH YOUR PATH" 
}

* --- DIRECTORY HIERARCHY ---
global data     "$project_root/data"
global raw_full "$data/raw"
global sample   "$data/sample"
global clean    "$data/clean"
global for_regs "$data/for_regs"

global code     "$project_root/code"
global build    "$code/build"
global logs     "$build/logs"
global output   "$project_root/output"

* Redirect $raw based on the sample flag
global raw = cond($use_sample == 1, "$sample", "$raw_full")

* Ensure directories exist
foreach dir in "$sample" "$clean" "$for_regs" "$logs" "$output" {
    capture mkdir "`dir'"
}

* --- DYNAMIC LOGGING SETUP ---
* This logic captures the calling file name passed as an argument
args calling_file
if "`calling_file'" != "" {
    capture log close
    local c_date = subinstr("`c(current_date)'", " ", "_", .)
    log using "$logs/`calling_file'_`c_date'.log", replace
}

di ">>> Initialization Complete. User `user' | Sample Flag: $use_sample"
di ">>> Raw data path: $raw"
