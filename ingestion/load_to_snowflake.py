import pandas as pd
import os
from dotenv import load_dotenv
from cryptography.hazmat.primitives.serialization import load_pem_private_key
from cryptography.hazmat.backends import default_backend
import snowflake.connector
from snowflake.connector.pandas_tools import write_pandas

# Load environment variables from the .env file for Snowflake connection parameters.
load_dotenv()

# load the enrollment data from the Excel file; specify the sheet name and skip the first two rows which contain group headers.
enrollment = pd.read_excel("/Users/jameslavin/Documents/dev/hhsc_data_architect_project/data/raw/enrollment/monthly-enrollment-by-risk-group.xlsx", sheet_name='Caseload by RG', skiprows=2)
 
 # the last few rows are blank or contain notes, so we trim to just the data
enrollment = enrollment[0:138]

# standardize the column names to be lowercase, with underscores instead of spaces, and no special characters. This is necessary for loading into Snowflake.
enrollment.columns = (enrollment.columns
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
enrollment = enrollment.rename(columns={
    'childrens_medicaid':   'childrens_medicaid_risk_group',
    'childrens_medicaid_1': 'childrens_medicaid_chip_group',
    'total':                'childrens_and_chip_total'
})

# add a timestamp column to track when the data was loaded into Snowflake
enrollment['loaded_at'] = pd.Timestamp.now()

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

try:
    success, num_chunks, num_rows, _ = write_pandas(
        conn=conn,
        df=enrollment,
        table_name='ENROLLMENT_BY_RISK_GROUP',
        auto_create_table=True
    )
    print(f"Success: {success}")
    print(f"Rows loaded: {num_rows}")
finally:
    conn.close()
