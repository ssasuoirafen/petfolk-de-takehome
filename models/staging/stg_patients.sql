-- 1:1 with patients_raw, typed. Weight outliers kept (flagged by a warn test);
-- nulls preserved.
select
    patient_id,
    client_id,
    species,
    breed,
    try_cast(date_of_birth as date) as date_of_birth,
    sex,
    try_cast(weight_kg as decimal(5, 1)) as weight_kg
from {{ ref('patients_raw') }}
