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
    
    rename_dict = {'Obs': 'Observations', 'R2': '$R^2$', r'small\_entity': 'Small Entity', r'is\_small': 'Small Entity'}
    if text in rename_dict: return rename_dict[text]
        
    # Standard Map (Incumbents)
    if text.startswith(r'log\_avgq'): return 'Incumbent Average Quality'
    if text.startswith(r'log\_medq'): return 'Incumbent Median Quality'
    if text.startswith(r'log\_flowq'): return 'Incumbent Flow Volume'
    if text.startswith(r'log\_hhi'): return 'Incumbent HHI'
    
    # New Entrant Map
    if text.startswith(r'log\_new\_avgq'): return 'New Entrant Average Quality'
    if text.startswith(r'log\_new\_medq'): return 'New Entrant Median Quality'
    if text.startswith(r'log\_new\_flowq'): return 'New Entrant Flow Volume'
    if text.startswith(r'log\_new\_hhi'): return 'New Entrant HHI'

    # Dyad Map (Incumbents)
    if text.startswith(r'log\_overlap\_count'): return 'Incumbent Overlap Volume'
    if text.startswith(r'log\_clone\_count'): return 'Incumbent Clone Count'
    if text.startswith(r'log\_clone\_avgq'): return 'Incumbent Clone Avg Quality'
    if r'c.log\_clone\_count' in text and '#' in text: return 'Incumbent Clone Count $\\times$ Avg Quality'

    # Dyad Map (New Entrants)
    if text.startswith(r'log\_new\_overlap\_count'): return 'New Entrant Overlap Volume'
    if text.startswith(r'log\_new\_clone\_count'): return 'New Entrant Clone Count'
    if text.startswith(r'log\_new\_clone\_avgq'): return 'New Entrant Clone Avg Quality'
    if r'c.log\_new\_clone\_count' in text and '#' in text: return 'New Entrant Clone Count $\\times$ Avg Quality'
    
    return text

# Map linking the key to a tuple of (Incumbent Variable Label, New Entrant Variable Label)
measure_dict = {
    'AVGQ': ('Incumbent Average Quality', 'New Entrant Average Quality'),
    'MEDQ': ('Incumbent Median Quality', 'New Entrant Median Quality'),
    'FLOWQ': ('Incumbent Flow Volume', 'New Entrant Flow Volume'),
    'HHI': ('Incumbent HHI', 'New Entrant HHI'),
    'OVERLAP': ('Incumbent Overlap Volume', 'New Entrant Overlap Volume'),
    'CLONE_COUNT': ('Incumbent Clone Count', 'New Entrant Clone Count'),
    'CLONE_INT': ('Incumbent Clone Count $\\times$ Avg Quality', 'New Entrant Clone Count $\\times$ Avg Quality')
}

def get_spec_legend():
    return (
        "\\begin{flushleft}\n"
        "\\footnotesize\n"
        "\\textbf{Notes:} Internal quality and Small Entity status are controlled for. Standard errors in parentheses. * $p < 0.1$, ** $p < 0.05$, *** $p < 0.01$. \\\\\n"
        "(1) Tech Level FE, SE clustered by Year \\\\\n"
        f"(2) Year FE, SE clustered by {cluster_desc} \\\\\n"
        f"(3) Tech Level + Year FE, SE clustered by {cluster_desc} \\\\\n"
        "\\vspace{0.2cm}\n"
        "\\textbf{Horse Race Interpretation:} These models pit the \"Incumbent\" (historical active stock) and \"New Entrant\" (recently granted patents) metrics head-to-head in the same specification to isolate the dominant competitive threat to the focal patent's renewal.\n"
        "\\end{flushleft}\n"
    )

def create_pdf(tex_content, output_filename, target_dir):
    template = r"""
    \documentclass{article}
    \usepackage[utf8]{inputenc}
    \usepackage{booktabs}
    \usepackage{geometry}
    \usepackage{caption}
    \usepackage{graphicx}
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

def compile_ultimate_tables():
    if not os.path.exists(results_path): return
    
    for lvl in ['class', 'cluster']:
        all_windows_content = []
        lvl_title = "Class" if lvl == "class" else "Cluster"

        for w in [1, 2, 3]:
            combined_df = pd.DataFrame(columns=["Competition Measure", "(1) Tech FE", "(2) Year FE", "(3) Dual FE"])
            obs_val = ""
            
            for m_key, (inc_label, new_label) in measure_dict.items():
                
                # Dynamic File Paths (dyads don't have _class or _cluster in the filename)
                if m_key in ['OVERLAP', 'CLONE_COUNT', 'CLONE_INT']:
                    base_m = m_key.split('_')[0]
                    file_name = f"reg_horserace_{base_m.lower()}{w}{suffix}.csv"
                else:
                    file_name = f"reg_horserace_{m_key.lower()}{w}_{lvl}{suffix}.csv"
                
                file_path = os.path.join(results_path, file_name)
                
                if os.path.exists(file_path):
                    df = pd.read_csv(file_path)
                    new_headers = [escape_latex(df.columns[0])] + [f"({i})" for i in range(1, len(df.columns))]
                    df.columns = new_headers
                    if hasattr(df, "map"): df = df.fillna("").map(escape_latex)
                    else: df = df.fillna("").applymap(escape_latex)
                        
                    # Find Indices Independently
                    var_idx_inc = df.index[df.iloc[:, 0] == inc_label].tolist()
                    var_idx_new = df.index[df.iloc[:, 0] == new_label].tolist()
                    
                    if var_idx_inc and var_idx_new:
                        idx_inc = var_idx_inc[0]
                        idx_new = var_idx_new[0]
                        
                        # Extract independently (2 rows for coef + SE)
                        subset_inc = df.iloc[idx_inc:idx_inc+2, [0, 6, 7, 8]].copy()
                        subset_new = df.iloc[idx_new:idx_new+2, [0, 6, 7, 8]].copy()
                        
                        subset_inc.iloc[0, 0] = inc_label
                        subset_inc.iloc[1, 0] = ""
                        subset_new.iloc[0, 0] = new_label
                        subset_new.iloc[1, 0] = ""
                        
                        # Concatenate vertically
                        subset = pd.concat([subset_inc, subset_new], ignore_index=True)
                        subset.columns = ["Competition Measure", "(1) Tech FE", "(2) Year FE", "(3) Dual FE"]
                        
                        combined_df = pd.concat([combined_df, subset], ignore_index=True)
                        
                        if obs_val == "":
                            obs_row = df[df.iloc[:, 0] == 'Observations']
                            if not obs_row.empty: obs_val = obs_row.iloc[0, 8]

            if obs_val != "":
                combined_df.loc[len(combined_df)] = [f"Observations ({lvl_title}-Level)", obs_val, obs_val, obs_val]

            styler = combined_df.style.hide(axis='index')
            raw_tabular = styler.to_latex(column_format="l" + "c" * (len(combined_df.columns) - 1), hrules=True)
            
            # FOOTNOTES EMBEDDED INSIDE THE TABLE ENVIRONMENT! NO MORE FLOATING SEPARATION!
            tex_fragment = (
                "\\begin{table}[htbp]\n"
                "\\centering \\footnotesize\n"
                f"\\caption*{{\\Large \\textbf{{Horse Race: Incumbent vs. New Entrant (Window {w}, {lvl_title}-Level)}} \\\\ \\vspace{{0.1cm}} \\normalsize \\textit{{{title_suffix}}}}}\n"
                "\\vspace{0.2cm}\n"
                f"{raw_tabular}\n"
                "\\vspace{0.2cm}\n"
                f"{get_spec_legend()}\n"
                "\\end{table}\n"
            )
            
            all_windows_content.append(tex_fragment + "\n\\newpage\n")

        if all_windows_content:
            final_document = "\n".join(all_windows_content)
            create_pdf(final_document, f"Ultimate_Horserace_Summary_{lvl_title}", ult_output_path)

if __name__ == "__main__":
    compile_ultimate_tables()
