{{
    config(
        materialized='view',
        description='Staged Medicaid application and redetermination timeliness metrics. Casts types, derives pct_timely and validates against source percent.'
    )
}}

/*
    SOURCE: HHSC_RAW.RAW.TIMELINESS_MEDICAID
    GRAIN: One row per record_type per region per report_month
    RECORD TYPES: applications, redeterminations
    DATE RANGE: 24-month rolling window

    REGIONS: Numeric codes 01-11 (02/09 grouped) are geographic regions.
    Non-geographic entities (CCC, DATA INT, MEPD, etc.) represent processing
    offices or eligibility units. Use is_geographic_region flag to filter.

    TIMELINESS STANDARDS:
      - Applications: 45 days for most; 90 days for disability-related
      - Redeterminations: processed before coverage lapses

    PERCENT VALIDATION: src_percent is the raw source value. pct_timely is
    derived as timely / nullif(disposed, 0). Both should agree within rounding.
    Discrepancies indicate a source data issue worth investigating.
*/

with source as (

    select * from {{ source('hhsc_raw', 'timeliness_medicaid') }}

),

staged as (

    select
        -- keys
        cast(to_timestamp("report_month", 6) as date)          as report_month,
        trim("region")                                         as region,
        trim("record_type")                                    as record_type,

        -- measures
        cast("disposed" as integer)                            as disposed,
        cast("timely" as integer)                              as timely,
        cast("disposed" as integer) - cast("timely" as integer) as untimely,

        -- derived pct for validation against source
        round(
            cast("timely" as float) / nullif(cast("disposed" as float), 0) * 100,
            2
        )                                                      as pct_timely,
        cast("percent" as float)                               as src_percent,

        -- flags
        cast("is_geographic_region" as boolean)                as is_geographic_region,

        -- audit
        current_timestamp()                                    as dbt_loaded_at

    from source

)

select * from staged