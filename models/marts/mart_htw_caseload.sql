{{
    config(
        materialized='table',
        description='Monthly Healthy Texas Women caseload trends. Includes month-over-month change and methodology flag. Draws from stg_htw_caseload.'
    )
}}

/*
    SOURCE: STAGING.stg_htw_caseload
    GRAIN: One row per report_month (138 months, Sep 2014 - Feb 2026)

    DERIVED METRICS:
      mom_change_caseload: month-over-month change in htw_caseload.
      mom_change_pct_caseload: percentage change month-over-month, div0 guarded.

    METHODOLOGY NOTE:
      count_methodology shifts from point_in_time_count to
      average_daily_caseload at Aug 2025, consistent with the methodology
      change applied to stg_enrollment_by_risk_group. mom_change and
      mom_change_pct will reflect noise at this boundary by design —
      use count_methodology to filter or annotate in downstream reporting.
*/

with staging as (

    select * from {{ ref('stg_htw_caseload') }}

),

mart as (

    select
        report_month,
        htw_caseload,
        count_methodology,

        htw_caseload
            - lag(htw_caseload)
                over (order by report_month)        as mom_change_caseload,

        div0(
            htw_caseload
                - lag(htw_caseload)
                    over (order by report_month),
            lag(htw_caseload)
                over (order by report_month)
        )                                           as mom_change_pct_caseload,

        current_timestamp()                         as dbt_loaded_at

    from staging

)

select * from mart