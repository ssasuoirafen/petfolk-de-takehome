-- Governed metric: revenue per completed visit, by pet care center and month.
-- Numerator and denominator share one definition of "visit" via fct_visits.
select
    location_id,
    visit_month,
    count(*) as visits,
    sum(invoice_total) as revenue,
    -- DuckDB's "/" on decimals returns DOUBLE; cast pins the BI-facing type.
    -- Residual float display-rounding is documented in DECISIONS.md.
    cast(round(sum(invoice_total) / count(*), 2) as decimal(10, 2)) as revenue_per_visit
from {{ ref('fct_visits') }}
group by location_id, visit_month
