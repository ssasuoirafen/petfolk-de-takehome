-- The metric must be unique per (location_id, visit_month).
select location_id, visit_month, count(*) as n
from {{ ref('metric_revenue_per_visit') }}
group by location_id, visit_month
having count(*) > 1
