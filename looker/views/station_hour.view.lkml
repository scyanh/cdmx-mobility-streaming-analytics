view: station_hour {
  sql_table_name: `@{gcp_project}.mobility_gold.station_hour` ;;

  dimension: pk {
    primary_key: yes
    hidden: yes
    sql: CONCAT(${TABLE}.station_id, '|', CAST(${TABLE}.hour_start AS STRING)) ;;
  }
  dimension: station_id {
    type: string
    sql: ${TABLE}.station_id ;;
  }
  dimension: station_name {
    type: string
    sql: ${TABLE}.station_name ;;
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
  dimension_group: hour {
    label: "Hour (Mexico City)"
    type: time
    datatype: datetime
    timeframes: [raw, hour, date, week, day_of_week, hour_of_day]
    sql: ${TABLE}.hour_start_local ;;
  }
  dimension: day_type {
    type: string
    sql: IF(EXTRACT(DAYOFWEEK FROM ${TABLE}.hour_start_local) IN (1, 7), 'weekend', 'weekday') ;;
  }

  measure: observed_minutes {
    type: sum
    sql: ${TABLE}.observed_minutes ;;
  }
  measure: empty_minutes {
    type: sum
    sql: ${TABLE}.empty_minutes ;;
  }
  measure: full_minutes {
    type: sum
    sql: ${TABLE}.full_minutes ;;
  }
  measure: pct_time_empty {
    label: "% Time Empty"
    type: number
    sql: SAFE_DIVIDE(${empty_minutes}, ${observed_minutes}) ;;
    value_format_name: percent_1
  }
  measure: pct_time_full {
    label: "% Time Full"
    type: number
    sql: SAFE_DIVIDE(${full_minutes}, ${observed_minutes}) ;;
    value_format_name: percent_1
  }
  measure: departures {
    type: sum
    sql: ${TABLE}.departures ;;
  }
  measure: arrivals {
    type: sum
    sql: ${TABLE}.arrivals ;;
  }
  measure: rebalanced_bikes {
    description: "Bikes moved by rebalancing trucks (out plus in)"
    type: sum
    sql: ${TABLE}.rebalanced_out + ${TABLE}.rebalanced_in ;;
  }
}
