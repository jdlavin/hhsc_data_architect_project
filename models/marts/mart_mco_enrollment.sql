{{
    config(
        materialized='table',
        description='SFY2025 MCO enrollment averages by service delivery area and program. Includes MCO market share within SDA and program. Draws from stg_mco_enrollment_by_sda.'
    )
}}

/*
    SOURCE: STAGING.stg_mco_enrollment_by_sda
    GRAIN: One row per mco_name x program x sub_program x sda
    ROWS: 205 (not all MCOs operate in all SDAs — sparse coverage expected)
    FISCAL YEAR: SFY2025 only — no monthly breakdown available

    ENROLLMENT TYPE: sfy_monthly_average throughout — no methodology variation.

    DERIVED METRICS:
      mco_share_of_sda: MCO enrollment as a share of total enrollment for
        that program/sub_program/sda combination. Denominator is the sum
        of all MCOs operating in that SDA for that program. Values of 100%
        are valid and expected where only one MCO operates in a given
        SDA/program combination — this reflects sparse MCO coverage in
        smaller or rural SDAs, not a data quality issue.
      mco_share_of_program: MCO enrollment as a share of total statewide
        enrollment for that program/sub_program. Measures each MCO's
        overall market share within a program regardless of geography.
*/

with staging as (

    select * from {{ ref('stg_mco_enrollment_by_sda') }}

),

sda_totals as (

    select
        program,
        sub_program,
        sda,
        sum(enrollment_avg)             as total_sda_enrollment
    from staging
    group by program, sub_program, sda

),

program_totals as (

    select
        program,
        sub_program,
        sum(enrollment_avg)             as total_program_enrollment
    from staging
    group by program, sub_program

),

mart as (

    select
        s.fiscal_year,
        s.mco_name,
        s.program,
        s.sub_program,
        s.sda,
        s.enrollment_avg,
        s.enrollment_type,

        div0(
            s.enrollment_avg,
            sd.total_sda_enrollment
        )                               as mco_share_of_sda,

        div0(
            s.enrollment_avg,
            p.total_program_enrollment
        )                               as mco_share_of_program,

        current_timestamp()             as dbt_loaded_at

    from staging s
    left join sda_totals sd
        on s.program = sd.program
        and s.sub_program = sd.sub_program
        and s.sda = sd.sda
    left join program_totals p
        on s.program = p.program
        and s.sub_program = p.sub_program

)

select * from mart