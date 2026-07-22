-- Kept as a VIEW on purpose: email/phone are masked dynamically per session;
-- a table would freeze whichever mask state existed at build time.
{{ config(materialized='view') }}

select
    client_id,
    first_name,
    last_name,
    email,
    phone,
    email_hash,
    phone_hash,
    location_id,
    created_at,
    n_source_ids
from {{ ref('int_clients') }}
