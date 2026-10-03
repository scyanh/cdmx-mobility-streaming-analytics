- dashboard: patterns_historical
  title: Patterns Historical
  description: "How ECOBICI moves by hour and day: trips, empty and full stations, rebalancing, by colonia."
  layout: newspaper
  preferred_viewer: dashboards-next
  filters:
  - name: date_range
    title: Date
    type: field_filter
    default_value: "28 days"
    allow_multiple_values: true
    model: cdmx_mobility
    explore: zone_hour
    field: zone_hour.hour_date
  - name: alcaldia
    title: Alcaldía
    type: field_filter
    default_value: ""
    allow_multiple_values: true
    model: cdmx_mobility
    explore: zone_hour
    field: zone_hour.alcaldia
  elements:
  - name: trips_by_hour
    title: Departures per hour
    model: cdmx_mobility
    explore: zone_hour
    type: looker_line
    fields: [zone_hour.hour_hour, zone_hour.departures, zone_hour.arrivals]
    sorts: [zone_hour.hour_hour]
    limit: 5000
    listen: {date_range: zone_hour.hour_date, alcaldia: zone_hour.alcaldia}
    row: 0
    col: 0
    width: 24
    height: 7
  - name: empty_heatmap
    title: "% of time stations are empty, by weekday and hour"
    model: cdmx_mobility
    explore: zone_hour
    type: looker_grid
    fields: [zone_hour.hour_hour_of_day, zone_hour.hour_day_of_week, zone_hour.pct_time_empty]
    pivots: [zone_hour.hour_day_of_week]
    sorts: [zone_hour.hour_hour_of_day, zone_hour.hour_day_of_week]
    limit: 500
    conditional_formatting:
    - type: along a scale...
      value:
      background_color:
      font_color:
      color_application: {collection_id: legacy, palette_id: legacy_sequential3}
      bold: false
      italic: false
      strikethrough: false
      fields: [zone_hour.pct_time_empty]
    listen: {date_range: zone_hour.hour_date, alcaldia: zone_hour.alcaldia}
    row: 7
    col: 0
    width: 12
    height: 12
  - name: weekday_vs_weekend
    title: Typical departures by hour, weekday vs weekend
    model: cdmx_mobility
    explore: station_hour
    type: looker_line
    fields: [station_hour.hour_hour_of_day, station_hour.day_type, station_hour.departures]
    pivots: [station_hour.day_type]
    sorts: [station_hour.hour_hour_of_day]
    listen: {date_range: station_hour.hour_date, alcaldia: station_hour.alcaldia}
    row: 7
    col: 12
    width: 12
    height: 6
  - name: empty_vs_full
    title: Empty and full station time by day
    model: cdmx_mobility
    explore: zone_hour
    type: looker_column
    fields: [zone_hour.hour_date, zone_hour.pct_time_empty, zone_hour.pct_time_full]
    sorts: [zone_hour.hour_date]
    listen: {date_range: zone_hour.hour_date, alcaldia: zone_hour.alcaldia}
    row: 13
    col: 12
    width: 12
    height: 6
  - name: colonia_flows
    title: Colonias that drain or fill with bikes
    model: cdmx_mobility
    explore: zone_hour
    type: looker_grid
    fields: [zone_hour.colonia, zone_hour.alcaldia, zone_hour.departures, zone_hour.arrivals, zone_hour.net_flow,
      zone_hour.pct_time_empty, zone_hour.pct_time_full]
    sorts: [zone_hour.departures desc]
    limit: 25
    listen: {date_range: zone_hour.hour_date, alcaldia: zone_hour.alcaldia}
    row: 19
    col: 0
    width: 14
    height: 8
  - name: busiest_stations
    title: Busiest stations
    model: cdmx_mobility
    explore: station_hour
    type: looker_bar
    fields: [station_hour.station_name, station_hour.departures, station_hour.rebalanced_bikes]
    sorts: [station_hour.departures desc]
    limit: 15
    listen: {date_range: station_hour.hour_date, alcaldia: station_hour.alcaldia}
    row: 19
    col: 14
    width: 10
    height: 8
