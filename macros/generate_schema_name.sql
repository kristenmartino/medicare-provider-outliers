{# ---------------------------------------------------------------------------
   Custom schema resolution.

   dbt's default generate_schema_name prefixes the target schema onto every
   custom schema (target.schema = "dbt_dev"  ->  DBT_DEV_STAGING etc.). This
   project instead uses the per-layer `+schema:` values from dbt_project.yml
   verbatim, so the warehouse reads cleanly:

       ANALYTICS.STAGING        (staging views)
       ANALYTICS.INTERMEDIATE   (intermediate tables)
       ANALYTICS.MARTS          (dim / facts / mart_provider_outliers)
       ANALYTICS.SEEDS          (nucc_taxonomy)

   Models without an explicit `+schema:` fall back to the target's default
   schema (the personal sandbox configured in profiles.yml).
   --------------------------------------------------------------------------- #}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema | trim }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
