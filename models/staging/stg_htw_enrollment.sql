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

    PRELIMINARY DATA NOTE:
    Rows for Sep 2025 onward are within the 24-month TX retroactive adjustment
    window and are subject to revision.
*/

with source as (

    select * from {{ source('hhsc_raw', 'htw_enrollment') }}

),

staged as (

    select
        -- keys
        cast(report_date as date)                          as report_month,

        -- measures
        cast(enrollment as integer)                        as enrollment_count,

        -- methodology documentation
        'ever_enrolled_unduplicated'                       as count_methodology,

        -- preliminary flag
        case
            when cast(report_date as date) >= '2025-09-01' then true
            else false
        end                                                as is_preliminary,

        -- audit
        current_timestamp()                                as dbt_loaded_at

    from source

)

select * from staged
