-- Data quality: implausible weights flagged, not dropped (P0107 has 0.0 kg).
{{ config(severity='warn') }}
select patient_id, species, weight_kg
from {{ ref('stg_patients') }}
where weight_kg is not null and (weight_kg <= 0 or weight_kg > 120)
