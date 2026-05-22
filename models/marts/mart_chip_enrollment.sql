{{
    config(
        materialized='table',
        description='Monthly CHIP enrollment trends including caseload, enrollment flows, and reconciliation variance. Draws from stg_chip_enrollment.'
    )
}}

/*
    SOURCE: STAGING.stg_chip_enrollment
    GRAIN: One row per report_month (138 months, Sep 2014 - Feb 2026)

    DERIVED METRICS:
      net_enrollment: new_enrollment minus disenrollment. Positive values
        indicate caseload growth, negative values indicate contraction.
      mom_change_caseload: month-over-month change in chip_caseload.
      mom_change_pct_caseload: percentage change month-over-month, div0 guarded.
      renewal_rate: renewals as share of caseload. Measures retention —
        higher values indicate members are successfully renewing coverage.
      disenrollment_rate: disenrollment as share of caseload. Measures churn.
      caseload_reconciliation_variance_pct: difference between reported
        caseload and implied caseload (prior_caseload + new_enrollment -
        disenrollment) as a share of reported caseload. Small variances
        are expected due to retroactive adjustments and administrative
        corrections within Texas's 24-month adjustment window. Large
        variances warrant investigation — historically coincide with
        COVID disruption (2020) and Medicaid unwinding (2021-2023).
*/

with staging as (

    select * from {{ ref('stg_chip_enrollment') }}

),

mart as (

    select
        report_month,
        chip_caseload,
        new_enrollment,
        renewals,
        disenrollment,

        new_enrollment - disenrollment              as net_enrollment,

        chip_caseload
            - lag(chip_caseload)
                over (order by report_month)        as mom_change_caseload,

        div0(
            chip_caseload
                - lag(chip_caseload)
                    over (order by report_month),
            lag(chip_caseload)
                over (order by report_month)
        )                                           as mom_change_pct_caseload,

        div0(renewals, chip_caseload)               as renewal_rate,

        div0(disenrollment, chip_caseload)          as disenrollment_rate,

        div0(
            chip_caseload - (
                lag(chip_caseload)
                    over (order by report_month)
                + new_enrollment - disenrollment
            ),
            chip_caseload
        )                                           as caseload_reconciliation_variance_pct,

        current_timestamp()                         as dbt_loaded_at

    from staging

)

select * from mart