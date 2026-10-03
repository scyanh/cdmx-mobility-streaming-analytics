view: station_status_live {
  sql_table_name: `@{gcp_project}.mobility_gold.station_status_live` ;;

  dimension: station_id {
    primary_key: yes
    type: string
    sql: ${TABLE}.station_id ;;
  }
  dimension: station_name {
    type: string
    sql: ${TABLE}.station_name ;;
  }
  dimension: station_code {
    type: string
    sql: ${TABLE}.station_code ;;
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
  dimension: location {
    type: location
    sql_latitude: ${TABLE}.lat ;;
    sql_longitude: ${TABLE}.lon ;;
  }
  dimension: capacity {
    type: number
    sql: ${TABLE}.capacity ;;
  }
  dimension: status {
    description: "ok, low (2 bikes or fewer), empty, full, not renting, or offline (no report in the last hour)"
    type: string
    sql: ${TABLE}.status ;;
    html: {% if value == 'empty' %}<span style="color:#b3261e">{{ value }}</span>
          {% elsif value == 'full' %}<span style="color:#7d5700">{{ value }}</span>
          {% else %}{{ value }}{% endif %} ;;
  }
  dimension_group: reported {
    type: time
    timeframes: [raw, time, minute]
    sql: ${TABLE}.reported_at ;;
  }
  dimension: report_age_minutes {
    type: number
    sql: ${TABLE}.report_age_seconds / 60 ;;
    value_format_name: decimal_0
  }
  dimension: bikes_available {
    type: number
    sql: ${TABLE}.num_bikes_available ;;
  }
  dimension: docks_available {
    type: number
    sql: ${TABLE}.num_docks_available ;;
  }

  measure: stations {
    type: count
  }
  measure: total_bikes_available {
    type: sum
    sql: ${bikes_available} ;;
    filters: [status: "-offline"]
  }
  measure: total_docks_available {
    type: sum
    sql: ${docks_available} ;;
    filters: [status: "-offline"]
  }
  measure: empty_stations {
    type: count
    filters: [status: "empty"]
  }
  measure: full_stations {
    type: count
    filters: [status: "full"]
  }
  measure: offline_stations {
    type: count
    filters: [status: "offline"]
  }
  measure: online_stations {
    type: count
    filters: [status: "-offline"]
  }
  measure: pct_stations_empty {
    label: "% Stations Empty"
    type: number
    sql: SAFE_DIVIDE(${empty_stations}, ${online_stations}) ;;
    value_format_name: percent_1
  }
  measure: last_polled {
    type: date_time
    sql: MAX(${TABLE}.polled_at) ;;
  }
}
