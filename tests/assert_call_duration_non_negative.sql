-- Business rule: call duration cannot be negative (null = unknown, allowed).
select contact_id, duration_seconds
from {{ ref('stg_gladly_calls') }}
where duration_seconds < 0
