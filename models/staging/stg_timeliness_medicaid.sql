{{
    config(
        materialized='view',
        description='Staged Medicaid application and redetermination timeliness metrics. Casts types, derives pct_timely where not already present, and flags preliminary rows.'
    )
}}

/*
    SOURCE: HHSC_RAW.RAW.TIMELINESS_MEDICAID
    GRAIN: One row per measure_type per report_month (864 rows, 24-month rolling window)
    MEASURE TYPES: Applications, Redeterminations

    Federal timeliness standards:
      - Applications: 45 days for most; 90 days for disability-related
      - Redeterminations: processed before coverage lapses

    pct_timely is either sourced directly from raw or derived here as
    timely_cases / nullif(total_cases, 0). Both paths produce the same result;
    the derivation is a safeguard against raw file inconsistencies.

    PRELIMINARY DATA NOTE:
    Same 24-month TX retroactive window applies. Rows for Sep 2025 onward
    flagged is_preliminary=true.
*/

with source as (

    select * from {{ source('hhsc_raw', 'timeliness_medicaid') }}

),

staged as (

    select
        -- keys
        cast(report_date as date)                          as report_month,
        trim(measure_type)                                 as measure_type,

        -- measures
        cast(total_cases as integer)                       as total_cases,
        cast(timely_cases as integer)                      as timely_cases,
        cast(total_cases - timely_cases as integer)        as untimely_cases,

        -- derived rate: prefer source value, fall back to calculation
        coalesce(
            cast(pct_timely as float),
            round(
                cast(timely_cases as float) / nullif(cast(total_cases as float), 0) * 100,
                2
            )
        )                                                  as pct_timely,

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
