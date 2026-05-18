{{
    config(
        materialized='view',
        description='Staged monthly CHIP enrollment metrics. Casts types and renames columns. Does not aggregate.'
    )
}}

/*
    SOURCE: HHSC_RAW.RAW.CHIP_ENROLLMENT_DETAIL
    GRAIN: One row per report_month (138 rows, Sep 2014-Feb 2026)

    CHIP covers children in families with incomes too high for Medicaid but
    who cannot afford private insurance.

    SHAPE: Wide format retained -- columns represent different metrics
    (caseload, new enrollment, renewals, disenrollment), not the same metric
    for different categories. No unpivot needed.

    No fractional values observed in any column -- integer casting is safe
    throughout the full date range. No methodology shift detected.
*/

with source as (

    select * from {{ source('hhsc_raw', 'chip_enrollment_detail') }}

),

staged as (

    select
        -- keys
        cast(to_timestamp("month", 6) as date)      as report_month,

        -- measures (all clean integers throughout full date range)
        cast("chip_caseload" as integer)             as chip_caseload,
        cast("new_enrollment" as integer)            as new_enrollment,
        cast("renewals" as integer)                  as renewals,
        cast("disenrollment" as integer)             as disenrollment,

        -- audit
        current_timestamp()                          as dbt_loaded_at

    from source

)

select * from staged