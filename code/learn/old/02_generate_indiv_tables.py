import pandas as pd
import os
import subprocess
from collections import defaultdict

# ==============================================================================
# CLUSTERING CONFIGURATION
# Set to match your Stata run:
# 1 = Tech Level
# 2 = Two-Way (Tech Level AND Grant Year)
# 3 = Assignee Level (assignee_id)
CLUSTER_MODE = 3
# ==============================================================================

if CLUSTER_MODE == 1:
    suffix = ""
    out_folder = "tech_level_cluster"
    title_suffix = "Clustered by Tech Level"
    cluster_desc = "Tech Level"
    cluster_rationale = r"\textbf{Standard Error Clustering:} Standard errors in Models (7) and (8) are clustered at the technology level to account for serial correlation of unobserved shocks within specific technology groupings over time."
elif CLUSTER_MODE == 2:
    suffix = "_twoway"
    out_folder = "twoway_cluster"
    title_suffix = "Two-Way Clustered (Tech & Year)"
    cluster_desc = "Tech Level and Year (Two-Way)"
    cluster_rationale = r"\textbf{Standard Error Clustering:} Standard errors in Models (7) and (8) are two-way clustered by technology level and grant year to simultaneously account for serial correlation within technology groupings over time and cross-sectional spatial correlation across classes in a given year."
elif CLUSTER_MODE == 3:
    suffix = "_assignee"
    out_folder = "assignee_cluster"
    title_suffix = "Clustered by Assignee"
    cluster_desc = "Assignee"
    cluster_rationale = r"\textbf{Standard Error Clustering:} Standard errors in Models (7) and (8) are clustered at the assignee level to account for correlated internal firm-level dynamics, such as annual IP budget shocks, that affect all patents owned by the same firm simultaneously."

# Paths dynamically route based on clustering mode
results_path = "/if/research-eme/omar/Harun/output/baseline_regressions/csvs"
output_path = f"/if/research-eme/omar/Harun/output/baseline_regressions/tables/active_incumbents/{out_folder}"

individual_base_path = os.path.join(output_path, "individual_tables")
aggregated_base_path = os.path.join(output_path, "aggregated_tables")

def escape_latex(text):
    if not isinstance(text, str):
        text = str(text)
    text = text.replace('="', '').replace('"', '')
    if text.startswith('='):
        text = text[1:]
    text = text.replace('_', r'\_').replace('%', r'\%').replace('&', r'\&')
    
    rename_dict = {
        r'log\_internal\_quality': 'Log Internal Quality',
        r'is\_small': 'Small Entity',
        r'\_cons': 'Constant',
        'Obs': 'Observations',
        'R2': '$R^2$'
    }
    if text in rename_dict: return rename_dict[text]
        
    # Process the new clone variables and their interaction
    if 'clone\_count' in text and 'clone\_avgq' in text: return r'Clone Count $\times$ Clone Quality'
    if 'log\_clone\_count' in text: return 'Log Clone Count'
    if 'log\_clone\_avgq' in text: return 'Log Clone Quality'
    
    if text.startswith(r'log\_avgq'): return 'Log Average Quality'
    if text.startswith(r'log\_medq'): return 'Log Median Quality'
    if text.startswith(r'log\_flowq'): return 'Log Flow Volume'
    if text.startswith(r'log\_hhi'): return 'Log HHI'
    if text.startswith(r'log\_overlap'): return 'Log Bibliographic Overlap'
    
    return text

def get_spec_legend(measure_type):
    descriptions = {
        'AVGQ': r"Log Average Quality is defined as the Inverse Hyperbolic Sine (IHS) of the mean 5-year forward citations received by all patents granted within the focal patent's technology grouping (class or cluster) during the respective 4-year rolling window.",
        'MEDQ': r"Log Median Quality is defined as the Inverse Hyperbolic Sine (IHS) of the median 5-year forward citations received by all patents granted within the focal patent's technology grouping (class or cluster) during the respective 4-year rolling window.",
        'FLOWQ': r"Log Flow Volume is defined as the Inverse Hyperbolic Sine (IHS) of the citation-weighted sum of all new patents entering the focal patent's technology grouping during the respective 4-year rolling window. Each rival patent is weighted by $(1 + \text{5-Year Citations})$.",
        'HHI': r"Log HHI is defined as the Inverse Hyperbolic Sine (IHS) of the Herfindahl-Hirschman Index of assignee patenting shares within the focal patent's technology grouping during the respective 4-year rolling window.",
        'OVERLAP': r"Log Bibliographic Overlap is defined as the Inverse Hyperbolic Sine (IHS) of the total number of times the focal patent's foundational prior art (backward citations) is cited by new competitor patents granted during the respective 4-year rolling window. This captures the intensity of targeted technological displacement.",
        'CLONE': r"Log Clone Count represents the discrete number of direct competitors (patents sharing $\ge 50\%$ of the focal patent's backward citations). Log Clone Quality is the average citation-weighted quality of those specific clones. The interaction term isolates the specific penalty of facing a high volume of highly-cited direct substitutes."
    }
    
    measure_desc = descriptions.get(measure_type, "")

    return f"""
    \\begin{{flushleft}}
    \\footnotesize
    \\textbf{{Notes:}} Internal quality (5-year standardized citations) is controlled for in all specifications. 
    Standard errors are reported in parentheses. Significance levels: * $p < 0.1$, ** $p < 0.05$, *** $p < 0.01$. \\\\
    (1) OLS + controls \\\\
    (2) OLS + controls, robust SEs \\\\
    (3) Tech Level FE, robust SEs \\\\
    (4) Year FE, robust SEs \\\\
    (5) Tech Level + Year FE, robust SEs \\\\
    (6) Tech Level FE, SE clustered by Year \\\\
    (7) Year FE, SE clustered by {cluster_desc} \\\\
    (8) Tech Level + Year FE, SE clustered by {cluster_desc} \\\\
    \\vspace{{0.2cm}}
    {cluster_rationale} \\\\
    \\vspace{{0.2cm}}
    \\textbf{{Variable Construction:}} {measure_desc}
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
        rel_dir = os.path.relpath(target_dir, output_path)
        print(f"Successfully compiled {output_filename}.pdf in {out_folder}/{rel_dir}/")
    except subprocess.CalledProcessError as e:
        error_msg = e.stdout.decode() if e.stdout else e.stderr.decode()
        if "Fatal" in error_msg or "Error" in error_msg or "!" in error_msg:
            print(f"Error compiling {output_filename}:\n{error_msg[-500:]}")
        else:
            print(f"Successfully compiled {output_filename}.pdf in tables/{out_folder}/ultimate_summary/")

# def is_target_file(f):
#    """Filters CSVs to only process the ones matching the current cluster mode."""
#    if not f.endswith(".csv"): return False
#    if suffix == "":
#        return not (f.endswith("_twoway.csv") or f.endswith("_assignee.csv"))
#    return f.endswith(f"{suffix}.csv")
def is_target_file(f):
    """Filters CSVs to only process Active Incumbent files matching the cluster mode."""
    if not f.endswith(".csv"): return False
    
    # NEW RULE: Explicitly block New Entrant and Horserace CSVs from this script
    if "new_" in f or "horserace_" in f: return False
    
    # Original clustering rule
    if suffix == "":
        return not (f.endswith("_twoway.csv") or f.endswith("_assignee.csv"))
    return f.endswith(f"{suffix}.csv")

def process_results():
    measure_groups = defaultdict(list)
    if not os.path.exists(results_path): return

    for file in os.listdir(results_path):
        if is_target_file(file):
            df = pd.read_csv(os.path.join(results_path, file))
            
            new_headers = [escape_latex(df.columns[0])]
            for i in range(1, len(df.columns)):
                new_headers.append(f"({i})")
            df.columns = new_headers

            df = df.fillna("")
            if hasattr(df, "map"): df = df.map(escape_latex)
            else: df = df.applymap(escape_latex)
                
            df = df[~df.iloc[:, 0].isin(['ren1', 'ren2', 'ren3', 'b/se'])]
            
            # Clean up the filename for the title (remove the suffix if it exists)
            m_name_raw = file.replace("reg_", "").replace(".csv", "").upper()
            if suffix: m_name_raw = m_name_raw.replace(suffix.upper(), "")
            m_name_clean = escape_latex(m_name_raw)
            
            styler = df.style.hide(axis='index')
            raw_tabular = styler.to_latex(
                column_format="l" + "c" * (len(df.columns) - 1),
                hrules=True
            )
            
            tex_fragment = f"""
            \\begin{{table}}[h!]
            \\centering
            \\small
            \\caption*{{\\Large \\textbf{{Active Stock's Impact of {m_name_clean} on Patent Renewal Probability}} \\\\ \\vspace{{0.1cm}} \\normalsize \\textit{{{title_suffix}}}}}
            \\vspace{{0.2cm}}
            \\label{{tab:{m_name_raw.lower()}}}
            \\resizebox{{\\textwidth}}{{!}}{{
            {raw_tabular}
            }}
            \\end{{table}}
            """
            
            base_measure = ''.join(c for c in m_name_raw.split('_')[0] if not c.isdigit())
            folder_name = base_measure.lower()
            
            full_content = tex_fragment + get_spec_legend(base_measure)
            
            target_indiv_dir = os.path.join(individual_base_path, folder_name)
            create_pdf(full_content, f"Table_{m_name_raw}", target_indiv_dir)
            measure_groups[base_measure].append(full_content + "\n\\newpage\n")
            
    for measure, contents in measure_groups.items():
        summary_content = "\n".join(contents)
        folder_name = measure.lower()
        target_agg_dir = os.path.join(aggregated_base_path, folder_name)
        create_pdf(summary_content, f"Summary_{measure}_Tables", target_agg_dir)

if __name__ == "__main__":
    process_results()