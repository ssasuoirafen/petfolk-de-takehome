-- Business rule: every completed visit must have been invoiced.
select appointment_id
from {{ ref('stg_appointments') }}
where status = 'Completed' and invoice_total is null
