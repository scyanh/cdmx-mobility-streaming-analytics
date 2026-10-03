- dashboard: tlanova_opportunity
  title: Tlanova Opportunity
  description: "Where and when riders find no ECOBICI bike: the trips that could not start, by colonia and hour of a typical week. Candidate zones and hours for Tlanova rides and couriers."
  layout: newspaper
  preferred_viewer: dashboards-next
  filters:
  - name: day_type
    title: Day type
    type: field_filter
    default_value: weekday
    allow_multiple_values: false
    model: cdmx_mobility
    explore: zone_opportunity
    field: zone_opportunity.day_type
  - name: confidence
    title: Confidence
    type: field_filter
    default_value: ""
    allow_multiple_values: true
    model: cdmx_mobility
    explore: zone_opportunity
    field: zone_opportunity.confidence
  elements:
  - name: unmet_total
    title: Est. unmet trips per day
    note_text: "Departure rate while the station had bikes, times the minutes it was empty."
    model: cdmx_mobility
    explore: zone_opportunity
    type: single_value
    fields: [zone_opportunity.est_unmet_trips]
    listen: {day_type: zone_opportunity.day_type, confidence: zone_opportunity.confidence}
    row: 0
    col: 0
    width: 8
    height: 3
  - name: unmet_share
    title: Share of demand left unmet
    model: cdmx_mobility
    explore: zone_opportunity
    type: single_value
    fields: [zone_opportunity.unmet_share]
    listen: {day_type: zone_opportunity.day_type, confidence: zone_opportunity.confidence}
    row: 0
    col: 8
    width: 8
    height: 3
  - name: blocked_returns
    title: Est. blocked returns per day
    model: cdmx_mobility
    explore: zone_opportunity
    type: single_value
    fields: [zone_opportunity.est_blocked_returns]
    listen: {day_type: zone_opportunity.day_type, confidence: zone_opportunity.confidence}
    row: 0
    col: 16
    width: 8
    height: 3
  - name: unmet_by_hour
    title: Unmet trips by hour of day
    model: cdmx_mobility
    explore: zone_opportunity
    type: looker_column
    fields: [zone_opportunity.hour_of_day, zone_opportunity.est_unmet_trips, zone_opportunity.departures]
    sorts: [zone_opportunity.hour_of_day]
    listen: {day_type: zone_opportunity.day_type, confidence: zone_opportunity.confidence}
    row: 3
    col: 0
    width: 12
    height: 7
  - name: top_colonias
    title: Colonias with the most unmet trips
    model: cdmx_mobility
    explore: zone_opportunity
    type: looker_bar
    fields: [zone_opportunity.colonia, zone_opportunity.est_unmet_trips]
    sorts: [zone_opportunity.est_unmet_trips desc]
    limit: 15
    listen: {day_type: zone_opportunity.day_type, confidence: zone_opportunity.confidence}
    row: 3
    col: 12
    width: 12
    height: 7
  - name: opportunity_ranking
    title: Best colonia and hour slots
    model: cdmx_mobility
    explore: zone_opportunity
    type: looker_grid
    fields: [zone_opportunity.opportunity_rank, zone_opportunity.colonia, zone_opportunity.alcaldia, zone_opportunity.hour_of_day,
      zone_opportunity.est_unmet_trips, zone_opportunity.pct_time_empty, zone_opportunity.departures, zone_opportunity.days_observed,
      zone_opportunity.confidence]
    sorts: [zone_opportunity.est_unmet_trips desc]
    limit: 50
    listen: {day_type: zone_opportunity.day_type, confidence: zone_opportunity.confidence}
    row: 10
    col: 0
    width: 24
    height: 10
