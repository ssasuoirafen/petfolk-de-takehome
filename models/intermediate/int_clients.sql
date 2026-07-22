-- One row per real person: the canonical row's attributes.
with map as (
    select canonical_client_id, count(*) as n_source_ids
    from {{ ref('int_client_id_map') }}
    group by canonical_client_id
)

select
    clients.client_id,
    clients.first_name,
    clients.last_name,
    clients.email,
    clients.phone,
    clients.email_hash,
    clients.phone_hash,
    clients.location_id,
    clients.created_at,
    map.n_source_ids
from {{ ref('stg_clients') }} as clients
inner join map
    on clients.client_id = map.canonical_client_id
