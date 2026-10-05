import pandas as pd
import os
import subprocess

results_path = "/if/research-eme/omar/Harun/output/baseline_regressions/csvs"
output_path = "/if/research-eme/omar/Harun/output/baseline_regressions/tables/structural_models"

def escape_latex(text):
    if not isinstance(text, str): text = str(text)
    text = text.replace('="', '').replace('"', '')
    if text.startswith('='): text = text[1:]
    
    # CRITICAL FIX: Escape the Stata interaction '#' character so LaTeX doesn't crash
    text = text.replace('_', r'\_').replace('%', r'\%').replace('&', r'\&').replace('#', r'\#')
    
    rename_dict = {
        # Base Variables
        r'log\_internal\_quality': 'Log Internal Quality',
        r'small\_entity': 'Small Entity',
        r'is\_breakthrough': 'Top 5\% Breakthrough',
        'Obs': 'Observations',
        'R2': '$R^2$',
        r'\_cons': 'Constant',
        
        # Main Effects (Decile)
        r'1.firm\_size\_bin\_decile': 'Small Firm (Bottom Decile)',
        r'2.firm\_size\_bin\_decile': 'Middle 80\% (Omitted)',
        r'3.firm\_size\_bin\_decile': 'Dominant Firm (Top Decile)',
        r'1.firm\_size\_bin': 'Small Firm (Bottom Decile)',
        r'2.firm\_size\_bin': 'Middle 80\% (Omitted)',
        r'3.firm\_size\_bin': 'Dominant Firm (Top Decile)',
        
        # Main Effects (Quartile)
        r'1.firm\_size\_bin\_quartile': 'Small Firm (Bottom Quartile)',
        r'2.firm\_size\_bin\_quartile': 'Middle 50\% (Omitted)',
        r'3.firm\_size\_bin\_quartile': 'Dominant Firm (Top Quartile)',
        
        # Interactions (Decile)
        r'1.firm\_size\_bin\#c.log\_internal\_quality': 'Quality $\times$ Small Firm (Decile)',
        r'2.firm\_size\_bin\#c.log\_internal\_quality': 'Quality $\times$ Middle (Omitted)',
        r'3.firm\_size\_bin\#c.log\_internal\_quality': 'Quality $\times$ Dominant Firm (Decile)',
        r'1.firm\_size\_bin\#c.log\_hhi1\_class': 'HHI $\times$ Small Firm',
        r'3.firm\_size\_bin\#c.log\_hhi1\_class': 'HHI $\times$ Dominant Firm',
        r'1.firm\_size\_bin\#c.flowq1\_class': 'Flow Volume $\times$ Small Firm',
        r'3.firm\_size\_bin\#c.flowq1\_class': 'Flow Volume $\times$ Dominant Firm',
        r'1.firm\_size\_bin\_decile\#c.log\_clone\_count1': 'Clone Count $\times$ Small Firm',
        r'3.firm\_size\_bin\_decile\#c.log\_clone\_count1': 'Clone Count $\times$ Dominant Firm',
        
        # Interactions (Quartile)
        r'1.firm\_size\_bin\_quartile\#c.log\_internal\_quality': 'Quality $\times$ Bottom Quartile',
        r'2.firm\_size\_bin\_quartile\#c.log\_internal\_quality': 'Quality $\times$ Middle (Omitted)',
        r'3.firm\_size\_bin\_quartile\#c.log\_internal\_quality': 'Quality $\times$ Top Quartile',
        r'1.firm\_size\_bin\_quartile\#c.log\_hhi1\_class': 'HHI $\times$ Bottom Quartile',
        r'3.firm\_size\_bin\_quartile\#c.log\_hhi1\_class': 'HHI $\times$ Top Quartile',
        r'1.firm\_size\_bin\_quartile\#c.flowq1\_class': 'Flow Volume $\times$ Bottom Quartile',
        r'3.firm\_size\_bin\_quartile\#c.flowq1\_class': 'Flow Volume $\times$ Top Quartile',
        r'1.firm\_size\_bin\_quartile\#c.log\_clone\_count1': 'Clone Count $\times$ Bottom Quartile',
        r'3.firm\_size\_bin\_quartile\#c.log\_clone\_count1': 'Clone Count $\times$ Top Quartile',
    }
    
    if text in rename_dict: return rename_dict[text]
    return text

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
        print(f"Successfully compiled {output_filename}.pdf")
    except Exception as e:
        print(f"Error compiling {output_filename}: {e}")

def process_structural_tables():
    if not os.path.exists(results_path): return
    
    files_to_process = {
        'structural_quality.csv': "Arrow vs. Schumpeter: Radical Innovation by Firm Size",
        'structural_behavior.csv': "Patent Thickets \& Congestion: Renewal Strategies by Firm Size"
    }
    
    for filename, title in files_to_process.items():
        file_path = os.path.join(results_path, filename)
        if not os.path.exists(file_path): continue
            
        df = pd.read_csv(file_path)
        
        # Clean headers
        headers = ["Variable"] + [f"({i})" for i in range(1, len(df.columns))]
        df.columns = headers
        
        df = df.fillna("")
        if hasattr(df, "map"): df = df.map(escape_latex)
        else: df = df.applymap(escape_latex)
        
        # Formatting for LaTeX
        styler = df.style.hide(axis='index')
        raw_tabular = styler.to_latex(column_format="l" + "c" * (len(df.columns) - 1), hrules=True)
        
        legend = (
            "\\vspace{0.2cm}\n"
            "\\begin{flushleft}\n"
            "\\footnotesize\n"
            "\\textbf{Notes:} Firm size bins are evaluated against the omitted middle group (the middle 80\\% for deciles, middle 50\\% for quartiles). "
            "Standard errors clustered at the Assignee level in parentheses. * $p < 0.1$, ** $p < 0.05$, *** $p < 0.01$.\n"
            "\\end{flushleft}\n"
        )
        
        tex_fragment = (
            "\\begin{table}[htbp]\n"
            "\\centering \\small\n"
            f"\\caption*{{\\Large \\textbf{{{title}}}}}\n"
            "\\vspace{0.2cm}\n"
            f"\\resizebox{{\\textwidth}}{{!}}{{\n{raw_tabular}\n}}\n"
            f"{legend}"
            "\\end{table}\n"
        )
        
        create_pdf(tex_fragment, filename.replace('.csv', ''), output_path)

if __name__ == "__main__":
    process_structural_tables()