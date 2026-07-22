-- One row per completed visit. Null-status appointments are excluded: a visit
-- is only a visit once the source system marks it Completed (documented in
-- DECISIONS.md, including the one invoiced null-status row).
select
    appointment_id,
    client_id,
    is_unknown_client,
    patient_id,
    species,
    location_id,
    provider_id,
    appointment_type,
    scheduled_at,
    cast(date_trunc('month', scheduled_at) as date) as visit_month,
    invoice_total
from {{ ref('int_visits') }}
where status = 'Completed'
