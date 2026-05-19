{{
    config(
        materialized='view',
        description='Staged SFY2025 Medicaid MCO enrollment by Service Delivery Area. Casts types and documents SFY monthly average count methodology. Does not aggregate.'
    )
}}

/*
    SOURCE: HHSC_RAW.RAW.MCO_ENROLLMENT_BY_SDA
    GRAIN: One row per MCO per program per sub_program per SDA (205 rows)
           SFY2025 full year averages -- no monthly breakdown available.

    COUNT METHODOLOGY NOTE:
    These are SFY monthly AVERAGES, not point-in-time counts. A member enrolled
    for half the month counts as 0.5. This is fundamentally different from both
    the risk group and county methodologies. These numbers WILL NOT reconcile
    with any other enrollment table. See enrollment_type column.

    TOTAL ROWS: program='TOTAL' and sub_program='TOTAL' rows excluded at
    ingestion -- derived aggregates. Totals can be derived in marts by summing
    across program/sub_program combinations.

    No fiscal_month in source data -- this is a full fiscal year average.
    fiscal_year carries the time dimension.
*/

with source as (

    select * from {{ source('hhsc_raw', 'mco_enrollment_by_sda') }}

),

staged as (

    select
        -- keys
        trim("mco_name")                                   as mco_name,
        trim("program")                                    as program,
        trim("sub_program")                                as sub_program,
        trim("sda")                                        as sda,
        cast("fiscal_year" as integer)                     as fiscal_year,

        -- measures
        cast("enrollment" as float)                        as enrollment_avg,

        -- methodology passthrough from source
        trim("enrollment_type")                            as enrollment_type,

        -- audit
        current_timestamp()                                as dbt_loaded_at

    from source

)

select * from staged