-- 1:1 with the generated gladly_calls seed. customer_phone is pet-parent PII:
-- masked for display, hashed for identity. Missing durations stay NULL.
select
    conversation_id,
    contact_id,
    {{ mask_pii('customer_phone', 'phone') }} as customer_phone,
    {{ hash_pii(normalize_phone('customer_phone')) }} as customer_phone_hash,
    agent_id,
    strptime(started_at, '%Y-%m-%dT%H:%M:%SZ') as started_at,
    try_cast(duration_seconds as integer) as duration_seconds
from {{ ref('gladly_calls') }}
