{{
    config(
        materialized='view',
        description='Staged monthly Medicaid enrollment by risk group. Unpivots wide source table to long format, casts types, and documents count methodology per risk group.'
    )
}}

/*
    SOURCE: HHSC_RAW.RAW.ENROLLMENT_BY_RISK_GROUP
    GRAIN: One row per risk_group per report_month (138 months x 10 risk groups = 1,380 rows)
    DATE RANGE: Sep 2014 - Feb 2026

    SHAPE CHANGE: Source table is wide (one column per risk group). This model
    unpivots to long format (one row per risk group) to support GROUP BY and
    filtering in mart models.

    COUNT METHODOLOGY:
    Most columns shift from point_in_time_count to average_daily_enrollment
    at Aug 2025 when HHSC changed their internal reporting calculation.
    Two exceptions:
      - medicaid_clients_under_21: shift happens one month later at Sep 2025
      - regular_chip: never exhibited fractional values, methodology unconfirmed,
        treated as point_in_time_count throughout

    childrens_and_chip_total excluded at ingestion -- derived sum, not a
    true risk group. Recalculate in marts if needed by summing component columns.
*/

with source as (

    select * from {{ source('hhsc_raw', 'enrollment_by_risk_group') }}

),

unpivoted as (

    select
        cast(to_timestamp("month", 6) as date)  as report_month,
        risk_group,
        cast(enrollment as float)               as enrollment_count
    from source
    unpivot(enrollment for risk_group in (
        "medicaid_caseload",
        "aged_and_medicare_related",
        "disability_related",
        "parents",
        "pregnant_women",
        "breast_and_cervical_cancer",
        "childrens_medicaid_risk_group",
        "medicaid_clients_under_21",
        "medicaid_clients_21_and_older",
        "childrens_medicaid_chip_group",
        "regular_chip"
    ))

),

staged as (

    select
        report_month,
        risk_group,
        enrollment_count,

        case
            when risk_group = 'regular_chip'
                then 'point_in_time_count'
            when risk_group = 'medicaid_clients_under_21'
                and report_month >= '2025-09-01'
                then 'average_daily_enrollment'
            when risk_group != 'medicaid_clients_under_21'
                and report_month >= '2025-08-01'
                then 'average_daily_enrollment'
            else 'point_in_time_count'
        end                         as count_methodology,

        current_timestamp()         as dbt_loaded_at

    from unpivoted

)

select * from staged