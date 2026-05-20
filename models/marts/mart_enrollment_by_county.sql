{{
    config(
        materialized='table',
        description='Monthly Medicaid enrollment by Texas county and risk group. Includes month-over-month change and share of county and state totals. Draws from stg_enrollment_by_county.'
    )
}}

/*
    SOURCE: STAGING.stg_enrollment_by_county
    GRAIN: One row per risk_group per county per report_month
           (21 months x 255 counties x 8 risk groups = 42,840 rows)
    DATE RANGE: Jan 2024 - Sep 2025

    DERIVED METRICS:
      - mom_change: month-over-month enrollment change per risk_group per county
      - mom_change_pct: percentage change month-over-month, div0 guarded
      - pct_of_county_total: risk_group share within county that month.
        Denominator uses caseload_by_risk_group only to avoid double-counting.
      - pct_of_state_total: county share of statewide enrollment for that
        risk_group and month. Unknown county (255) included in both numerator
        and denominator. Use is_unknown_county to filter in downstream reporting.

    METHODOLOGY NOTE:
      count_methodology is point_in_time_count throughout -- no methodology
      shift in county data. mom_change will not exhibit methodology boundary
      noise unlike mart_enrollment_trends.
*/

with staging as (

    select * from {{ ref('stg_enrollment_by_county') }}

),

county_totals as (

    select
        report_month,
        county_code,
        sum(enrollment_count)           as total_county_enrollment
    from staging
    where risk_group_category = 'caseload_by_risk_group'
    group by report_month, county_code

),

state_totals as (

    select
        report_month,
        risk_group,
        sum(enrollment_count)           as total_state_enrollment
    from staging
    group by report_month, risk_group

),

mart as (

    select
        s.report_month,
        s.county_code,
        s.county_name,
        s.is_unknown_county,
        s.risk_group,
        s.risk_group_category,
        s.enrollment_count,
        s.count_methodology,

        s.enrollment_count
            - lag(s.enrollment_count)
                over (
                    partition by s.risk_group, s.county_code
                    order by s.report_month
                )                       as mom_change,

        div0(
            s.enrollment_count
                - lag(s.enrollment_count)
                    over (
                        partition by s.risk_group, s.county_code
                        order by s.report_month
                    ),
            lag(s.enrollment_count)
                over (
                    partition by s.risk_group, s.county_code
                    order by s.report_month
                )
        )                               as mom_change_pct,

        div0(
            s.enrollment_count,
            ct.total_county_enrollment
        )                               as pct_of_county_total,

        div0(
            s.enrollment_count,
            st.total_state_enrollment
        )                               as pct_of_state_total,

        current_timestamp()             as dbt_loaded_at

    from staging s
    left join county_totals ct
        on s.report_month = ct.report_month
        and s.county_code = ct.county_code
    left join state_totals st
        on s.report_month = st.report_month
        and s.risk_group = st.risk_group

)

select * from mart