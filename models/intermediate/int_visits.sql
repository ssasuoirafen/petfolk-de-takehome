-- Visit-level conformed model: every unique appointment, client ids remapped to
-- canonical. Six Completed appointments reference clients missing from the
-- export: client_id becomes NULL (flagged), the visit and its revenue stay.
select
    a.appointment_id,
    m.canonical_client_id as client_id,
    a.client_id as source_client_id,
    m.canonical_client_id is null as is_unknown_client,
    a.patient_id,
    p.species,
    a.location_id,
    a.appointment_type,
    a.scheduled_at,
    a.status,
    a.provider_id,
    a.invoice_total,
    a.created_at
from {{ ref('stg_appointments') }} as a
left join {{ ref('int_client_id_map') }} as m
    on a.client_id = m.client_id
left join {{ ref('stg_patients') }} as p
    on a.patient_id = p.patient_id
