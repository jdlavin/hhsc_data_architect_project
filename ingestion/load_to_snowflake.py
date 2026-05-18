import pandas as pd
import os
import re
from pathlib import Path
from dotenv import load_dotenv
from cryptography.hazmat.primitives.serialization import load_pem_private_key
from cryptography.hazmat.backends import default_backend
import snowflake.connector
from snowflake.connector.pandas_tools import write_pandas

load_dotenv()

# ── Snowflake connection ──────────────────────────────────────────────────────

with open(os.getenv('SNOWFLAKE_PRIVATE_KEY_PATH'), 'rb') as key_file:
    private_key = load_pem_private_key(key_file.read(), password=None, backend=default_backend())

conn = snowflake.connector.connect(
    account=os.getenv('SNOWFLAKE_ACCOUNT'),
    user=os.getenv('SNOWFLAKE_USER'),
    private_key=private_key,
    warehouse=os.getenv('SNOWFLAKE_WAREHOUSE'),
    database=os.getenv('SNOWFLAKE_DATABASE'),
    schema='RAW',
    role=os.getenv('SNOWFLAKE_ROLE')
)

with conn.cursor() as cur:
    cur.execute("USE WAREHOUSE COMPUTE_WH")
    cur.execute("USE DATABASE HHSC_RAW")
    cur.execute("USE SCHEMA HHSC_RAW.RAW")

# ── Helper functions ──────────────────────────────────────────────────────────

def clean_columns(df):
    """Standardize column names for Snowflake compatibility."""
    df.columns = (df.columns
        .str.strip()
        .str.lower()
        .str.replace(' ', '_', regex=False)
        .str.replace('*', '', regex=False)
        .str.replace('&', 'and', regex=False)
        .str.replace('-', '_', regex=False)
        .str.replace('\u2019', '', regex=False)
        .str.replace("'", '', regex=False)
        .str.replace('.', '_', regex=False)
    )
    return df

def load_table(df, table_name):
    """Write a cleaned dataframe to Snowflake RAW schema."""
    try:
        success, num_chunks, num_rows, _ = write_pandas(
            conn=conn,
            df=df,
            table_name=table_name,
            auto_create_table=True,
            overwrite=True
        )
        print(f"  Loaded {table_name}: {num_rows} rows")
    except Exception as e:
        print(f"  Failed to load {table_name}: {e}")

RAW = Path("/Users/jameslavin/Documents/dev/hhsc_data_architect_project/data/raw")

MONTH_MAP = {
    'jan': '01', 'feb': '02', 'mar': '03', 'april': '04', 'apr': '04',
    'may': '05', 'jun': '06', 'june': '06', 'july': '07', 'jul': '07',
    'aug': '08', 'sep': '09', 'sept': '09', 'oct': '10', 'nov': '11', 'dec': '12'
}

def parse_report_month(filename):
    """Extract YYYY-MM-01 date from filenames ending in -mon-YYYY.xlsx"""
    name = filename.lower().replace('.xlsx', '')
    parts = name.split('-')
    year = parts[-1]
    month_str = parts[-2]
    month_num = MONTH_MAP.get(month_str)
    if not month_num:
        raise ValueError(f"Could not parse month from filename: {filename}")
    return f"{year}-{month_num}-01"

# ── 1. Enrollment by Risk Group ───────────────────────────────────────────────

print("\n[1/6] Loading enrollment by risk group...")

df = pd.read_excel(
    RAW / "medicaid_&_chip_enrollement/monthly-enrollment-by-risk-group.xlsx",
    sheet_name='Caseload by RG',
    skiprows=2
)
 # the last few rows are blank or contain notes, so we trim to just the data
df = df[0:138]

df = clean_columns(df)
df = df.rename(columns={
    'childrens_medicaid':   'childrens_medicaid_risk_group',
    'childrens_medicaid_1': 'childrens_medicaid_chip_group',
    'total':                'childrens_and_chip_total'
})

# drop total column since it's just the sum of the other columns and can be calculated in Snowflake if needed
df = df.drop(columns=['childrens_and_chip_total'])

df['loaded_at'] = pd.Timestamp.now()
load_table(df, 'ENROLLMENT_BY_RISK_GROUP')

# ── 2. CHIP Enrollment Detail ─────────────────────────────────────────────────

print("\n[2/6] Loading CHIP enrollment detail...")

df = pd.read_excel(
    RAW / "medicaid_&_chip_enrollement/chip-enrollment-detail.xlsx",
    sheet_name='CHIP Regular Caseload',
    skiprows=1
)
df = df[0:138]
df = clean_columns(df)
df['loaded_at'] = pd.Timestamp.now()
load_table(df, 'CHIP_ENROLLMENT_DETAIL')

# ── 3. Healthy Texas Women Enrollment ────────────────────────────────────────

print("\n[3/6] Loading Healthy Texas Women enrollment...")

df = pd.read_excel(
    RAW / "medicaid_&_chip_enrollement/healthy-texas-women-enrollment.xlsx",
    sheet_name='Summary'
)
df = df[0:138]
df = clean_columns(df)
df = df.rename(columns={
    'healthy_texas_women_caseload': 'month',
    'unnamed:_1':                   'caseload'
})
df['loaded_at'] = pd.Timestamp.now()
load_table(df, 'HTW_ENROLLMENT')

# ── 4. Enrollment by County (loop) ────────────────────────────────────────────

print("\n[4/6] Loading enrollment by county...")

COUNTY_DIR = RAW / "county"
all_frames = []

for filepath in sorted(COUNTY_DIR.glob("*.xlsx")):
    filename = filepath.name
    report_month = parse_report_month(filename)

    df = pd.read_excel(filepath, sheet_name='Summary', skiprows=2, header=0)

    df.columns = [
        'hhsc_county_code',
        'county',
        'medicaid_caseload',
        'aged_and_medicare_related',
        'disability_related',
        'parents',
        'pregnant_women',
        'breast_and_cervical_cancer',
        'childrens_medicaid',
        'medicaid_clients_under_21',
        'medicaid_clients_21_and_older'
    ]

    # drop total row and footnotes — keep only rows with a numeric county code
    df = df[pd.to_numeric(df['hhsc_county_code'], errors='coerce').notna()].copy()
    df['hhsc_county_code'] = df['hhsc_county_code'].astype(int)

    df['report_month'] = pd.to_datetime(report_month)
    df['source_file']  = filename
    df['loaded_at']    = pd.Timestamp.now()

    all_frames.append(df)
    print(f"  Processed {filename}: {len(df)} rows")

combined = pd.concat(all_frames, ignore_index=True)
print(f"  Total rows: {len(combined)}")
load_table(combined, 'ENROLLMENT_BY_COUNTY')

# ── 5. Timeliness ─────────────────────────────────────────────────────────────

print("\n[5/6] Loading timeliness...")

TIMELINESS_DIR = RAW / "timeliness"
all_timeliness = []

for filepath in sorted(TIMELINESS_DIR.glob("*.xlsx")):
    filename = filepath.name

    match = re.search(r'medicaid-(\w+-\d{4})\.xlsx', filename)
    if not match:
        print(f"  Skipping {filename} - could not parse month")
        continue
    report_month = pd.to_datetime(match.group(1), format='mixed')

    apps = pd.read_excel(filepath, sheet_name='Medicaid', skiprows=3)
    apps = apps[1:19]
    apps['record_type'] = 'applications'

    redets = pd.read_excel(filepath, sheet_name='Medicaid', skiprows=25)
    redets = redets[1:19]
    redets['record_type'] = 'redeterminations'

    combined = pd.concat([apps, redets], ignore_index=True)
    combined['report_month'] = report_month
    combined['source_file']  = filename
    all_timeliness.append(combined)
    print(f"  Processed {filename}: {len(combined)} rows")

timeliness = pd.concat(all_timeliness, ignore_index=True)

timeliness.columns = (timeliness.columns
    .str.strip()
    .str.lower()
    .str.replace(' ', '_', regex=False)
)

geographic_regions = ['01', '02/09', '03', '04', '05', '06', '07', '08', '10', '11']
timeliness['is_geographic_region'] = timeliness['region'].isin(geographic_regions)
timeliness['loaded_at'] = pd.Timestamp.now()

print(f"  Total rows: {len(timeliness)}")
load_table(timeliness, 'TIMELINESS_MEDICAID')

# ── 6. MCO Enrollment by SDA ─────────────────────────────────────────────────

print("\n[6/6] Loading MCO enrollment by SDA...")

f = RAW / "medicaid_&_chip_enrollement/mco-enrollment-by-sda-final-sfy25.xlsx"
df_raw = pd.read_excel(f, sheet_name=0, header=None)

sda_columns = df_raw.iloc[1, 1:-1].tolist()

MCO_BLOCK_SIZE = 10
DATA_START_ROW = 2
DATA_END_ROW   = 202

PROGRAM_MAP = {
    0: ('TOTAL',    'TOTAL'),
    1: ('CHIP',     'TOTAL'),
    2: ('CHIP',     'Regular'),
    3: ('CHIP',     'Perinatal'),
    4: ('MEDICAID', 'TOTAL'),
    5: ('MEDICAID', 'STAR'),
    6: ('MEDICAID', 'STAR+Plus'),
    7: ('MEDICAID', 'Dual Demo'),
    8: ('MEDICAID', 'STAR Health'),
    9: ('MEDICAID', 'STAR Kids'),
}

records = []

for block_start in range(DATA_START_ROW, DATA_END_ROW, MCO_BLOCK_SIZE):
    mco_name = df_raw.iloc[block_start, 0]

    for offset, (program, sub_program) in PROGRAM_MAP.items():
        row = df_raw.iloc[block_start + offset, 1:-1]

        for sda, value in zip(sda_columns, row):
            if pd.isna(value):
                continue

            records.append({
                'mco_name':        mco_name,
                'program':         program,
                'sub_program':     sub_program,
                'sda':             sda,
                'enrollment':      value,
                'enrollment_type': 'sfy_monthly_average',
                'fiscal_year':     2025,
                'source_file':     f.name,
                'loaded_at':       pd.Timestamp.now()
            })

mco_sda = pd.DataFrame(records)
mco_sda['mco_name'] = mco_sda['mco_name'].str.replace('\n', ' ', regex=False).str.strip()

print(f"  Total rows: {len(mco_sda)}")
load_table(mco_sda, 'MCO_ENROLLMENT_BY_SDA')

# ── Done ──────────────────────────────────────────────────────────────────────

conn.close()
print("\nAll tables loaded. Connection closed.")

