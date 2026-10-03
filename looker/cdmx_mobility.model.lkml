# BigQuery connection created in Looker Admin > Connections, pointing at the gcp_project.
connection: "cdmx_mobility_bigquery"

include: "/views/*.view.lkml"
include: "/dashboards/*.dashboard.lookml"

datagroup: live {
  # station_status_live is a view over the stream; cache for at most a minute.
  max_cache_age: "1 minute"
}

datagroup: gold_build {
  # Gold tables change only when Dataform rebuilds them.
  sql_trigger: SELECT MAX(last_modified_time) FROM `@{gcp_project}.mobility_gold.__TABLES__` ;;
  max_cache_age: "2 hours"
}

explore: station_status_live {
  label: "Mobility Live"
  description: "Current state of every ECOBICI station, seconds behind the feed."
  persist_with: live
}

explore: station_hour {
  label: "Station Patterns"
  description: "Availability and trips per station and hour."
  persist_with: gold_build
}

explore: zone_hour {
  label: "Zone Patterns"
  description: "Availability and trips per colonia and hour."
  persist_with: gold_build
}

explore: zone_opportunity {
  label: "Tlanova Opportunity"
  description: "Typical week per colonia: where and when riders find no bike, with the trips that could not start."
  persist_with: gold_build
}
