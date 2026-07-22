-- 1:1 with clients_raw. Raw email/phone never leave this layer unmasked:
-- masked columns for display, sha256 hashes of normalized values as identity keys.
select
    client_id,
    first_name,
    last_name,
    {{ mask_pii(normalize_email('email'), 'email') }} as email,
    {{ mask_pii('phone', 'phone') }} as phone,
    {{ hash_pii(normalize_email('email')) }} as email_hash,
    {{ hash_pii(normalize_phone('phone')) }} as phone_hash,
    location_id,
    strptime(created_at, '%Y-%m-%dT%H:%M:%SZ') as created_at
from {{ ref('clients_raw') }}
