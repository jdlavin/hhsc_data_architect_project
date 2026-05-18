{{
    config(
        materialized='view',
        description='Staged monthly CHIP enrollment by sub-program. Casts types and standardizes names. Does not aggregate.'
    )
}}

/*
    SOURCE: HHSC_RAW.RAW.CHIP_ENROLLMENT_DETAIL
    GRAIN: One row per program per report_month (138 rows, Sep 2014-Feb 2026)

    CHIP covers children in families with incomes too high for Medicaid but
    who cannot afford private insurance. CHIP Perinate covers unborn children
    of pregnant women.

    PRELIMINARY DATA NOTE:
    Rows for Sep 2025 onward are within the 24-month TX retroactive adjustment
    window and are subject to revision.
*/

with source as (

    select * from {{ source('hhsc_raw', 'chip_enrollment_detail') }}

),

staged as (

    select
        -- keys
        cast(report_date as date)                          as report_month,
        trim(program)                                      as chip_program,

        -- measures
        cast(enrollment as integer)                        as enrollment_count,

        -- methodology documentation (consistent with risk group table)
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
