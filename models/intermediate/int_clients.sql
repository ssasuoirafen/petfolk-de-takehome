-- One row per real person: the canonical row's attributes.
with map as (
    select canonical_client_id, count(*) as n_source_ids
    from {{ ref('int_client_id_map') }}
    group by canonical_client_id
)

select
    c.client_id,
    c.first_name,
    c.last_name,
    c.email,
    c.phone,
    c.email_hash,
    c.phone_hash,
    c.location_id,
    c.created_at,
    map.n_source_ids
from {{ ref('stg_clients') }} as c
inner join map
    on c.client_id = map.canonical_client_id
