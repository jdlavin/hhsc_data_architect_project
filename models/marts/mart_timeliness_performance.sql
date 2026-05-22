{{
    config(
        materialized='table',
        description='Monthly Medicaid application and redetermination timeliness performance by region and processing unit. Includes month-over-month trends and rolling averages. Draws from stg_timeliness_medicaid.'
    )
}}

/*
    SOURCE: STAGING.stg_timeliness_medicaid
    GRAIN: One row per record_type per region per report_month
    DATE RANGE: 24-month rolling window

    REGIONS:
      Geographic regions 01-11 (is_geographic_region = true):
        HHSC divides Texas into 11 service regions for field office operations.
        Region 02/09 represents two regions reported together.
      Processing units (is_geographic_region = false):
        MEPD     - Medicaid for the Elderly and People with Disabilities,
                   specialized unit with 90-day processing window
        CCC      - Community Care Centralized processing unit
        DATA INT - Data Integration, automated/batch eligibility determinations
        PERFORMANC - Performance monitoring unit (truncated in source)
        ST OFFICE  - State Office centralized processing
        VIC        - Voice Intake Center, phone-based application processing
        UNKNOWN    - Unclassified processing unit

    RECORD TYPES:
      applications     - new Medicaid applications, 45-day federal standard
      redeterminations - eligibility renewals

    DERIVED METRICS:
      pct_timely: recalculated from timely / disposed for auditability.
      src_percent: original HHSC-calculated figure retained for comparison.
      pct_timely_variance: difference between recalculated and source figures,
        flags rounding or methodology discrepancies.
      mom_change_pct_timely: month-over-month change in pct_timely per
        region and record type.
      rolling_3m_pct_timely: 3-month rolling average of pct_timely,
        smooths noise for trend analysis.
*/

with staging as (

    select * from {{ ref('stg_timeliness_medicaid') }}

),

mart as (

    select
        report_month,
        region,
        is_geographic_region,
        record_type,
        disposed,
        timely,
        untimely,

        div0(timely, disposed)                  as pct_timely,

        src_percent,

        div0(timely, disposed) - src_percent    as pct_timely_variance,

        div0(timely, disposed)
            - lag(div0(timely, disposed))
                over (
                    partition by region, record_type
                    order by report_month
                )                               as mom_change_pct_timely,

        avg(div0(timely, disposed))
            over (
                partition by region, record_type
                order by report_month
                rows between 2 preceding and current row
            )                                   as rolling_3m_pct_timely,

        current_timestamp()                     as dbt_loaded_at

    from staging

)

select * from mart