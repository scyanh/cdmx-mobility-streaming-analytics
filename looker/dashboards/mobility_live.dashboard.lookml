- dashboard: mobility_live
  title: Mobility Live
  description: "ECOBICI right now: bikes and docks available, empty and full stations, seconds behind the feed."
  layout: newspaper
  preferred_viewer: dashboards-next
  refresh: 1 minute
  filters:
  - name: alcaldia
    title: Alcaldía
    type: field_filter
    default_value: ""
    allow_multiple_values: true
    model: cdmx_mobility
    explore: station_status_live
    field: station_status_live.alcaldia
  elements:
  - name: bikes_available
    title: Bikes available
    model: cdmx_mobility
    explore: station_status_live
    type: single_value
    fields: [station_status_live.total_bikes_available]
    listen: {alcaldia: station_status_live.alcaldia}
    row: 0
    col: 0
    width: 5
    height: 3
  - name: docks_available
    title: Free docks
    model: cdmx_mobility
    explore: station_status_live
    type: single_value
    fields: [station_status_live.total_docks_available]
    listen: {alcaldia: station_status_live.alcaldia}
    row: 0
    col: 5
    width: 5
    height: 3
  - name: empty_stations
    title: Empty stations
    model: cdmx_mobility
    explore: station_status_live
    type: single_value
    fields: [station_status_live.empty_stations, station_status_live.pct_stations_empty]
    listen: {alcaldia: station_status_live.alcaldia}
    row: 0
    col: 10
    width: 5
    height: 3
  - name: full_stations
    title: Full stations
    model: cdmx_mobility
    explore: station_status_live
    type: single_value
    fields: [station_status_live.full_stations]
    listen: {alcaldia: station_status_live.alcaldia}
    row: 0
    col: 15
    width: 4
    height: 3
  - name: last_update
    title: Last poll
    model: cdmx_mobility
    explore: station_status_live
    type: single_value
    fields: [station_status_live.last_polled]
    row: 0
    col: 19
    width: 5
    height: 3
  - name: station_map
    title: Stations by status
    model: cdmx_mobility
    explore: station_status_live
    type: looker_map
    fields: [station_status_live.location, station_status_live.status, station_status_live.station_name, station_status_live.total_bikes_available]
    sorts: [station_status_live.total_bikes_available desc]
    limit: 1000
    map_plot_mode: points
    map_tile_provider: light
    map_position: custom
    map_latitude: 19.405
    map_longitude: -99.170
    map_zoom: 13
    listen: {alcaldia: station_status_live.alcaldia}
    row: 3
    col: 0
    width: 15
    height: 12
  - name: status_breakdown
    title: Stations by status
    model: cdmx_mobility
    explore: station_status_live
    type: looker_bar
    fields: [station_status_live.status, station_status_live.stations]
    sorts: [station_status_live.stations desc]
    listen: {alcaldia: station_status_live.alcaldia}
    row: 3
    col: 15
    width: 9
    height: 5
  - name: colonias_empty_now
    title: Colonias with the most empty stations now
    model: cdmx_mobility
    explore: station_status_live
    type: looker_grid
    fields: [station_status_live.colonia, station_status_live.alcaldia, station_status_live.empty_stations,
      station_status_live.online_stations, station_status_live.pct_stations_empty, station_status_live.total_bikes_available]
    sorts: [station_status_live.empty_stations desc]
    limit: 15
    listen: {alcaldia: station_status_live.alcaldia}
    row: 8
    col: 15
    width: 9
    height: 7
