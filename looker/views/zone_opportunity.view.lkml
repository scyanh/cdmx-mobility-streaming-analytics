view: zone_opportunity {
  sql_table_name: `@{gcp_project}.mobility_gold.zone_opportunity` ;;

  dimension: pk {
    primary_key: yes
    hidden: yes
    sql: CONCAT(${TABLE}.colonia_id, '|', ${TABLE}.day_type, '|', CAST(${TABLE}.hour_of_day AS STRING)) ;;
  }
  dimension: colonia {
    type: string
    sql: ${TABLE}.colonia ;;
  }
  dimension: alcaldia {
    label: "Alcaldía"
    type: string
    sql: ${TABLE}.alcaldia ;;
  }
  dimension: day_type {
    type: string
    sql: ${TABLE}.day_type ;;
  }
  dimension: hour_of_day {
    type: number
    sql: ${TABLE}.hour_of_day ;;
  }
  dimension: days_observed {
    type: number
    sql: ${TABLE}.days_observed ;;
  }
  dimension: confidence {
    description: "'low' when fewer than 3 days back the estimate"
    type: string
    sql: ${TABLE}.confidence ;;
  }
  dimension: opportunity_rank {
    type: number
    sql: ${TABLE}.opportunity_rank ;;
  }
  dimension: rank_in_hour {
    type: number
    sql: ${TABLE}.rank_in_hour ;;
  }

  measure: est_unmet_trips {
    label: "Est. Unmet Trips"
    description: "Trips that could not start because the station was empty (sum over the selected hours of trips per hour)"
    type: sum
    sql: ${TABLE}.est_unmet_departures_per_hour ;;
    value_format_name: decimal_1
  }
  measure: est_blocked_returns {
    label: "Est. Blocked Returns"
    type: sum
    sql: ${TABLE}.est_blocked_returns_per_hour ;;
    value_format_name: decimal_1
  }
  measure: departures {
    label: "Departures (typical day)"
    type: sum
    sql: ${TABLE}.departures_per_hour ;;
    value_format_name: decimal_1
  }
  measure: pct_time_empty {
    label: "% Time Empty (mean of hours)"
    type: average
    sql: ${TABLE}.pct_time_empty ;;
    value_format_name: percent_1
  }
  measure: unmet_share {
    label: "Unmet Share of Demand"
    description: "Unmet trips over unmet plus completed departures"
    type: number
    sql: SAFE_DIVIDE(${est_unmet_trips}, ${est_unmet_trips} + ${departures}) ;;
    value_format_name: percent_1
  }
}
