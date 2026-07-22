-- Same person can appear under several client_ids. Cluster on the hash of the
-- normalized email (names collide across distinct people; normalized phone
-- produces the same 6 pairs and stays available as a cross-check).
-- Canonical id = lowest client_id in the cluster (created_at ties in all pairs).
select
    client_id,
    min(client_id) over (partition by email_hash) as canonical_client_id
from {{ ref('stg_clients') }}
