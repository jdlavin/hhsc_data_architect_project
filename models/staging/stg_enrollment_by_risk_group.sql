{{
    config(
        materialized='view',
        description='Staged monthly Medicaid enrollment by risk group. Unpivots wide source table to long format, casts types, and documents count methodology per risk group.'
    )
}}

/*
    SOURCE: HHSC_RAW.RAW.ENROLLMENT_BY_RISK_GROUP
    GRAIN: One row per risk_group per report_month (138 months x 10 risk dimensions = 1,390 rows)
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

    EXCLUDED ROWS:
      - medicaid_caseload: grand total row, excluded at unpivot stage. Requires
        domain knowledge to identify as derived — filtered here rather than at
        ingestion. Reconstruct in marts via sum() if needed.
      - childrens_and_chip_total excluded at ingestion -- derived sum, not a
        true risk group. Recalculate in marts if needed by summing component columns.

    RISK GROUP CATEGORIES:
    risk_group_category maps each risk group to its HHSC report header bucket.
    childrens_medicaid_chip_group and regular_chip appear under
    childrens_medicaid_and_chip and should not be summed alongside
    childrens_medicaid_risk_group to avoid double-counting children's Medicaid.
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

        case
            when risk_group in (
                'aged_and_medicare_related',
                'breast_and_cervical_cancer',
                'disability_related',
                'parents',
                'pregnant_women',
                'childrens_medicaid_risk_group'
            )                               then 'caseload_by_risk_group'
            when risk_group in (
                'medicaid_clients_under_21',
                'medicaid_clients_21_and_older'
            )                               then 'caseload_by_age'
            when risk_group in (
                'childrens_medicaid_chip_group',
                'regular_chip'
            )                               then 'childrens_medicaid_and_chip'
        end                                 as risk_group_category,

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
        end                                 as count_methodology,

        current_timestamp()                 as dbt_loaded_at

    from unpivoted

)

select * from staged