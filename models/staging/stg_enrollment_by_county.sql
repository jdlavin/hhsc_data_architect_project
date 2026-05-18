{{
    config(
        materialized='view',
        description='Staged monthly Medicaid enrollment by Texas county. Casts types, standardizes names, and documents count methodology. Does not aggregate.'
    )
}}

/*
    SOURCE: HHSC_RAW.RAW.ENROLLMENT_BY_COUNTY
    GRAIN: One row per county per report_month (5,355 rows, 255 counties)
    LOADED FROM: 21 monthly release files, loop-unioned in ingestion layer.
    MISSING: Nov 2025 and Dec 2025 files not yet published by HHSC as of ingestion.

    COUNT METHODOLOGY NOTE:
    County counts use a point-in-time (end-of-month snapshot) methodology.
    This WILL NOT reconcile with stg_enrollment_by_risk_group, which uses an
    ever-enrolled (unduplicated) methodology. This is expected and by design per
    HHSC reporting practice. Do not attempt to reconcile these two tables.
    See count_methodology column.

    PRELIMINARY DATA NOTE:
    The county file bridging Sep 2025-Feb 2026 is a preliminary release.
    TX policy allows 24-month retroactive adjustments, so the same month will
    look different across different snapshot vintages. is_preliminary=true rows
    should be treated as estimates subject to revision.
*/

with source as (

    select * from {{ source('hhsc_raw', 'enrollment_by_county') }}

),

staged as (

    select
        -- keys
        cast(report_date as date)                          as report_month,
        trim(upper(county_name))                           as county_name,
        cast(county_code as varchar(10))                   as county_code,

        -- measures
        cast(enrollment as integer)                        as enrollment_count,

        -- methodology documentation
        'point_in_time_end_of_month'                       as count_methodology,

        /*
            Preliminary flag: covers Sep 2025-Feb 2026 gap file.
            TX has a 24-month retroactive adjustment window so these counts
            will be revised. Not a data quality issue -- do not alert on drift
            between vintages for is_preliminary=true rows.
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
