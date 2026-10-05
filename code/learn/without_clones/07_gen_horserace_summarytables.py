import pandas as pd
import os
import subprocess
from collections import defaultdict

# ==============================================================================
# CLUSTERING CONFIGURATION
CLUSTER_MODE = 3
# ==============================================================================

if CLUSTER_MODE == 1:
    suffix = ""
    out_folder = "tech_level_cluster"
    title_suffix = "Clustered by Tech Level"
    cluster_desc = "Tech Level"
    cluster_rationale = r"\textbf{Standard Error Clustering:} Standard errors in Models (2) and (3) are clustered at the technology level."
elif CLUSTER_MODE == 2:
    suffix = "_twoway"
    out_folder = "twoway_cluster"
    title_suffix = "Two-Way Clustered (Tech & Year)"
    cluster_desc = "Tech Level and Year (Two-Way)"
    cluster_rationale = r"\textbf{Standard Error Clustering:} Standard errors in Models (2) and (3) are two-way clustered by technology level and grant year."
elif CLUSTER_MODE == 3:
    suffix = "_assignee"
    out_folder = "assignee_cluster"
    title_suffix = "Clustered by Assignee"
    cluster_desc = "Assignee"
    cluster_rationale = r"\textbf{Standard Error Clustering:} Standard errors in Models (2) and (3) are clustered at the assignee level."

results_path = "/if/research-eme/omar/Harun/output/baseline_regressions/csvs"
agg_output_path = f"/if/research-eme/omar/Harun/output/baseline_regressions/tables/horserace/{out_folder}/aggregated_tables"
ult_output_path = f"/if/research-eme/omar/Harun/output/baseline_regressions/tables/horserace/{out_folder}/ultimate_summary"

def escape_latex(text):
    if not isinstance(text, str): text = str(text)
    text = text.replace('="', '').replace('"', '')
    if text.startswith('='): text = text[1:]
    text = text.replace('_', r'\_').replace('%', r'\%').replace('&', r'\&')
    
    rename_dict = {'Obs': 'Observations', 'R2': '$R^2$'}
    if text in rename_dict: return rename_dict[text]
        
    # Standard Map
    if text.startswith(r'log\_avgq'): return 'Incumbent Average Quality'
    if text.startswith(r'log\_medq'): return 'Incumbent Median Quality'
    if text.startswith(r'log\_flowq'): return 'Incumbent Flow Volume'
    if text.startswith(r'log\_hhi'): return 'Incumbent HHI'
    
    # New Entrant Map
    if text.startswith(r'log\_new\_avgq'): return 'New Entrant Average Quality'
    if text.startswith(r'log\_new\_medq'): return 'New Entrant Median Quality'
    if text.startswith(r'log\_new\_flowq'): return 'New Entrant Flow Volume'
    if text.startswith(r'log\_new\_hhi'): return 'New Entrant HHI'
    
    return text

measure_dict = {
    'AVGQ': ('Incumbent Average Quality', 'New Entrant Average Quality'),
    'MEDQ': ('Incumbent Median Quality', 'New Entrant Median Quality'),
    'FLOWQ': ('Incumbent Flow Volume', 'New Entrant Flow Volume'),
    'HHI': ('Incumbent HHI', 'New Entrant HHI')
}

def get_spec_legend(is_ultimate=False):
    if is_ultimate:
        models = r"""
        (1) Tech Level FE, SE clustered by Year \\
        (2) Year FE, SE clustered by {cluster_desc} \\
        (3) Tech Level + Year FE, SE clustered by {cluster_desc} \\
        """
    else:
        models = r"(1-8) Specification details follow previous formatting, closing with Two-Way Fixed Effects and Assignee-level standard errors in Model (8). \\"
        
    return f"""
    \\begin{{flushleft}}
    \\footnotesize
    \\textbf{{Notes:}} Internal quality and Small Entity status are controlled for. Standard errors in parentheses. * $p < 0.1$, ** $p < 0.05$, *** $p < 0.01$. \\\\
    {models.format(cluster_desc=cluster_desc)}
    \\vspace{{0.2cm}}
    \\textbf{{Horse Race Interpretation:}} These models pit the "Incumbent" (historical active stock) and "New Entrant" (recently granted patents) metrics head-to-head in the same specification to isolate the dominant competitive threat to the focal patent's renewal.
    \\end{{flushleft}}
    """

def create_pdf(tex_content, output_filename, target_dir):
    template = r"""
    \documentclass{article}
    \usepackage[utf8]{inputenc}
    \usepackage{booktabs}
    \usepackage{geometry}
    \usepackage{caption}
    \geometry{letterpaper, margin=0.5in, landscape}
    \begin{document}
    \centering
    %CONTENT%
    \end{document}
    """
    final_tex = template.replace('%CONTENT%', tex_content)
    if not os.path.exists(target_dir): os.makedirs(target_dir)
    tex_file = os.path.join(target_dir, f"{output_filename}.tex")
    with open(tex_file, "w") as f: f.write(final_tex)
    try:
        subprocess.run(["pdflatex", "-interaction=nonstopmode", "-output-directory", target_dir, tex_file], check=True, capture_output=True)
        print(f"Compiled {output_filename}.pdf")
    except: pass

def compile_all_summaries():
    if not os.path.exists(results_path): return
    
    measure_groups = defaultdict(list)

    # 1. GENERATE AGGREGATED TABLES (All 8 Models, stacked by Measure)
    for file in sorted(os.listdir(results_path)):
        if file.startswith("reg_horserace_") and file.endswith(f"{suffix}.csv"):
            df = pd.read_csv(os.path.join(results_path, file))
            new_headers = [escape_latex(df.columns[0])] + [f"({i})" for i in range(1, len(df.columns))]
            df.columns = new_headers
            df = df.fillna("").map(escape_latex)
            df = df[~df.iloc[:, 0].isin(['ren1', 'ren2', 'ren3', 'b/se'])]
            
            m_name_raw = file.replace("reg_horserace_", "").replace(".csv", "").upper()
            if suffix: m_name_raw = m_name_raw.replace(suffix.upper(), "")
            m_name_clean = escape_latex(m_name_raw)
            
            styler = df.style.hide(axis='index')
            raw_tabular = styler.to_latex(column_format="l" + "c" * (len(df.columns) - 1), hrules=True)
            
            tex_fragment = f"""
            \\begin{{table}}[h!]
            \\centering \\small
            \\caption*{{\\Large \\textbf{{Incumbents vs. New Entrants: {m_name_clean}}} \\\\ \\vspace{{0.1cm}} \\normalsize \\textit{{{title_suffix}}}}}
            \\vspace{{0.2cm}}
            \\resizebox{{\\textwidth}}{{!}}{{{raw_tabular}}}
            \\end{{table}}
            """
            
            base_measure = ''.join(c for c in m_name_raw.split('_')[0] if not c.isdigit())
            measure_groups[base_measure].append(tex_fragment + get_spec_legend(is_ultimate=False) + "\n\\newpage\n")
            
    for measure, contents in measure_groups.items():
        summary_content = "\n".join(contents)
        create_pdf(summary_content, f"Aggregated_{measure}_Tables", os.path.join(agg_output_path, measure.lower()))

    # 2. GENERATE ULTIMATE SUMMARY TABLES (Models 6, 7, 8 only, stacked head-to-head)
    for lvl in ['class', 'cluster']:
        all_windows_content = []
        lvl_title = "Class" if lvl == "class" else "Cluster"

        for w in [1, 2, 3]:
            combined_df = pd.DataFrame(columns=["Competition Measure", "(1) Tech FE", "(2) Year FE", "(3) Dual FE"])
            obs_val = ""
            
            for m_key, (inc_label, new_label) in measure_dict.items():
                file_name = f"reg_horserace_{m_key.lower()}{w}_{lvl}{suffix}.csv"
                file_path = os.path.join(results_path, file_name)
                
                if os.path.exists(file_path):
                    df = pd.read_csv(file_path)
                    new_headers = [escape_latex(df.columns[0])] + [f"({i})" for i in range(1, len(df.columns))]
                    df.columns = new_headers
                    df = df.fillna("").map(escape_latex)
                        
                    var_idx = df.index[df.iloc[:, 0] == inc_label].tolist()
                    if var_idx:
                        idx = var_idx[0]
                        # Pull 4 rows to capture both the Incumbent and New Entrant coefs + SEs
                        subset = df.iloc[idx:idx+4, [0, 6, 7, 8]].copy()
                        subset.iloc[0, 0] = inc_label
                        subset.iloc[1, 0] = ""
                        subset.iloc[2, 0] = new_label
                        subset.iloc[3, 0] = ""
                        subset.columns = ["Competition Measure", "(1) Tech FE", "(2) Year FE", "(3) Dual FE"]
                        combined_df = pd.concat([combined_df, subset], ignore_index=True)
                        
                        if obs_val == "":
                            obs_row = df[df.iloc[:, 0] == 'Observations']
                            if not obs_row.empty: obs_val = obs_row.iloc[0, 8]

            if obs_val != "":
                combined_df.loc[len(combined_df)] = [f"Observations ({lvl_title}-Level)", obs_val, obs_val, obs_val]

            styler = combined_df.style.hide(axis='index')
            raw_tabular = styler.to_latex(column_format="l" + "c" * (len(combined_df.columns) - 1), hrules=True)
            
            tex_fragment = f"""
            \\begin{{table}}[h!]
            \\centering \\small
            \\caption*{{\\Large \\textbf{{Horse Race: Incumbent vs. New Entrant (Window {w}, {lvl_title}-Level)}} \\\\ \\vspace{{0.1cm}} \\normalsize \\textit{{{title_suffix}}}}}
            \\vspace{{0.2cm}}
            \\resizebox{{0.95\\textwidth}}{{!}}{{{raw_tabular}}}
            \\end{{table}}
            """
            all_windows_content.append(tex_fragment + get_spec_legend(is_ultimate=True) + "\n\\newpage\n")

        if all_windows_content:
            final_document = "\n".join(all_windows_content)
            create_pdf(final_document, f"Ultimate_Horserace_Summary_{lvl_title}", ult_output_path)

if __name__ == "__main__":
    compile_all_summaries()