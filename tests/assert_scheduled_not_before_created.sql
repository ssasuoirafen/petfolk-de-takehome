-- Business rule: an appointment cannot be scheduled before it was created.
select appointment_id, scheduled_at, created_at
from {{ ref('stg_appointments') }}
where scheduled_at < created_at
