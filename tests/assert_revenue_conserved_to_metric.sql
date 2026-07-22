-- Reconciliation: the metric must carry exactly the revenue of fct_visits.
with fct as (
    select sum(invoice_total) as total_revenue from {{ ref('fct_visits') }}
),

metric as (
    select sum(revenue) as total_revenue from {{ ref('metric_revenue_per_visit') }}
)

select fct.total_revenue as fct_revenue, metric.total_revenue as metric_revenue
from fct
cross join metric
where fct.total_revenue <> metric.total_revenue
