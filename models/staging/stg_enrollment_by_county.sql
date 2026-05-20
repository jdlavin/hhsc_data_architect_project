{{
    config(
        materialized='view',
        description='Staged monthly Medicaid enrollment by Texas county. Unpivots wide source to long format, casts types, and documents count methodology.'
    )
}}

/*
    SOURCE: HHSC_RAW.RAW.ENROLLMENT_BY_COUNTY
    GRAIN: One row per risk_group per county per report_month
    LOADED FROM: 21 monthly release files, loop-unioned in ingestion layer.
    MISSING: Nov 2025 and Dec 2025 files not yet published by HHSC as of ingestion.

    SHAPE CHANGE: Source table is wide (one column per risk group). This model
    unpivots to long format to support GROUP BY and filtering in mart models.

    COUNT METHODOLOGY NOTE:
    County counts use point_in_time_count methodology throughout -- no fractional
    values observed even in recent months, unlike stg_enrollment_by_risk_group
    which shifted to average_daily_enrollment at Aug 2025. These two tables
    cover overlapping categories but WILL NOT reconcile due to different
    counting methodologies. Do not attempt to reconcile.

    DATE RANGE: Jan 2024 - Sep 2025 (21 monthly files).
    Nov and Dec 2025 files not yet published by HHSC as of ingestion.
    No preliminary data loaded -- preliminary county file skipped as
    2026 data has no counterpart tables to join against.

    COUNTIES: 254 named Texas counties plus county_code 255 (Unknown) --
    enrollees whose county of residence could not be determined. Unknown
    is retained as a genuine source row representing real enrollees.
    Flagged with is_unknown_county in mart models.

    EXCLUDED ROWS:
      - medicaid_caseload: grand total row, excluded at unpivot stage.
        Requires domain knowledge to identify as derived — filtered here
        rather than at ingestion. Reconstruct in marts via sum() if needed.

    RISK GROUP CATEGORIES:
      - caseload_by_risk_group: aged_and_medicare_related,
        breast_and_cervical_cancer, disability_related, parents,
        pregnant_women, childrens_medicaid
      - caseload_by_age: medicaid_clients_under_21,
        medicaid_clients_21_and_older
      - childrens_medicaid_and_chip bucket not present at county level --
        CHIP is not broken out in county enrollment files.
*/

with source as (

    select * from {{ source('hhsc_raw', 'enrollment_by_county') }}

),

unpivoted as (

    select
        cast(to_timestamp("report_month", 6) as date)  as report_month,
        "hhsc_county_code"                             as county_code,
        trim("county")                                 as county_name,
        risk_group,
        cast(enrollment as integer)                    as enrollment_count
    from source
    unpivot(enrollment for risk_group in (
        "aged_and_medicare_related",
        "disability_related",
        "parents",
        "pregnant_women",
        "breast_and_cervical_cancer",
        "childrens_medicaid",
        "medicaid_clients_under_21",
        "medicaid_clients_21_and_older"
    ))

),

staged as (

    select
        report_month,
        county_code,
        county_name,
        risk_group,

        case
            when risk_group in (
                'aged_and_medicare_related',
                'breast_and_cervical_cancer',
                'disability_related',
                'parents',
                'pregnant_women',
                'childrens_medicaid'
            )                               then 'caseload_by_risk_group'
            when risk_group in (
                'medicaid_clients_under_21',
                'medicaid_clients_21_and_older'
            )                               then 'caseload_by_age'
        end                                 as risk_group_category,

        enrollment_count,

        'point_in_time_count'               as count_methodology,

        county_code = 255                   as is_unknown_county,

        current_timestamp()                 as dbt_loaded_at

    from unpivoted

)

select * from staged