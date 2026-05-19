{{
    config(
        materialized='view',
        description='Staged monthly Healthy Texas Women enrollment. Casts types. Does not aggregate.'
    )
}}

/*
    SOURCE: HHSC_RAW.RAW.HTW_ENROLLMENT
    GRAIN: One row per report_month (138 rows, Sep 2014-Feb 2026)

    Healthy Texas Women (HTW) provides family planning services to low-income
    women aged 15-44 who are not otherwise eligible for Medicaid. This is a
    statewide total -- no county or risk group breakdown in source data.

    CASELOAD VS ENROLLMENT: HTW reports active caseload (point-in-time active
    cases) not an enrollment flow count. Starting Aug 2025 the source data
    shifts to average daily caseload, producing fractional values.
    See count_methodology column.
*/

with source as (

    select * from {{ source('hhsc_raw', 'htw_enrollment') }}

),

staged as (

    select
        cast(to_timestamp("month", 6) as date)            as report_month,
        cast("caseload" as float)                         as htw_caseload,

        case
            when report_month >= '2025-08-01' then 'average_daily_caseload'
            else 'point_in_time_count'
        end                                               as count_methodology,

        current_timestamp()                               as dbt_loaded_at

    from source

)

select * from staged