-- PII helpers.
-- mask_pii: dynamic masking evaluated at query time. DuckDB has no roles, so the
-- "role" is a session variable: SET VARIABLE pii_role = '<unmask role>'.
-- Unset variable -> getvariable() returns NULL -> CASE falls through to the mask
-- (default-deny). In production this CASE body becomes a Snowflake masking policy.
{% macro mask_pii(column, kind='email') %}
    case
        when getvariable('pii_role') = '{{ var("pii_unmask_role", "unmask_pii_data") }}'
            then {{ column }}
        {% if kind == 'email' %}
        -- regexp_replace returns its input unchanged on no match, which would
        -- leak a malformed (no-@) value through the masked branch: guard it.
        when {{ column }} like '%@%'
            then regexp_replace({{ column }}, '^(.).*@', '\1***@')
        else '***'
        {% else %}
        else '*******' || right({{ column }}, 4)
        {% endif %}
    end
{% endmacro %}

{% macro normalize_email(column) %}
    lower(trim({{ column }}))
{% endmacro %}

-- Last 10 digits: collapses '+1XXXXXXXXXX' and 'XXXXXXXXXX' to the same key.
{% macro normalize_phone(column) %}
    right(regexp_replace({{ column }}, '[^0-9]', '', 'g'), 10)
{% endmacro %}

{% macro hash_pii(column) %}
    sha256({{ column }})
{% endmacro %}
