{{
    config(
        materialized='view',
        description='Staged monthly Medicaid enrollment by risk group. Casts types, standardizes names, and documents count methodology. Does not aggregate.'
    )
}}

/*
    SOURCE: HHSC_RAW.RAW.ENROLLMENT_BY_RISK_GROUP
    GRAIN: One row per risk_group per report_month (138 rows, Sep 2014-Feb 2026)

    COUNT METHODOLOGY NOTE:
    Risk group counts use an ever-enrolled (unduplicated) methodology -- a member
    is counted once in a given month regardless of how many days they were enrolled.
    This WILL NOT reconcile with stg_enrollment_by_county, which uses a
    point-in-time (end-of-month snapshot) methodology. This is by design per
    HHSC reporting practice. See count_methodology column.

    PRELIMINARY DATA NOTE:
    TX policy allows 24-month retroactive adjustments. Rows for Sep 2025 onward
    are considered preliminary and subject to revision. See is_preliminary column.
*/

with source as (

    select * from {{ source('hhsc_raw', 'enrollment_by_risk_group') }}

),

staged as (

    select
        -- keys
        cast(report_date as date)                          as report_month,
        trim(risk_group)                                   as risk_group,

        -- measures
        cast(enrollment as integer)                        as enrollment_count,

        -- methodology documentation
        'ever_enrolled_unduplicated'                       as count_methodology,

        /*
            Preliminary flag: Sep 2025 onward is within the 24-month TX retroactive
            adjustment window. The same calendar month will show different totals
            depending on which snapshot file you pull -- this is expected behavior,
            not a data quality issue. Do not join or compare preliminary rows to
            finalized rows without accounting for this.
        */
        case
            when cast(report_date as date) >= '2025-09-01' then true
            else false
        end                                                as is_preliminary,

        -- audit
        current_timestamp()                                as dbt_loaded_at

    from source

)

select * from staged
