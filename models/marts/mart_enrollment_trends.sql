{{
    config(
        materialized='table',
        description='Monthly Medicaid enrollment trends by risk group. Includes month-over-month change and share of total enrollment. Draws from stg_enrollment_by_risk_group.'
    )
}}

/*
    SOURCE: STAGING.stg_enrollment_by_risk_group
    GRAIN: One row per risk_group per report_month (138 months x 10 risk groups = 1,380 rows)
    DATE RANGE: Sep 2014 - Feb 2026

    DERIVED METRICS:
      - mom_change: month-over-month enrollment change per risk group
      - mom_change_pct: percentage change month-over-month per risk group
      - pct_of_total: share of total enrollment using caseload_by_risk_group
        denominator only (6 mutually exclusive groups) to avoid double-counting

    METHODOLOGY NOTE:
      count_methodology flags the boundary where HHSC shifted from
      point_in_time_count to average_daily_enrollment (Aug 2025 for most
      groups, Sep 2025 for medicaid_clients_under_21). mom_change and
      mom_change_pct will reflect noise at this boundary by design —
      use count_methodology to filter or annotate in downstream reporting.
*/

with staging as (

    select * from {{ ref('stg_enrollment_by_risk_group') }}

),

monthly_totals as (

    select
        report_month,
        sum(enrollment_count)           as total_enrollment
    from staging
    where risk_group_category = 'caseload_by_risk_group'
    group by report_month

),

mart as (

    select
        s.report_month,
        s.risk_group,
        s.risk_group_category,
        s.enrollment_count,
        s.count_methodology,

        s.enrollment_count
            - lag(s.enrollment_count)
                over (
                    partition by s.risk_group
                    order by s.report_month
                )                       as mom_change,

        div0(
            s.enrollment_count
                - lag(s.enrollment_count)
                    over (
                        partition by s.risk_group
                        order by s.report_month
                    ),
            lag(s.enrollment_count)
                over (
                    partition by s.risk_group
                    order by s.report_month
                )
        )                               as mom_change_pct,

        div0(
            s.enrollment_count,
            m.total_enrollment
        )                               as pct_of_total,

        current_timestamp()             as dbt_loaded_at

    from staging s
    left join monthly_totals m
        on s.report_month = m.report_month

)

select * from mart