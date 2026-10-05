import pandas as pd
import os
import subprocess
from collections import defaultdict

# Paths as per your latest script setup
results_path = "/if/research-eme/omar/Harun/output/baseline_regressions/csvs"
output_path = "/if/research-eme/omar/Harun/output/baseline_regressions/tables"

individual_base_path = os.path.join(output_path, "individual_tables")
aggregated_base_path = os.path.join(output_path, "aggregated_tables")

def escape_latex(text):
    """Cleans Stata formatting, escapes LaTeX, and polishes variable names."""
    if not isinstance(text, str):
        text = str(text)
        
    # 1. Strip Stata's Excel-proofing (="...") and raw quotes
    text = text.replace('="', '').replace('"', '')
    if text.startswith('='):
        text = text[1:]
        
    # 2. Escape common LaTeX characters
    text = text.replace('_', r'\_').replace('%', r'\%').replace('&', r'\&')
    
    # 3. Rename variables to look like a Top Journal
    rename_dict = {
        r'log\_internal\_quality': 'Log Internal Quality',
        r'is\_small': 'Small Entity',
        r'\_cons': 'Constant',
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

def get_spec_legend(measure_type):
    """Returns the footnote explaining the 8 specifications and measure construction."""
    descriptions = {
        'AVGQ': r"Log Average Quality is defined as the Inverse Hyperbolic Sine (IHS) of the mean 5-year forward citations received by all patents granted within the focal patent's technology grouping (class or cluster) during the respective 4-year rolling window.",
        'MEDQ': r"Log Median Quality is defined as the Inverse Hyperbolic Sine (IHS) of the median 5-year forward citations received by all patents granted within the focal patent's technology grouping (class or cluster) during the respective 4-year rolling window.",
        'FLOWQ': r"Log Flow Volume is defined as the Inverse Hyperbolic Sine (IHS) of the citation-weighted sum of all new patents entering the focal patent's technology grouping during the respective 4-year rolling window. Each rival patent is weighted by (1 + \text{5-year forward citations}).",
        'HHI': r"Log HHI is defined as the Inverse Hyperbolic Sine (IHS) of the Herfindahl-Hirschman Index of assignee patenting shares within the focal patent's technology grouping during the respective 4-year rolling window.",
        'OVERLAP': r"Log Bibliographic Overlap is defined as the Inverse Hyperbolic Sine (IHS) of the total number of times the focal patent's foundational prior art (backward citations) is cited by new competitor patents granted during the respective 4-year rolling window. This captures the intensity of targeted technological displacement."
    }
    
    measure_desc = descriptions.get(measure_type, "")

    # Inject the specific description into the LaTeX footnote
    return r"""
    \begin{flushleft}
    \footnotesize
    \textbf{Notes:} Internal quality (5-year standardized citations) is controlled for in all specifications. 
    Standard errors are reported in parentheses. Significance levels: * $p < 0.1$, ** $p < 0.05$, *** $p < 0.01$. \\
    (1) OLS + controls \\
    (2) OLS + controls, robust SEs \\
    (3) Tech Level FE, robust SEs \\
    (4) Year FE, robust SEs \\
    (5) Tech Level + Year FE, robust SEs \\
    (6) Tech Level FE, SE clustered by Year \\
    (7) Year FE, SE clustered by Tech Level \\
    (8) Tech Level + Year FE, SE clustered by Tech Level \\
    \vspace{0.2cm}
    \textbf{Variable Construction:} %s
    \end{flushleft}
    """ % measure_desc

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
        rel_dir = os.path.relpath(target_dir, output_path)
        print(f"Successfully compiled {output_filename}.pdf in {rel_dir}/")
    except subprocess.CalledProcessError as e:
        error_msg = e.stdout.decode() if e.stdout else e.stderr.decode()
        print(f"Error compiling {output_filename}:\n{error_msg[-500:]}")

def process_results():
    measure_groups = defaultdict(list)
    
    if not os.path.exists(results_path):
        print(f"Error: Could not find {results_path}")
        return

    for file in os.listdir(results_path):
        if file.endswith(".csv"):
            df = pd.read_csv(os.path.join(results_path, file))
            
            new_headers = [escape_latex(df.columns[0])]
            for i in range(1, len(df.columns)):
                new_headers.append(f"({i})")
            df.columns = new_headers

            df = df.fillna("")
            if hasattr(df, "map"):
                df = df.map(escape_latex)
            else:
                df = df.applymap(escape_latex)
                
            df = df[~df.iloc[:, 0].isin(['ren1', 'ren2', 'ren3', 'b/se'])]
            
            m_name = file.replace("reg_", "").replace(".csv", "").upper()
            m_name_clean = escape_latex(m_name)
            
            styler = df.style.hide(axis='index')
            raw_tabular = styler.to_latex(
                column_format="l" + "c" * (len(df.columns) - 1),
                hrules=True
            )
            
            tex_fragment = f"""
            \\begin{{table}}[h!]
            \\centering
            \\small
            \\caption{{Impact of {m_name_clean} on Patent Renewal Probability}}
            \\label{{tab:{m_name.lower()}}}
            \\resizebox{{\\textwidth}}{{!}}{{
            {raw_tabular}
            }}
            \\end{{table}}
            """
            
            # Identify the base measure to pass to the legend function (e.g., MEDQ2_CLASS -> MEDQ)
            base_measure = ''.join(c for c in m_name.split('_')[0] if not c.isdigit())
            folder_name = base_measure.lower()
            
            # Pass the base_measure to dynamically fetch the right description
            full_content = tex_fragment + get_spec_legend(base_measure)
            
            target_indiv_dir = os.path.join(individual_base_path, folder_name)
            create_pdf(full_content, f"Table_{m_name}", target_indiv_dir)
            
            measure_groups[base_measure].append(full_content + "\n\\newpage\n")
            
    for measure, contents in measure_groups.items():
        summary_content = "\n".join(contents)
        folder_name = measure.lower()
        target_agg_dir = os.path.join(aggregated_base_path, folder_name)
        create_pdf(summary_content, f"Summary_{measure}_Tables", target_agg_dir)

if __name__ == "__main__":
    process_results()
