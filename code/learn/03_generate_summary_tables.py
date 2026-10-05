import pandas as pd
import os
import subprocess

# ==============================================================================
# CLUSTERING CONFIGURATION
# Set to match your Stata run:
# 1 = Tech Level
# 2 = Two-Way (Tech Level AND Grant Year)
# 3 = Assignee Level (assignee_id)
CLUSTER_MODE = 3

# FIRM SIZE ROBUSTNESS TOGGLE
# "p90" = Baseline, "p75" = Quartile Robustness
SIZE_MODE = "p90" 
size_suffix = "" if SIZE_MODE == "p90" else "_p75"
# ==============================================================================

if CLUSTER_MODE == 1:
    suffix = ""
    out_folder = "tech_level_cluster"
    title_suffix = "Clustered by Tech Level"
    cluster_desc = "Tech Level"
    cluster_rationale = r"\textbf{Standard Error Clustering:} Standard errors in Models (2) and (3) are clustered at the technology level to account for serial correlation of unobserved shocks within specific technology groupings over time."
elif CLUSTER_MODE == 2:
    suffix = "_twoway"
    out_folder = "twoway_cluster"
    title_suffix = "Two-Way Clustered (Tech & Year)"
    cluster_desc = "Tech Level and Year (Two-Way)"
    cluster_rationale = r"\textbf{Standard Error Clustering:} Standard errors in Models (2) and (3) are two-way clustered by technology level and grant year to simultaneously account for serial correlation within technology groupings over time and cross-sectional spatial correlation across classes in a given year."
elif CLUSTER_MODE == 3:
    suffix = "_assignee"
    out_folder = "assignee_cluster"
    title_suffix = "Clustered by Assignee"
    cluster_desc = "Assignee"
    cluster_rationale = r"\textbf{Standard Error Clustering:} Standard errors in Models (2) and (3) are clustered at the assignee level to account for correlated internal firm-level dynamics, such as annual IP budget shocks, that affect all patents owned by the same firm simultaneously."

# Paths dynamically route based on clustering mode
results_path = "/if/research-eme/omar/Harun/output/baseline_regressions/csvs"
output_path = f"/if/research-eme/omar/Harun/output/baseline_regressions/tables/active_incumbents/{out_folder}/ultimate_summary"

def escape_latex(text):
    if not isinstance(text, str):
        text = str(text)
    text = text.replace('="', '').replace('"', '')
    if text.startswith('='):
        text = text[1:]
    text = text.replace('_', r'\_').replace('%', r'\%').replace('&', r'\&')
    
    rename_dict = {
        r'log\_internal\_quality': 'Log Internal Quality',
        r'small\_entity': 'Small Entity',
        r'is\_big\_p90': 'Top Decile Firm ($>90$th)',
        r'is\_big\_p75': 'Top Quartile Firm ($>75$th)',
        r'\_cons': 'Constant',
        'Obs': 'Observations',
        'R2': '$R^2$'
    }
    if text in rename_dict: return rename_dict[text]
        
    if 'clone\_count' in text and 'clone\_avgq' in text: return r'Clone Count $\times$ Clone Quality'
    if 'log\_clone\_count' in text: return 'Log Clone Count'
    if 'log\_clone\_avgq' in text: return 'Log Clone Quality'
    
    if text.startswith(r'log\_avgq'): return 'Log Average Quality'
    if text.startswith(r'log\_medq'): return 'Log Median Quality'
    if text.startswith(r'log\_flowq'): return 'Log Flow Volume'
    if text.startswith(r'log\_hhi'): return 'Log HHI'
    if text.startswith(r'log\_overlap'): return 'Log Bibliographic Overlap'
    
    return text

measure_dict = {
    'AVGQ': 'Log Average Quality',
    'MEDQ': 'Log Median Quality',
    'FLOWQ': 'Log Flow Volume',
    'HHI': 'Log HHI',
    'OVERLAP': 'Log Bibliographic Overlap',
    'CLONE': 'Log Clone Count' # Used as the anchor to find the interaction block
}

def get_spec_legend():
    return f"""
    \\begin{{flushleft}}
    \\footnotesize
    \\textbf{{Notes:}} Internal quality (5-year standardized citations), Small Entity status, and firm size indicators are controlled for in all specifications but omitted for brevity. 
    Standard errors are reported in parentheses. Significance levels: * $p < 0.1$, ** $p < 0.05$, *** $p < 0.01$. \\\\
    (1) Tech Level FE, SE clustered by Year (Model 6)\\\\
    (2) Year FE, SE clustered by {cluster_desc} (Model 7)\\\\
    (3) Tech Level + Year FE, SE clustered by {cluster_desc} (Model 8)\\\\
    \\vspace{{0.2cm}}
    {cluster_rationale} \\\\
    \\vspace{{0.2cm}}
    \\textbf{{Variable Construction (4-Year Rolling Windows):}} \\\\
    \\textbf{{Average / Median Quality:}} IHS of the mean/median 5-year forward citations received by all patents granted within the focal patent's technology grouping. \\\\
    \\textbf{{Flow Volume:}} IHS of the citation-weighted sum of all new patents entering the grouping. \\\\
    \\textbf{{HHI:}} IHS of the Herfindahl-Hirschman Index of assignee patenting shares within the grouping. \\\\
    \\textbf{{Bibliographic Overlap:}} IHS of the total number of times the focal patent's foundational prior art is cited by new competitor patents. \\\\
    \\textbf{{50\\% Clones (Interaction):}} IHS of the count of direct clone competitors, IHS of their average quality, and their interaction.
    \\end{{flushleft}}
    """

def create_pdf(tex_content, output_filename, target_dir):
    template = r"""
    \documentclass{article}
    \usepackage[utf8]{inputenc}
    \usepackage{booktabs}
    \usepackage{geometry}
    \usepackage{caption}
    \usepackage{graphicx}
    \usepackage{amsmath}
    \geometry{letterpaper, margin=0.5in, landscape}
    \begin{document}
    \centering
    %CONTENT%
    \end{document}
    """
    final_tex = template.replace('%CONTENT%', tex_content)
    
    if not os.path.exists(target_dir):
        os.makedirs(target_dir)
        
    tex_file = os.path.join(target_dir, f"{output_filename}.tex")
    with open(tex_file, "w") as f:
        f.write(final_tex)
    
    try:
        subprocess.run(
            ["pdflatex", "-interaction=nonstopmode", "-output-directory", target_dir, tex_file],
            check=True, capture_output=True
        )
        print(f"Successfully compiled {output_filename}.pdf in tables/{out_folder}/ultimate_summary/")
    except subprocess.CalledProcessError as e:
        error_msg = e.stdout.decode() if e.stdout else e.stderr.decode()
        if "Fatal" in error_msg or "Error" in error_msg or "!" in error_msg:
            print(f"Error compiling {output_filename}:\n{error_msg[-500:]}")
        else:
            print(f"Successfully compiled {output_filename}.pdf in tables/{out_folder}/ultimate_summary/")

def compile_ultimate_tables():
    if not os.path.exists(results_path): return

    for lvl in ['class', 'cluster']:
        all_windows_content = []
        lvl_title = "Class" if lvl == "class" else "Cluster"

        for w in [1, 2, 3]:
            combined_df = pd.DataFrame(columns=["Competition Measure", "(1) Tech FE", "(2) Year FE", "(3) Dual FE"])
            obs_val = ""
            
            for m_key, m_label in measure_dict.items():
                if m_key in ['OVERLAP', 'CLONE']:
                    file_name = f"reg_{m_key.lower()}{w}{suffix}{size_suffix}.csv"
                else:
                    file_name = f"reg_{m_key.lower()}{w}_{lvl}{suffix}{size_suffix}.csv"
                    
                file_path = os.path.join(results_path, file_name)
                
                if os.path.exists(file_path):
                    df = pd.read_csv(file_path)
                    
                    new_headers = [escape_latex(df.columns[0])]
                    for i in range(1, len(df.columns)):
                        new_headers.append(f"({i})")
                    df.columns = new_headers
                    
                    df = df.fillna("")
                    if hasattr(df, "map"): df = df.map(escape_latex)
                    else: df = df.applymap(escape_latex)
                        
                    var_idx = df.index[df.iloc[:, 0] == m_label].tolist()
                    
                    if var_idx:
                        idx = var_idx[0]
                        if m_key == 'CLONE':
                            subset = df.iloc[idx:idx+6, [0, 6, 7, 8]].copy()
                            subset.iloc[1, 0] = ""
                            subset.iloc[3, 0] = ""
                            subset.iloc[5, 0] = ""
                        else:
                            subset = df.iloc[idx:idx+2, [0, 6, 7, 8]].copy()
                            subset.iloc[0, 0] = m_label
                            subset.iloc[1, 0] = ""
                            
                        subset.columns = ["Competition Measure", "(1) Tech FE", "(2) Year FE", "(3) Dual FE"]
                        combined_df = pd.concat([combined_df, subset], ignore_index=True)
                        
                        if obs_val == "":
                            obs_row = df[df.iloc[:, 0] == 'Observations']
                            if not obs_row.empty:
                                obs_val = obs_row.iloc[0, 8]

            if obs_val != "":
                combined_df.loc[len(combined_df)] = [f"Observations ({lvl_title}-Level)", obs_val, obs_val, obs_val]

            styler = combined_df.style.hide(axis='index')
            raw_tabular = styler.to_latex(
                column_format="l" + "c" * (len(combined_df.columns) - 1),
                hrules=True
            )
            
            tex_fragment = f"""
            \\begin{{table}}[h!]
            \\centering
            \\small
            \\caption*{{\\Large \\textbf{{Active Stock's Effects on Patent Renewal Probability (Window {w}, {lvl_title}-Level)}} \\\\ \\vspace{{0.1cm}} \\normalsize \\textit{{{title_suffix}}}}}
            \\vspace{{0.2cm}}
            \\label{{tab:ultimate_w{w}_{lvl}}}
            \\resizebox{{0.95\\textwidth}}{{!}}{{
            {raw_tabular}
            }}
            \\end{{table}}
            """
            
            all_windows_content.append(tex_fragment + get_spec_legend() + "\n\\newpage\n")

        if all_windows_content:
            final_document = "\n".join(all_windows_content)
            create_pdf(final_document, f"Ultimate_Unified_Competition_Summary_{lvl_title}", output_path)

if __name__ == "__main__":
    compile_ultimate_tables()