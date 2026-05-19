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

   DATE RANGE: Apr 2024 - Sep 2025 (21 monthly files).
    Nov and Dec 2025 files not yet published by HHSC as of ingestion.
    No preliminary data loaded -- preliminary county file skipped as
    2026 data has no counterpart tables to join against.
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
        "medicaid_caseload",
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
        enrollment_count,

        'point_in_time_count'                          as count_methodology,

        current_timestamp()                            as dbt_loaded_at

    from unpivoted

)

select * from staged