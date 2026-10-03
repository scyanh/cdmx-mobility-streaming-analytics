view: zone_hour {
  sql_table_name: `@{gcp_project}.mobility_gold.zone_hour` ;;

  dimension: pk {
    primary_key: yes
    hidden: yes
    sql: CONCAT(${TABLE}.colonia_id, '|', CAST(${TABLE}.hour_start AS STRING)) ;;
  }
  dimension: colonia_id {
    hidden: yes
    type: string
    sql: ${TABLE}.colonia_id ;;
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

  measure: observed_station_minutes {
    type: sum
    sql: ${TABLE}.observed_station_minutes ;;
  }
  measure: empty_station_minutes {
    type: sum
    sql: ${TABLE}.empty_station_minutes ;;
  }
  measure: full_station_minutes {
    type: sum
    sql: ${TABLE}.full_station_minutes ;;
  }
  measure: pct_time_empty {
    label: "% Time Empty"
    type: number
    sql: SAFE_DIVIDE(${empty_station_minutes}, ${observed_station_minutes}) ;;
    value_format_name: percent_1
  }
  measure: pct_time_full {
    label: "% Time Full"
    type: number
    sql: SAFE_DIVIDE(${full_station_minutes}, ${observed_station_minutes}) ;;
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
  measure: net_flow {
    description: "Arrivals minus departures; negative means the colonia drains bikes"
    type: number
    sql: ${arrivals} - ${departures} ;;
  }
  measure: avg_bikes_available {
    type: average
    sql: ${TABLE}.avg_bikes_available ;;
    value_format_name: decimal_1
  }
}
