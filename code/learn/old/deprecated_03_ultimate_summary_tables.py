import pandas as pd
import os
import subprocess

# Paths
results_path = "/if/research-eme/omar/Harun/output/baseline_regressions/csvs"
output_path = "/if/research-eme/omar/Harun/output/baseline_regressions/tables/ultimate_summary"

def escape_latex(text):
    """Strips Stata's Excel-proofing and escapes LaTeX special characters."""
    if not isinstance(text, str):
        text = str(text)
    text = text.replace('="', '').replace('"', '')
    if text.startswith('='):
        text = text[1:]
    text = text.replace('_', r'\_').replace('%', r'\%').replace('&', r'\&')
    
    # Standardize basic variables
    rename_dict = {
        'Obs': 'Observations',
        'R2': '$R^2$'
    }
    if text in rename_dict:
        return rename_dict[text]
        
    # Rename the dynamic competition measures cleanly
    if text.startswith(r'log\_avgq'): return 'Log Average Quality'
    if text.startswith(r'log\_medq'): return 'Log Median Quality'
    if text.startswith(r'log\_flowq'): return 'Log Flow Volume'
    if text.startswith(r'log\_hhi'): return 'Log HHI'
    if text.startswith(r'log\_overlap'): return 'Log Bibliographic Overlap'
    
    return text

# The exact order and naming for the unified rows
measure_dict = {
    'AVGQ': 'Log Average Quality',
    'MEDQ': 'Log Median Quality',
    'FLOWQ': 'Log Flow Volume',
    'HHI': 'Log HHI',
    'OVERLAP': 'Log Bibliographic Overlap'
}

def get_spec_legend():
    """Returns the unified footnote explaining all measures and the 3 chosen specifications."""
    return r"""
    \begin{flushleft}
    \footnotesize
    \textbf{Notes:} Internal quality (5-year standardized citations) and Small Entity status are controlled for in all specifications but omitted for brevity. 
    Standard errors are reported in parentheses. Significance levels: * $p < 0.1$, ** $p < 0.05$, *** $p < 0.01$. \\
    (1) Tech Level FE, SE clustered by Year (Model 6)\\
    (2) Year FE, SE clustered by Tech Level (Model 7)\\
    (3) Tech Level + Year FE, SE clustered by Tech Level (Model 8)\\
    \vspace{0.2cm}
    \textbf{Variable Construction (4-Year Rolling Windows):} \\
    \textbf{Average / Median Quality:} Inverse Hyperbolic Sine (IHS) of the mean/median 5-year forward citations received by all patents granted within the focal patent's technology grouping. \\
    \textbf{Flow Volume:} IHS of the citation-weighted sum of all new patents entering the focal patent's technology grouping. Each rival is weighted by (1 + \text{5-year forward citations}). \\
    \textbf{HHI:} IHS of the Herfindahl-Hirschman Index of assignee patenting shares within the focal patent's technology grouping. \\
    \textbf{Bibliographic Overlap:} IHS of the total number of times the focal patent's foundational prior art (backward citations) is cited by new competitor patents.
    \end{flushleft}
    """

def create_pdf(tex_content, output_filename, target_dir):
    """Wraps LaTeX content in a standalone document and compiles to PDF."""
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
        rel_dir = os.path.relpath(target_dir, os.path.dirname(target_dir))
        print(f"Successfully compiled {output_filename}.pdf in {rel_dir}/")
    except subprocess.CalledProcessError as e:
        error_msg = e.stdout.decode() if e.stdout else e.stderr.decode()
        print(f"Error compiling {output_filename}:\n{error_msg[-500:]}")

def compile_ultimate_tables():
    if not os.path.exists(results_path):
        print(f"Error: Could not find {results_path}")
        return

    # Generate two PDFs: One for Class-level, one for Cluster-level
    for lvl in ['class', 'cluster']:
        all_windows_content = []
        lvl_title = "Class" if lvl == "class" else "Cluster"

        for w in [1, 2, 3]:
            combined_df = pd.DataFrame(columns=["Competition Measure", "(1) Tech FE", "(2) Year FE", "(3) Dual FE"])
            obs_val = ""
            
            for m_key, m_label in measure_dict.items():
                if m_key == 'OVERLAP':
                    file_name = f"reg_overlap{w}_class.csv"
                else:
                    file_name = f"reg_{m_key.lower()}{w}_{lvl}.csv"
                    
                file_path = os.path.join(results_path, file_name)
                
                if os.path.exists(file_path):
                    df = pd.read_csv(file_path)
                    
                    # Clean Headers
                    new_headers = [escape_latex(df.columns[0])]
                    for i in range(1, len(df.columns)):
                        new_headers.append(f"({i})")
                    df.columns = new_headers
                    
                    # Clean Data
                    df = df.fillna("")
                    if hasattr(df, "map"):
                        df = df.map(escape_latex)
                    else:
                        df = df.applymap(escape_latex)
                        
                    # ---> THE BULLETPROOF FIX <---
                    # Instead of deleting junk, actively hunt for the row that matches our metric name
                    var_idx = df.index[df.iloc[:, 0] == m_label].tolist()
                    
                    if var_idx:
                        idx = var_idx[0]
                        # Grab the target row AND the standard error row below it (idx to idx+2)
                        subset = df.iloc[idx:idx+2, [0, 6, 7, 8]].copy()
                    else:
                        # Fallback just in case (assuming standard esttab structure)
                        subset = df.iloc[2:4, [0, 6, 7, 8]].copy()
                    
                    # Relabel for the unified table
                    subset.iloc[0, 0] = m_label
                    subset.iloc[1, 0] = ""
                    subset.columns = ["Competition Measure", "(1) Tech FE", "(2) Year FE", "(3) Dual FE"]
                    
                    combined_df = pd.concat([combined_df, subset], ignore_index=True)
                    
                    # Grab the Observations count to append at the bottom
                    if obs_val == "":
                        obs_row = df[df.iloc[:, 0] == 'Observations']
                        if not obs_row.empty:
                            obs_val = obs_row.iloc[0, 8]

            # Add the Observations row at the bottom
            if obs_val != "":
                combined_df.loc[len(combined_df)] = [f"Observations ({lvl_title}-Level)", obs_val, obs_val, obs_val]

            # Convert to LaTeX
            styler = combined_df.style.hide(axis='index')
            raw_tabular = styler.to_latex(
                column_format="l" + "c" * (len(combined_df.columns) - 1),
                hrules=True
            )
            
            # Build the Table Fragment with ENLARGED Title
            tex_fragment = f"""
            \\begin{{table}}[h!]
            \\centering
            \\small
            \\caption*{{\\Large \\textbf{{Unified Competition Effects on Patent Renewal Probability (Window {w}, {lvl_title}-Level)}}}}
            \\vspace{{0.2cm}}
            \\label{{tab:ultimate_w{w}_{lvl}}}
            \\resizebox{{0.95\\textwidth}}{{!}}{{
            {raw_tabular}
            }}
            \\end{{table}}
            """
            
            all_windows_content.append(tex_fragment + get_spec_legend() + "\n\\newpage\n")

        # Compile the final multi-page PDF for this Tech Level
        if all_windows_content:
            final_document = "\n".join(all_windows_content)
            create_pdf(final_document, f"Ultimate_Unified_Competition_Summary_{lvl_title}", output_path)
        else:
            print(f"No data found to compile for {lvl_title}-level.")

if __name__ == "__main__":
    compile_ultimate_tables()
