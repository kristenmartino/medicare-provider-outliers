{# ---------------------------------------------------------------------------
   Outlier-detection helpers.
   Documented in macros/_macros.yml (descriptions, arg lists).
   --------------------------------------------------------------------------- #}


{# zscore: classical z-score, (value - mean) / stddev. Null when stddev is 0. #}
{% macro zscore(value, mean, stddev) %}
    case when {{ stddev }} > 0
         then ({{ value }} - {{ mean }}) / {{ stddev }}
    end
{% endmacro %}


{# modified_zscore: MAD-based z-score, robust to right-skewed distributions.
   Returns 0.6745 * (value - median) / mad, or NULL when mad is 0.
   See docs/methodology.md for the math + thresholds. #}
{% macro modified_zscore(value, median, mad, mad_constant=0.6745) %}
    case when {{ mad }} > 0
         then {{ mad_constant }} * ({{ value }} - {{ median }}) / {{ mad }}
    end
{% endmacro %}


{# is_outlier: true when |score| >= threshold. NULL scores → NULL flag. #}
{% macro is_outlier(score, threshold) %}
    abs({{ score }}) >= {{ threshold }}
{% endmacro %}
