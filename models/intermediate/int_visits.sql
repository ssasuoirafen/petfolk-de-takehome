-- Visit-level conformed model: every unique appointment, client ids remapped to
-- canonical. Six Completed appointments reference clients missing from the
-- export: client_id becomes NULL (flagged), the visit and its revenue stay.
select
    appointments.appointment_id,
    id_map.canonical_client_id as client_id,
    appointments.client_id as source_client_id,
    id_map.canonical_client_id is null as is_unknown_client,
    appointments.patient_id,
    patients.species,
    appointments.location_id,
    appointments.appointment_type,
    appointments.scheduled_at,
    appointments.status,
    appointments.provider_id,
    appointments.invoice_total,
    appointments.created_at
from {{ ref('stg_appointments') }} as appointments
left join {{ ref('int_client_id_map') }} as id_map
    on appointments.client_id = id_map.client_id
left join {{ ref('stg_patients') }} as patients
    on appointments.patient_id = patients.patient_id
