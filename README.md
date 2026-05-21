Welcome to your new dbt project!

### Using the starter project

Try running the following commands:
- dbt run
- dbt test


### Resources:
- Learn more about dbt [in the docs](https://docs.getdbt.com/docs/introduction)
- Check out [Discourse](https://discourse.getdbt.com/) for commonly asked questions and answers
- Join the [chat](https://community.getdbt.com/) on Slack for live discussions and support
- Find [dbt events](https://events.getdbt.com) near you
- Check out [the blog](https://blog.getdbt.com/) for the latest news on dbt's development and best practices
# HHSC CFO Data Architect Portfolio Pipeline

A production-style data pipeline built on real, publicly available Texas Medicaid/CHIP data
from the [HHSC Healthcare Statistics website](https://www.hhs.texas.gov/about/records-statistics/data-statistics/healthcare-statistics).
Designed as a portfolio project targeting the [HHSC CFO Data Architect I role (Posting #12430)](https://jobshrportal.hhsc.state.tx.us/),
and as a domain knowledge accelerator for Texas Medicaid finance concepts.

---

## What This Project Demonstrates

The role calls for hands-on proficiency across the full data stack — ETL, data warehousing,
data modeling, and analytics-ready output. This project covers all of it end to end:

| Requirement (from JD) | How It's Addressed Here |
|---|---|
| ETL development and monitoring | Python ingestion layer with structured error handling, full-refresh load pattern, source traceability |
| Snowflake data warehouse | Three-layer Snowflake architecture (RAW → STAGING → MARTS) with RSA key auth |
| Data modeling | 6 staging models + 6 mart models in dbt with full lineage, tests, and documentation |
| Data profiling and cleansing | Ingestion filters structural noise; staging filters semantic aggregates — distinction is documented and defensible |
| Reconciliation and data quality | 108/108 dbt tests passing across all layers; variance flags built into mart metrics |
| Analytics-ready output | Mart layer built for direct Streamlit consumption with pre-computed derived metrics |
| Domain knowledge | Medicaid enrollment, CHIP, managed care (MCO/SDA), timeliness reporting, and cost methodology nuances embedded throughout |

---

## Tech Stack

- **Python 3.11** — ingestion, EDA, Streamlit dashboard
- **Snowflake** — cloud data warehouse (RSA key pair auth)
- **dbt-snowflake** — staging and mart layer transformations, testing, documentation
- **pandas** — EDA and in-memory transformation during ingestion
- **conda** — environment management (`dbt-snowflake` env)
- **VS Code** — development IDE

---

## Architecture

```
data/raw/                          ← Source Excel files (public HHSC data)
    enrollment/
    county/
    timeliness/

ingestion/
    load_to_snowflake.py           ← Master ingestion script (5 sections)

HHSC_RAW.RAW                      ← Raw tables, faithful to source
    ENROLLMENT_BY_RISK_GROUP
    CHIP_ENROLLMENT_DETAIL
    HTW_ENROLLMENT
    ENROLLMENT_BY_COUNTY_*         ← One table per source file
    TIMELINESS_*                   ← One table per source file

HHSC_RAW.STAGING                  ← dbt view models: typed, filtered, business logic
    stg_enrollment_by_risk_group
    stg_enrollment_by_county
    stg_chip_enrollment
    stg_htw_caseload
    stg_timeliness_medicaid
    stg_mco_enrollment_by_sda

HHSC_RAW.MARTS                    ← dbt table models: analytics-ready, pre-computed metrics
    mart_enrollment_trends
    mart_enrollment_by_county
    mart_timeliness_performance
    mart_chip_enrollment
    mart_htw_caseload
    mart_mco_enrollment
```

### Design Philosophy

**Ingestion is dumb and faithful.** The Python layer loads source data as-is with minimal
transformation. Structural noise (non-numeric county codes, footnote rows) is filtered during
ingestion because it is meaningless at any layer. All business logic — semantic filtering,
type casting, methodology flags — is deferred to dbt.

**Staging filters semantic aggregates.** Rows like `medicaid_caseload` (a subtotal row
present in the risk group and county files) and structurally empty timeliness record types
(`MEPD`, `ST OFFICE`, `UNKNOWN`) are filtered at the staging layer, where the decision is
documented, testable, and visible to downstream consumers.

**Marts are pre-computed for analytics.** The mart layer materializes as tables and carries
all derived metrics so that Streamlit and other consumers run zero business logic of their own.

---

## Data Sources

All data is publicly available from the Texas HHSC Healthcare Statistics website.

| Source | Coverage | Grain |
|---|---|---|
| Enrollment by Risk Group | Monthly, statewide | Risk group × month |
| Enrollment by County | Monthly, by county | Risk group × county × month |
| CHIP Enrollment Detail | Monthly, statewide | Month |
| Healthy Texas Women (HTW) Enrollment | Monthly, statewide | Month |
| Timeliness | Monthly, by region | Record type × region × month |
| MCO Enrollment by SDA | SFY2025 annual averages | MCO × program × sub-program × SDA |

---

## Staging Layer

Six dbt view models. Each handles type casting, semantic filtering, business logic flags,
and documentation.

| Model | Grain | Key Notes |
|---|---|---|
| `stg_enrollment_by_risk_group` | risk_group × month | Unpivoted from wide format. 10 risk groups. `medicaid_caseload` aggregate filtered. `risk_group_category` added. Methodology note for Aug/Sep 2025 |
| `stg_enrollment_by_county` | risk_group × county × month | Unpivoted. 255 counties including Unknown (code 255). `is_unknown_county` flag. Jan 2024–Sep 2025 |
| `stg_chip_enrollment` | month | Wide format retained. 4 metrics: caseload, new_enrollment, renewals, disenrollment |
| `stg_htw_caseload` | month | Single statewide caseload. Methodology note for Aug 2025 |
| `stg_timeliness_medicaid` | record_type × region × month | MEPD, ST OFFICE, UNKNOWN filtered (structurally empty rows). 672 rows |
| `stg_mco_enrollment_by_sda` | mco × program × sub_program × sda | SFY2025 annual averages. 205 rows |

---

## Mart Layer

Six dbt table models. All derived metrics are pre-computed here.

| Model | Rows | Key Derived Metrics |
|---|---|---|
| `mart_enrollment_trends` | 1,380 | `mom_change`, `mom_change_pct`, `pct_of_total` |
| `mart_enrollment_by_county` | 42,840 | `mom_change`, `pct_of_county_total`, `pct_of_state_total`, `is_unknown_county` |
| `mart_timeliness_performance` | 672 | `pct_timely`, `src_percent`, `pct_timely_variance`, `mom_change_pct_timely`, `rolling_3m_pct_timely` |
| `mart_chip_enrollment` | 138 | `net_enrollment`, `renewal_rate`, `disenrollment_rate`, `caseload_reconciliation_variance_pct` |
| `mart_htw_caseload` | 138 | `mom_change_caseload`, `mom_change_pct_caseload` |
| `mart_mco_enrollment` | 205 | `mco_share_of_sda`, `mco_share_of_program` |

---

## Data Quality

**108/108 dbt tests passing** across all three layers.

Tests cover:
- `not_null` and `unique` constraints on all grain-defining columns
- Accepted value tests on categorical fields (risk group, region, record type)
- Relationship tests between staging and mart layers
- Custom range tests on derived percentage metrics

### Known Methodology Nuances (Interview-Ready)

These are not data quality issues — they are intentional design decisions reflecting how
Texas Medicaid data actually works:

**Enrollment counts will not reconcile across tables.** The risk group file, county file,
and CHIP file use different count methodologies (point-in-time, ever-enrolled, unduplicated).
This is by design. A `count_methodology` column documents this at the staging layer.

**Texas has a 24-month retroactive adjustment window.** The same month's enrollment figure
will look different depending on when the snapshot was taken. The preliminary county file
(which bridges the Sep 2025–Feb 2026 gap) carries an `is_preliminary` flag at staging.

**`pct_of_total` denominators use `caseload_by_risk_group` only** to avoid double-counting
across the unpivoted risk group grain.

**STAR Health shows 100% `mco_share_of_sda`.** This is correct — STAR Health has a single
statewide contractor by design.

**`caseload_reconciliation_variance_pct` peaks at ~4.1%** for April 2020, coinciding with
COVID-era processing disruptions. This is expected and documented.

---

## Key Implementation Details

- All source column names are lowercased at ingestion and require double-quoted identifiers in dbt
- All date columns are stored as Unix microseconds (scale 6) — cast with `cast(to_timestamp("col", 6) as date)`
- County files for November and December 2025 are intentionally absent — not yet released by the agency
- Snowflake authentication uses RSA key pair (private key at `~/.ssh/snowflake/rsa_key.p8`)
- `format='mixed'` date parsing handles inconsistent filename conventions (full month names vs. abbreviations) across the source file set

---

## Local Setup

### Prerequisites

- Snowflake account with `ACCOUNTADMIN` role (or equivalent)
- Conda (Python 3.11 required — 3.14 is incompatible with dbt)
- RSA key pair configured for Snowflake auth

### Environment

```bash
conda activate dbt-snowflake
```

### Snowflake Objects

Create the three-layer structure before running anything:

```sql
CREATE DATABASE HHSC_RAW;
CREATE SCHEMA HHSC_RAW.RAW;
CREATE SCHEMA HHSC_RAW.STAGING;
CREATE SCHEMA HHSC_RAW.MARTS;
```

### Ingestion

```bash
python ingestion/load_to_snowflake.py
```

Loads all five source datasets into `HHSC_RAW.RAW`. Full-refresh on every run.

### dbt

```bash
# Must run from inside the project directory
cd hhsc_data_architect_project

dbt run        # Build staging and mart models
dbt test       # Run all 108 tests
dbt docs generate && dbt docs serve   # Browse lineage and documentation
```

### Profiles

dbt expects `~/.dbt/profiles.yml` configured for your Snowflake account. Profile name
must match the `profile:` value in `dbt_project.yml`.

---

## Project Context

This project was built as a portfolio piece targeting the HHSC CFO Data Architect I role
(Posting #12430, closing July 7, 2026). The domain — Texas Medicaid and CHIP — is the
actual subject matter of the role. All data is public.

The pipeline is production-style in structure: separate ingestion, staging, and mart layers
with clear separation of concerns, documented design decisions, passing tests, and an
analytics-ready output layer. It is also a deliberate domain knowledge accelerator — the
process of building it surfaces Medicaid finance concepts (managed care capitation, PMPM,
provider finance, enrollment methodology) that are directly relevant to the work.

---

## What's Next

- Streamlit dashboard consuming the mart layer
- Additional mart metrics (PMPM cost proxies, timeliness trend analysis)
- GitHub Actions CI for dbt test automation