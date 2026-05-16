import pandas as pd
import os
from dotenv import load_dotenv
from cryptography.hazmat.primitives.serialization import load_pem_private_key
from cryptography.hazmat.backends import default_backend
import snowflake.connector
from snowflake.connector.pandas_tools import write_pandas

# Load environment variables from the .env file for Snowflake connection parameters
load_dotenv()

# load private key
with open(os.getenv('SNOWFLAKE_PRIVATE_KEY_PATH'), 'rb') as key_file:
    private_key = load_pem_private_key(
        key_file.read(),
        password=None,
        backend=default_backend()
    )
    
conn = snowflake.connector.connect(
    account=os.getenv('SNOWFLAKE_ACCOUNT'),
    user=os.getenv('SNOWFLAKE_USER'),
    private_key=private_key,
    warehouse=os.getenv('SNOWFLAKE_WAREHOUSE'),
    database=os.getenv('SNOWFLAKE_DATABASE'),
    schema='RAW',
    role=os.getenv('SNOWFLAKE_ROLE')
)

# explicitly set the database and schema context for the session
with conn.cursor() as cur:
    cur.execute("USE WAREHOUSE COMPUTE_WH")
    cur.execute("USE DATABASE HHSC_RAW")
    cur.execute("USE SCHEMA HHSC_RAW.RAW")

def load_table(df, table_name, conn):
    """Write a cleaned dataframe to Snowflake RAW schema."""
    try:
        success, num_chunks, num_rows, _ = write_pandas(
            conn=conn,
            df=df,
            table_name=table_name,
            auto_create_table=True,
            overwrite=True
        )
        print(f"Loaded {table_name}: {num_rows} rows")
    except Exception as e:
        print(f"Failed to load {table_name}: {e}")

# load the enrollment data; specify the sheet name and skip the first two rows which contain group headers
enrollment_by_rg = pd.read_excel("/Users/jameslavin/Documents/dev/hhsc_data_architect_project/data/raw/medicaid_&_chip_enrollement/monthly-enrollment-by-risk-group.xlsx", sheet_name='Caseload by RG', skiprows=2)
 
 # the last few rows are blank or contain notes, so we trim to just the data
enrollment_by_rg = enrollment_by_rg[0:138]

# standardize the column names to be lowercase, with underscores instead of spaces, and no special characters. This is necessary for loading into Snowflake
enrollment_by_rg.columns = (enrollment_by_rg.columns
    .str.strip()
    .str.lower()
    .str.replace(' ', '_', regex=False)
    .str.replace('*', '', regex=False)
    .str.replace('&', 'and', regex=False)
    .str.replace('-', '_', regex=False)
    .str.replace('\u2019', '', regex=False)  # curly apostrophe
    .str.replace("'", '', regex=False)        # straight apostrophe fallback
    .str.replace('.', '_', regex=False)       # handles the .1 suffix
)

# rename the columns to be more descriptive and clear about the risk groups.
enrollment_by_rg = enrollment_by_rg.rename(columns={
    'childrens_medicaid':   'childrens_medicaid_risk_group',
    'childrens_medicaid_1': 'childrens_medicaid_chip_group',
    'total':                'childrens_and_chip_total'
})

# add a timestamp column to track when the data was loaded into Snowflake
enrollment_by_rg['loaded_at'] = pd.Timestamp.now()

# load the enrollment by risk group to snowflake
load_table(enrollment_by_rg, 'ENROLLMENT_BY_RISK_GROUP', conn)

# load the CHIP enrollment data; sheet name is specified and we skip the first row which contains group headers
chip_enrollment = pd.read_excel("/Users/jameslavin/Documents/dev/hhsc_data_architect_project/data/raw/medicaid_&_chip_enrollement/chip-enrollment-detail.xlsx", sheet_name='CHIP Regular Caseload', skiprows=1)

# the last few rows are blank or contain notes, so we trim to just the data
chip_enrollment = chip_enrollment[0:138]

# standardize the column names to be lowercase, with underscores instead of spaces, and no special characters. This is necessary for loading into Snowflake
chip_enrollment.columns = (chip_enrollment.columns
    .str.strip()
    .str.lower()
    .str.replace(' ', '_', regex=False)
    .str.replace('*', '', regex=False)
    .str.replace('&', 'and', regex=False)
    .str.replace('-', '_', regex=False)
    .str.replace('\u2019', '', regex=False)  # curly apostrophe
    .str.replace("'", '', regex=False)        # straight apostrophe fallback
    .str.replace('.', '_', regex=False)       # handles the .1 suffix
)

# add a timestamp column to track when the data was loaded into Snowflake
chip_enrollment['loaded_at'] = pd.Timestamp.now()

# load the chip enrollment to snowflake
load_table(chip_enrollment, 'CHIP_ENROLLMENT_DETAIL', conn)

# load the healtthy texas women enrollment data; sheet name is specified
hwt_enrollment = pd.read_excel("/Users/jameslavin/Documents/dev/hhsc_data_architect_project/data/raw/medicaid_&_chip_enrollement/healthy-texas-women-enrollment.xlsx", sheet_name='Summary')

# the last few rows are blank or contain notes, so we trim to just the data
hwt_enrollment = hwt_enrollment[0:138]

# standardize the column names to be lowercase, with underscores instead of spaces, and no special characters. This is necessary for loading into Snowflake
hwt_enrollment.columns = (hwt_enrollment.columns
    .str.strip()
    .str.lower()
    .str.replace(' ', '_', regex=False)
    .str.replace('*', '', regex=False)
    .str.replace('&', 'and', regex=False)
    .str.replace('-', '_', regex=False)
    .str.replace('\u2019', '', regex=False)  # curly apostrophe
    .str.replace("'", '', regex=False)        # straight apostrophe fallback
    .str.replace('.', '_', regex=False)       # handles the .1 suffix
)

# rename the columns to be more descriptive and clear about the risk groups
hwt_enrollment = hwt_enrollment.rename(columns={
    'healthy_texas_women_caseload':   'month',
    'unnamed:_1': 'caseload',
})

# add a timestamp column to track when the data was loaded into Snowflake
hwt_enrollment['loaded_at'] = pd.Timestamp.now()

# load the healthy texas women to snowflake
load_table(hwt_enrollment, 'HTW_ENROLLMENT', conn)

# close once at the very end
conn.close()
print("Connection closed.")
