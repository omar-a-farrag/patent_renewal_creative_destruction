import duckdb
import pandas as pd
import time
import os

# ==============================================================================
# 0. INITIALIZATION & PATHS
# ==============================================================================
# --- USER FLAGS ---
USE_SAMPLE = 0  # <--- Set to 0! Run the whole thing!
PROJECT_ROOT = "/if/research-eme/omar/Harun"

if USE_SAMPLE == 1:
    RAW_DIR = f"{PROJECT_ROOT}/data/sample"
    print(">>> RUNNING IN DEBUG MODE: Using 5% Sample Data")
else:
    RAW_DIR = f"{PROJECT_ROOT}/data/raw"
    print(">>> RUNNING FULL DATASET: Using 100% Raw Data")

OUTPUT_DIR = f"{PROJECT_ROOT}/data/clean"

print(">>> Initializing DuckDB Engine...")
con = duckdb.connect(f'{OUTPUT_DIR}/patent_pipeline.db')
con.execute("PRAGMA threads=32;") 
con.execute("PRAGMA memory_limit='128GB';")

start_time = time.time()

# ==============================================================================
# 1. BASE LAYER: LIFESPANS, CITATIONS & RENEWALS
# ==============================================================================
print(">>> Reading MaintFeeEvents via Pandas (Collapsing Whitespace)...")
# FIX 1: Updated to sep='\s+' to silence the Pandas deprecation warning
maint_df = pd.read_csv(
    f'{RAW_DIR}/MaintFeeEvents_20250317.txt',
    sep='\s+',
    header=None,
    names=['patent_id', 'app_number', 'small_entity', 'filing_date', 'grant_date', 'maint_fee_date', 'maint_fee_code'],
    dtype=str,
    on_bad_lines='skip'
)
con.register('raw_renewals_pandas', maint_df)

print(">>> Building Base Universe & Lifespans...")
con.execute(f"""
    CREATE OR REPLACE TABLE base_patents AS 
    WITH raw_renewals AS (
        SELECT 
            REPLACE(TRIM(patent_id), 'US', '') as raw_id,
            CAST(SUBSTRING(grant_date, 1, 4) AS INT) as grant_year,
            small_entity,
            -- Placeholder for your actual renewal codes
            1 as ren1, 1 as ren2, 0 as ren3 
        FROM raw_renewals_pandas
        WHERE patent_id IS NOT NULL AND grant_date IS NOT NULL
    )
    SELECT 
        -- Stata %08.0f Emulator: Add leading zeros to numeric IDs
        CASE WHEN raw_id ~ '^[0-9]+$' THEN LPAD(raw_id, 8, '0') ELSE raw_id END as patent_id,
        grant_year as birth_year,
        MAX(small_entity) as small_entity,
        MAX(ren1) as ren1, 
        MAX(ren2) as ren2, 
        MAX(ren3) as ren3,
        CASE 
            WHEN MAX(ren1) = 0 THEN grant_year + 4
            WHEN MAX(ren2) = 0 THEN grant_year + 8
            WHEN MAX(ren3) = 0 THEN grant_year + 12
            ELSE grant_year + 20 
        END as death_year
    FROM raw_renewals
    GROUP BY raw_id, grant_year
""")

print(">>> Linking Technology Classes...")
con.execute(f"""
    CREATE OR REPLACE TABLE cpc_data AS 
    WITH ranked_cpc AS (
        SELECT 
            REPLACE(TRIM(patent_id), 'US', '') as raw_id,
            SUBSTRING(cpc_group, 1, 4) as cpc_class,
            SUBSTRING(cpc_group, 1, 3) as cpc_cluster,
            ROW_NUMBER() OVER(PARTITION BY patent_id ORDER BY cpc_sequence ASC) as rn
        -- FIX 2: all_varchar=true prevents strict-typing crashes
        FROM read_csv_auto('{RAW_DIR}/g_cpc_current.tsv', delim='\t', header=True, all_varchar=true)
    )
    SELECT 
        CASE WHEN raw_id ~ '^[0-9]+$' THEN LPAD(raw_id, 8, '0') ELSE raw_id END as patent_id,
        cpc_class, cpc_cluster 
    FROM ranked_cpc WHERE rn = 1
""")

print(">>> Calculating 5-Year Citation Quality...")
con.execute(f"""
    CREATE OR REPLACE TABLE citations_5y AS 
    WITH raw_cites AS (
        SELECT 
            REPLACE(TRIM(patent_id), 'US', '') as raw_focal,
            REPLACE(TRIM(citation_patent_id), 'US', '') as raw_citing
        FROM read_csv_auto('{RAW_DIR}/g_us_patent_citation.tsv', delim='\t', header=True, all_varchar=true)
    )
    SELECT 
        CASE WHEN c.raw_focal ~ '^[0-9]+$' THEN LPAD(c.raw_focal, 8, '0') ELSE c.raw_focal END as focal_id,
        COUNT(c.raw_citing) as total_5y_citations
    FROM raw_cites c
    JOIN base_patents focal_dates 
        ON (CASE WHEN c.raw_focal ~ '^[0-9]+$' THEN LPAD(c.raw_focal, 8, '0') ELSE c.raw_focal END) = focal_dates.patent_id
    JOIN base_patents citing_dates 
        ON (CASE WHEN c.raw_citing ~ '^[0-9]+$' THEN LPAD(c.raw_citing, 8, '0') ELSE c.raw_citing END) = citing_dates.patent_id
    WHERE (citing_dates.birth_year - focal_dates.birth_year) BETWEEN 0 AND 5
    GROUP BY c.raw_focal
""")

print(">>> Assembling Master Metadata...")
con.execute(f"""
    CREATE OR REPLACE TABLE master_metadata AS 
    SELECT 
        b.patent_id, b.birth_year, b.death_year, b.small_entity,
        b.ren1, b.ren2, b.ren3, c.cpc_class, c.cpc_cluster
    FROM base_patents b
    JOIN cpc_data c ON b.patent_id = c.patent_id
""")

print(">>> Indexing Foundational Prior Art...")
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

# ==============================================================================
# 2. MACRO COMPETITION LAYER: ACTIVE STOCK
# ==============================================================================
print(">>> Calculating Dynamic Active Stock Measures (AVGQ, FLOWQ, MEDQ)...")

con.execute("""
    CREATE OR REPLACE TABLE focal_windows AS
    SELECT patent_id, cpc_class, birth_year, 1 as window_id, birth_year as win_start, birth_year + 3 as win_end FROM master_metadata
    UNION ALL
    SELECT patent_id, cpc_class, birth_year, 2 as window_id, birth_year + 4 as win_start, birth_year + 7 as win_end FROM master_metadata
    UNION ALL
    SELECT patent_id, cpc_class, birth_year, 3 as window_id, birth_year + 8 as win_start, birth_year + 11 as win_end FROM master_metadata
""")

con.execute("""
    CREATE OR REPLACE TABLE macro_measures AS 
    SELECT 
        f.patent_id,
        f.window_id,
        SUM(1 + COALESCE(r_cite.total_5y_citations, 0)) as raw_flowq,
        AVG(COALESCE(r_cite.total_5y_citations, 0)) as raw_avgq,
        MEDIAN(COALESCE(r_cite.total_5y_citations, 0)) as raw_medq
    FROM focal_windows f
    JOIN master_metadata r 
        ON f.cpc_class = r.cpc_class 
        AND r.patent_id != f.patent_id
        AND r.birth_year <= f.win_end 
        AND r.death_year > f.win_start
    LEFT JOIN citations_5y r_cite ON r.patent_id = r_cite.focal_id
    GROUP BY f.patent_id, f.window_id
""")

# ==============================================================================
# 3. MICRO OVERLAP LAYER: THE CLONE ARMY
# ==============================================================================
print(">>> Calculating Bibliographic Overlap and Clone Quality...")

con.execute("""
    CREATE OR REPLACE TABLE overlap_measures AS 
    WITH focal_bases AS (
        SELECT patent_id, COUNT(foundation_id) as base_count
        FROM prior_art GROUP BY patent_id
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
        GROUP BY f.patent_id, f.window_id, r.patent_id
    )
    SELECT 
        s.patent_id,
        s.window_id,
        SUM(s.shared_count) as raw_overlap_sum,
        SUM(CASE WHEN (s.shared_count * 1.0 / b.base_count) >= 0.50 THEN 1 ELSE 0 END) as raw_overlap_thresh,
        AVG(CASE WHEN (s.shared_count * 1.0 / b.base_count) >= 0.50 THEN COALESCE(r_cite.total_5y_citations, 0) ELSE NULL END) as raw_clone_quality
    FROM shared_citations s
    JOIN focal_bases b ON s.patent_id = b.patent_id
    LEFT JOIN citations_5y r_cite ON s.rival_id = r_cite.focal_id
    GROUP BY s.patent_id, s.window_id
""")

# ==============================================================================
# 4. FINAL ASSEMBLY & EXPORT
# ==============================================================================
print(">>> Assembling Master Regression File...")
os.makedirs(OUTPUT_DIR, exist_ok=True)

final_query = """
    SELECT 
        base.patent_id, base.birth_year as grant_year,
        base.ren1, base.ren2, base.ren3, base.small_entity as is_small,
        base.cpc_class, base.cpc_cluster,
        COALESCE(c5y.total_5y_citations, 0) as total_5y_citations,
        
        -- WINDOW 1: RAW MEASURES
        COALESCE(m1.raw_flowq, 0) as flowq1_class,
        COALESCE(m1.raw_avgq, 0) as avgq1_class,
        COALESCE(m1.raw_medq, 0) as medq1_class,
        COALESCE(o1.raw_overlap_sum, 0) as overlap_sum1,
        COALESCE(o1.raw_overlap_thresh, 0) as overlap_thresh1,
        COALESCE(o1.raw_clone_quality, 0) as clone_quality1,
        
        -- WINDOW 1: IHS TRANSFORMS (For Regressions)
        LN(COALESCE(m1.raw_flowq, 0) + SQRT(POWER(COALESCE(m1.raw_flowq, 0), 2) + 1)) as log_flowq1_class,
        LN(COALESCE(m1.raw_avgq, 0) + SQRT(POWER(COALESCE(m1.raw_avgq, 0), 2) + 1)) as log_avgq1_class,
        LN(COALESCE(m1.raw_medq, 0) + SQRT(POWER(COALESCE(m1.raw_medq, 0), 2) + 1)) as log_medq1_class,
        LN(COALESCE(o1.raw_overlap_sum, 0) + SQRT(POWER(COALESCE(o1.raw_overlap_sum, 0), 2) + 1)) as log_overlap_sum1,
        LN(COALESCE(o1.raw_overlap_thresh, 0) + SQRT(POWER(COALESCE(o1.raw_overlap_thresh, 0), 2) + 1)) as log_overlap_thresh1,
        LN(COALESCE(o1.raw_clone_quality, 0) + SQRT(POWER(COALESCE(o1.raw_clone_quality, 0), 2) + 1)) as log_clone_quality1,

        -- WINDOW 2: RAW MEASURES
        COALESCE(m2.raw_flowq, 0) as flowq2_class,
        COALESCE(m2.raw_avgq, 0) as avgq2_class,
        COALESCE(m2.raw_medq, 0) as medq2_class,
        COALESCE(o2.raw_overlap_sum, 0) as overlap_sum2,
        COALESCE(o2.raw_overlap_thresh, 0) as overlap_thresh2,
        COALESCE(o2.raw_clone_quality, 0) as clone_quality2,

        -- WINDOW 2: IHS TRANSFORMS
        LN(COALESCE(m2.raw_flowq, 0) + SQRT(POWER(COALESCE(m2.raw_flowq, 0), 2) + 1)) as log_flowq2_class,
        LN(COALESCE(m2.raw_avgq, 0) + SQRT(POWER(COALESCE(m2.raw_avgq, 0), 2) + 1)) as log_avgq2_class,
        LN(COALESCE(m2.raw_medq, 0) + SQRT(POWER(COALESCE(m2.raw_medq, 0), 2) + 1)) as log_medq2_class,
        LN(COALESCE(o2.raw_overlap_sum, 0) + SQRT(POWER(COALESCE(o2.raw_overlap_sum, 0), 2) + 1)) as log_overlap_sum2,
        LN(COALESCE(o2.raw_overlap_thresh, 0) + SQRT(POWER(COALESCE(o2.raw_overlap_thresh, 0), 2) + 1)) as log_overlap_thresh2,
        LN(COALESCE(o2.raw_clone_quality, 0) + SQRT(POWER(COALESCE(o2.raw_clone_quality, 0), 2) + 1)) as log_clone_quality2,

        -- WINDOW 3: RAW MEASURES
        COALESCE(m3.raw_flowq, 0) as flowq3_class,
        COALESCE(m3.raw_avgq, 0) as avgq3_class,
        COALESCE(m3.raw_medq, 0) as medq3_class,
        COALESCE(o3.raw_overlap_sum, 0) as overlap_sum3,
        COALESCE(o3.raw_overlap_thresh, 0) as overlap_thresh3,
        COALESCE(o3.raw_clone_quality, 0) as clone_quality3,

        -- WINDOW 3: IHS TRANSFORMS
        LN(COALESCE(m3.raw_flowq, 0) + SQRT(POWER(COALESCE(m3.raw_flowq, 0), 2) + 1)) as log_flowq3_class,
        LN(COALESCE(m3.raw_avgq, 0) + SQRT(POWER(COALESCE(m3.raw_avgq, 0), 2) + 1)) as log_avgq3_class,
        LN(COALESCE(m3.raw_medq, 0) + SQRT(POWER(COALESCE(m3.raw_medq, 0), 2) + 1)) as log_medq3_class,
        LN(COALESCE(o3.raw_overlap_sum, 0) + SQRT(POWER(COALESCE(o3.raw_overlap_sum, 0), 2) + 1)) as log_overlap_sum3,
        LN(COALESCE(o3.raw_overlap_thresh, 0) + SQRT(POWER(COALESCE(o3.raw_overlap_thresh, 0), 2) + 1)) as log_overlap_thresh3,
        LN(COALESCE(o3.raw_clone_quality, 0) + SQRT(POWER(COALESCE(o3.raw_clone_quality, 0), 2) + 1)) as log_clone_quality3

    FROM master_metadata base
    LEFT JOIN citations_5y c5y ON base.patent_id = c5y.focal_id
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
