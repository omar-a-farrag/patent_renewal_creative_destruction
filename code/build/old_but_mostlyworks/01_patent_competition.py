import duckdb
import pandas as pd
import time
import os

PROJECT_ROOT = "/if/research-eme/omar/Harun"
OUTPUT_DIR = f"{PROJECT_ROOT}/data/clean"
RAW_DIR = f"{PROJECT_ROOT}/data/raw"

print(">>> 1. Initializing DuckDB Out-Of-Core Engine...")
start_time = time.time()

os.makedirs(f"{OUTPUT_DIR}/duckdb_tmp", exist_ok=True)

con = duckdb.connect(f'{OUTPUT_DIR}/patent_pipeline.db')

# FIX 1: Slash the thread count to stop the 32x RAM multiplier. 
# 10 threads leaves cores free for the OS and drastically cuts RAM usage.
con.execute("PRAGMA threads=1;") 

# FIX 2: The DuckDB Silver Bullet. Disables RAM buffering for INSERT statements.
con.execute("PRAGMA preserve_insertion_order=false;")

# FIX 3: Strict ceiling.
con.execute("PRAGMA memory_limit='45GB';")
con.execute(f"PRAGMA temp_directory='{OUTPUT_DIR}/duckdb_tmp';")


print(">>> 2. Calculating Dynamic Lifespans from Stata CSV...")
con.execute(f"""
    CREATE OR REPLACE TABLE master_metadata AS 
    SELECT 
        patent_id,
        CAST(grant_year AS INT) as birth_year,
        CAST(ren1 AS INT) as ren1, 
        CAST(ren2 AS INT) as ren2, 
        CAST(ren3 AS INT) as ren3, 
        is_small,
        cpc_class, cpc_cluster, 
        CAST(total_5y_citations AS INT) as total_5y_citations,
        CASE 
            WHEN CAST(ren1 AS INT) = 0 THEN CAST(grant_year AS INT) + 4
            WHEN CAST(ren2 AS INT) = 0 THEN CAST(grant_year AS INT) + 8
            WHEN CAST(ren3 AS INT) = 0 THEN CAST(grant_year AS INT) + 12
            ELSE CAST(grant_year AS INT) + 20 
        END as death_year
    FROM read_csv_auto('{OUTPUT_DIR}/master_with_location.csv', header=True)
""")

print(">>> 3. Indexing Foundational Prior Art (Raw TSV)...")
con.execute(f"""
    CREATE OR REPLACE TABLE prior_art AS 
    WITH raw_cites AS (
        SELECT 
            REPLACE(TRIM(patent_id), 'US', '') as raw_patent,
            REPLACE(TRIM(citation_patent_id), 'US', '') as raw_foundation
        FROM read_csv_auto('{RAW_DIR}/g_us_patent_citation.tsv', delim='\t', header=True, all_varchar=true)
    )
    SELECT 
        CASE WHEN raw_patent ~ '^[0-9]+$' THEN LPAD(raw_patent, 8, '0') ELSE raw_patent END as patent_id,
        CASE WHEN raw_foundation ~ '^[0-9]+$' THEN LPAD(raw_foundation, 8, '0') ELSE raw_foundation END as foundation_id
    FROM raw_cites
""")

print(">>> 4. Prepping Windows...")
con.execute("""
    CREATE OR REPLACE TABLE focal_windows AS
    SELECT patent_id, cpc_class, birth_year, 1 as window_id, birth_year as win_start, birth_year + 3 as win_end FROM master_metadata
    UNION ALL
    SELECT patent_id, cpc_class, birth_year, 2 as window_id, birth_year + 4 as win_start, birth_year + 7 as win_end FROM master_metadata
    UNION ALL
    SELECT patent_id, cpc_class, birth_year, 3 as window_id, birth_year + 8 as win_start, birth_year + 11 as win_end FROM master_metadata
""")

# Fetch the unique grant years to build our Python loops
years_df = con.execute("SELECT DISTINCT birth_year FROM master_metadata ORDER BY birth_year").df()
unique_years = years_df['birth_year'].tolist()

# ==============================================================================
# FIX 2: THE OOM-PROOF CHUNKING LOOPS
# ==============================================================================
print(f">>> 5. Calculating Dynamic Active Stock (Chunked across {len(unique_years)} years)...")

# Initialize the empty tables
con.execute("CREATE OR REPLACE TABLE macro_measures (patent_id VARCHAR, window_id INT, raw_flowq DOUBLE, raw_avgq DOUBLE, raw_medq DOUBLE)")
con.execute("CREATE OR REPLACE TABLE overlap_measures (patent_id VARCHAR, window_id INT, raw_overlap_sum DOUBLE, raw_overlap_thresh DOUBLE, raw_clone_quality DOUBLE)")

# Create an index to speed up the loop joins
con.execute("CREATE INDEX idx_master_cpc ON master_metadata(cpc_class)")
con.execute("CREATE INDEX idx_prior_art ON prior_art(patent_id, foundation_id)")

for window in [1, 2, 3]:
    print(f"  --- Processing Window {window} ---")
    for year in unique_years:
        # If year is a float/nan, skip
        if pd.isna(year): continue
        yr = int(year)
        
        # 5A: Macro Measures Loop
        con.execute(f"""
            INSERT INTO macro_measures
            SELECT 
                f.patent_id, f.window_id,
                SUM(1 + COALESCE(r.total_5y_citations, 0)) as raw_flowq,
                AVG(COALESCE(r.total_5y_citations, 0)) as raw_avgq,
                MEDIAN(COALESCE(r.total_5y_citations, 0)) as raw_medq
            FROM focal_windows f
            JOIN master_metadata r 
                ON f.cpc_class = r.cpc_class 
                AND r.patent_id != f.patent_id
                AND r.birth_year <= f.win_end 
                AND r.death_year > f.win_start
            WHERE f.window_id = {window} AND f.birth_year = {yr}
            GROUP BY f.patent_id, f.window_id
        """)
        
        # 5B: Bibliographic Overlap Loop
        con.execute(f"""
            INSERT INTO overlap_measures
            WITH focal_bases AS (
                SELECT p.patent_id, COUNT(p.foundation_id) as base_count
                FROM prior_art p
                JOIN focal_windows fw ON p.patent_id = fw.patent_id
                WHERE fw.window_id = {window} AND fw.birth_year = {yr}
                GROUP BY p.patent_id
            ),
            shared_citations AS (
                SELECT 
                    f.patent_id, f.window_id, r.patent_id as rival_id,
                    COUNT(shared.foundation_id) as shared_count
                FROM focal_windows f
                JOIN master_metadata r 
                    ON r.patent_id != f.patent_id
                    AND r.birth_year <= f.win_end 
                    AND r.death_year > f.win_start
                JOIN prior_art p_focal ON p_focal.patent_id = f.patent_id
                JOIN prior_art shared ON shared.patent_id = r.patent_id 
                    AND p_focal.foundation_id = shared.foundation_id
                WHERE f.window_id = {window} AND f.birth_year = {yr}
                GROUP BY f.patent_id, f.window_id, r.patent_id
            )
            SELECT 
                s.patent_id, s.window_id,
                SUM(s.shared_count) as raw_overlap_sum,
                SUM(CASE WHEN (s.shared_count * 1.0 / b.base_count) >= 0.50 THEN 1 ELSE 0 END) as raw_overlap_thresh,
                AVG(CASE WHEN (s.shared_count * 1.0 / b.base_count) >= 0.50 THEN COALESCE(r.total_5y_citations, 0) ELSE NULL END) as raw_clone_quality
            FROM shared_citations s
            JOIN focal_bases b ON s.patent_id = b.patent_id
            LEFT JOIN master_metadata r ON s.rival_id = r.patent_id
            GROUP BY s.patent_id, s.window_id
        """)

# ==============================================================================
# 6. FINAL ASSEMBLY & EXPORT
# ==============================================================================
print(">>> 6. Assembling Final CSV...")
final_query = """
    SELECT 
        base.patent_id, base.birth_year as grant_year,
        base.ren1, base.ren2, base.ren3, base.is_small,
        base.cpc_class, base.cpc_cluster, base.total_5y_citations,
        
        -- WINDOW 1
        COALESCE(m1.raw_flowq, 0) as flowq1_class,
        COALESCE(m1.raw_avgq, 0) as avgq1_class,
        COALESCE(m1.raw_medq, 0) as medq1_class,
        COALESCE(o1.raw_overlap_sum, 0) as overlap_sum1,
        COALESCE(o1.raw_overlap_thresh, 0) as overlap_thresh1,
        COALESCE(o1.raw_clone_quality, 0) as clone_quality1,
        
        LN(COALESCE(m1.raw_flowq, 0) + SQRT(POWER(COALESCE(m1.raw_flowq, 0), 2) + 1)) as log_flowq1_class,
        LN(COALESCE(m1.raw_avgq, 0) + SQRT(POWER(COALESCE(m1.raw_avgq, 0), 2) + 1)) as log_avgq1_class,
        LN(COALESCE(m1.raw_medq, 0) + SQRT(POWER(COALESCE(m1.raw_medq, 0), 2) + 1)) as log_medq1_class,
        LN(COALESCE(o1.raw_overlap_sum, 0) + SQRT(POWER(COALESCE(o1.raw_overlap_sum, 0), 2) + 1)) as log_overlap_sum1,
        LN(COALESCE(o1.raw_overlap_thresh, 0) + SQRT(POWER(COALESCE(o1.raw_overlap_thresh, 0), 2) + 1)) as log_overlap_thresh1,
        LN(COALESCE(o1.raw_clone_quality, 0) + SQRT(POWER(COALESCE(o1.raw_clone_quality, 0), 2) + 1)) as log_clone_quality1,

        -- WINDOW 2
        COALESCE(m2.raw_flowq, 0) as flowq2_class,
        COALESCE(m2.raw_avgq, 0) as avgq2_class,
        COALESCE(m2.raw_medq, 0) as medq2_class,
        COALESCE(o2.raw_overlap_sum, 0) as overlap_sum2,
        COALESCE(o2.raw_overlap_thresh, 0) as overlap_thresh2,
        COALESCE(o2.raw_clone_quality, 0) as clone_quality2,

        LN(COALESCE(m2.raw_flowq, 0) + SQRT(POWER(COALESCE(m2.raw_flowq, 0), 2) + 1)) as log_flowq2_class,
        LN(COALESCE(m2.raw_avgq, 0) + SQRT(POWER(COALESCE(m2.raw_avgq, 0), 2) + 1)) as log_avgq2_class,
        LN(COALESCE(m2.raw_medq, 0) + SQRT(POWER(COALESCE(m2.raw_medq, 0), 2) + 1)) as log_medq2_class,
        LN(COALESCE(o2.raw_overlap_sum, 0) + SQRT(POWER(COALESCE(o2.raw_overlap_sum, 0), 2) + 1)) as log_overlap_sum2,
        LN(COALESCE(o2.raw_overlap_thresh, 0) + SQRT(POWER(COALESCE(o2.raw_overlap_thresh, 0), 2) + 1)) as log_overlap_thresh2,
        LN(COALESCE(o2.raw_clone_quality, 0) + SQRT(POWER(COALESCE(o2.raw_clone_quality, 0), 2) + 1)) as log_clone_quality2,

        -- WINDOW 3
        COALESCE(m3.raw_flowq, 0) as flowq3_class,
        COALESCE(m3.raw_avgq, 0) as avgq3_class,
        COALESCE(m3.raw_medq, 0) as medq3_class,
        COALESCE(o3.raw_overlap_sum, 0) as overlap_sum3,
        COALESCE(o3.raw_overlap_thresh, 0) as overlap_thresh3,
        COALESCE(o3.raw_clone_quality, 0) as clone_quality3,

        LN(COALESCE(m3.raw_flowq, 0) + SQRT(POWER(COALESCE(m3.raw_flowq, 0), 2) + 1)) as log_flowq3_class,
        LN(COALESCE(m3.raw_avgq, 0) + SQRT(POWER(COALESCE(m3.raw_avgq, 0), 2) + 1)) as log_avgq3_class,
        LN(COALESCE(m3.raw_medq, 0) + SQRT(POWER(COALESCE(m3.raw_medq, 0), 2) + 1)) as log_medq3_class,
        LN(COALESCE(o3.raw_overlap_sum, 0) + SQRT(POWER(COALESCE(o3.raw_overlap_sum, 0), 2) + 1)) as log_overlap_sum3,
        LN(COALESCE(o3.raw_overlap_thresh, 0) + SQRT(POWER(COALESCE(o3.raw_overlap_thresh, 0), 2) + 1)) as log_overlap_thresh3,
        LN(COALESCE(o3.raw_clone_quality, 0) + SQRT(POWER(COALESCE(o3.raw_clone_quality, 0), 2) + 1)) as log_clone_quality3

    FROM master_metadata base
    LEFT JOIN macro_measures m1 ON base.patent_id = m1.patent_id AND m1.window_id = 1
    LEFT JOIN overlap_measures o1 ON base.patent_id = o1.patent_id AND o1.window_id = 1
    LEFT JOIN macro_measures m2 ON base.patent_id = m2.patent_id AND m2.window_id = 2
    LEFT JOIN overlap_measures o2 ON base.patent_id = o2.patent_id AND o2.window_id = 2
    LEFT JOIN macro_measures m3 ON base.patent_id = m3.patent_id AND m3.window_id = 3
    LEFT JOIN overlap_measures o3 ON base.patent_id = o3.patent_id AND o3.window_id = 3
"""

final_df = con.execute(final_query).df()
print(f"    -> Successfully joined {len(final_df)} patent records!")

csv_path = f"{OUTPUT_DIR}/master_regression_file.csv"
print(f">>> Saving to: {csv_path}")
final_df.to_csv(csv_path, index=False)

con.close()
print(f">>> Pipeline Complete! Total time: {round((time.time() - start_time)/60, 2)} minutes.")
