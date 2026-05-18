{{
    config(
        materialized='view',
        description='Staged SFY2025 Medicaid MCO enrollment by Service Delivery Area. Casts types and documents SFY monthly average count methodology. Does not aggregate.'
    )
}}

/*
    SOURCE: HHSC_RAW.RAW.MCO_ENROLLMENT_BY_SDA
    GRAIN: One row per MCO per SDA per fiscal_month (1,004 rows)
           19 MCOs x 14 SDAs x SFY2025 months

    COUNT METHODOLOGY NOTE:
    These are SFY monthly AVERAGES, not point-in-time counts. A member enrolled
    for half the month counts as 0.5. This is fundamentally different from both
    the risk group (ever-enrolled) and county (point-in-time) methodologies.
    These numbers WILL NOT reconcile with any other enrollment table.
    See count_methodology column.

    STATEWIDE TOTAL ROWS: Excluded in ingestion (derived aggregates do not
    belong in raw). Statewide totals can be derived in the marts layer by
    summing across all SDAs.

    FISCAL MONTH MAPPING (TX State Fiscal Year starts September 1):
        fiscal_month 1  = September
        fiscal_month 2  = October
        fiscal_month 3  = November
        fiscal_month 4  = December
        fiscal_month 5  = January
        fiscal_month 6  = February
        fiscal_month 7  = March
        fiscal_month 8  = April
        fiscal_month 9  = May
        fiscal_month 10 = June
        fiscal_month 11 = July
        fiscal_month 12 = August
*/

with source as (

    select * from {{ source('hhsc_raw', 'mco_enrollment_by_sda') }}

),

staged as (

    select
        -- keys
        trim(mco_name)                                     as mco_name,
        trim(sda_name)                                     as sda_name,
        cast(fiscal_year as integer)                       as fiscal_year,
        cast(fiscal_month as integer)                      as fiscal_month,

        -- derive a calendar date for the fiscal month (first of month)
        -- SFY starts Sep 1, so fiscal_month 1 = September of (fiscal_year - 1)
        dateadd(
            month,
            cast(fiscal_month as integer) - 1,
            to_date(cast(fiscal_year - 1 as varchar) || '-09-01')
        )                                                  as report_month,

        -- measures
        cast(enrollment as float)                          as enrollment_avg,

        -- methodology documentation: critical for preventing bad joins
        'sfy_monthly_average'                              as count_methodology,

        /*
            is_preliminary: SFY2025 is the current fiscal year as of ingestion.
            Mid-year months may be revised in later releases.
        */
        case
            when cast(fiscal_year as integer) >= 2025 then true
            else false
        end                                                as is_preliminary,

        -- passthrough for lineage
        enrollment_type,

        -- audit
        current_timestamp()                                as dbt_loaded_at

    from source

)

select * from staged