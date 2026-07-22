-- 1:1 with appointments_raw: typed, cleaned, exact-duplicate rows removed.
with deduped as (
    select *
    from {{ ref('appointments_raw') }}
    qualify row_number() over (
        partition by appointment_id
        -- every column as tiebreak: pick stays deterministic even if copies diverge
        order by created_at, scheduled_at, status, invoice_total,
            patient_id, client_id, location_id, appointment_type, provider_id
    ) = 1
)

select
    appointment_id,
    patient_id,
    client_id,
    location_id,
    appointment_type,
    -- four source formats; shapes are mutually exclusive, so coalesce is safe:
    -- ISO Z, ISO space, day-first dash (DD-MM-YYYY), US month-first slash with AM/PM
    coalesce(
        try_strptime(scheduled_at, '%Y-%m-%dT%H:%M:%SZ'),
        try_strptime(scheduled_at, '%Y-%m-%d %H:%M:%S'),
        try_strptime(scheduled_at, '%d-%m-%Y %H:%M'),
        try_strptime(scheduled_at, '%m/%d/%Y %I:%M %p')
    ) as scheduled_at,
    status,
    provider_id,
    try_cast(replace(replace(invoice_total, '$', ''), ',', '') as decimal(10, 2))
        as invoice_total,
    strptime(created_at, '%Y-%m-%dT%H:%M:%SZ') as created_at
from deduped
