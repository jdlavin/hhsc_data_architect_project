import pandas as pd

enrollment = pd.read_excel("/Users/jameslavin/Documents/dev/hhsc_data_architect_project/data/raw/enrollment/monthly-enrollment-by-risk-group.xlsx", sheet_name='Caseload by RG', skiprows=2)
enrollment = enrollment[0:138]