cube(`events`, {
  sql_table: `public.events`,

  data_source: `default`,

  joins: {},

  dimensions: {
    region: {
      sql: `region`,
      type: `string`,
    },

    device: {
      sql: `device`,
      type: `string`,
    },

    source: {
      sql: `source`,
      type: `string`,
    },

    campaign: {
      sql: `campaign`,
      type: `string`,
    },

    event_type: {
      sql: `event_type`,
      type: `string`,
    },

    plan: {
      sql: `plan`,
      type: `string`,
    },

    event_time: {
      sql: `event_time`,
      type: `time`,
    },
  },

  measures: {
    count: {
      type: `count`,
    },

    pv: {
      type: `count`,
    },

    uv: {
      sql: `user_id`,
      type: `count_distinct`,
    },

    revenue: {
      sql: `revenue`,
      type: `sum`,
    },

    avg_session: {
      sql: `session_duration_seconds`,
      type: `avg`,
    },

    signups: {
      sql: `CASE WHEN ${CUBE}.event_type = 'signup' THEN 1 ELSE 0 END`,
      type: `sum`,
    },

    purchases: {
      sql: `CASE WHEN ${CUBE}.event_type = 'purchase' THEN 1 ELSE 0 END`,
      type: `sum`,
    },

    upgrades: {
      sql: `CASE WHEN ${CUBE}.event_type = 'upgrade' THEN 1 ELSE 0 END`,
      type: `sum`,
    },
  },

  pre_aggregations: {
    // Pre-aggregation definitions go here.
    // Learn more in the documentation: https://cube.dev/docs/caching/pre-aggregations/getting-started
    dailyByRegion: {
      type: "rollup",
      measures: [events.pv, events.uv, events.revenue, events.avg_session],
      timeDimension: events.event_time,
      granularity: "day",
      dimensions: [events.region],
      partitionGranularity: "month",
      refreshKey: { every: "30 minutes" },
    },
    dailyByDevice: {
      type: "rollup",
      measures: [events.pv, events.uv, events.signups],
      timeDimension: events.event_time,
      granularity: "day",
      dimensions: [events.device],
      partitionGranularity: "month",
      refreshKey: { every: "30 minutes" },
    },
    dailyByCampaign: {
      type: "rollup",
      measures: [events.pv, events.uv, events.revenue, events.signups, events.purchases],
      timeDimension: events.event_time,
      granularity: "day",
      dimensions: [events.campaign],
      partitionGranularity: "month",
      refreshKey: { every: "30 minutes" },
    },
    dailyByEventType: {
      type: "rollup",
      measures: [events.pv, events.uv, events.revenue, events.signups, events.purchases, events.upgrades],
      timeDimension: events.event_time,
      granularity: "day",
      dimensions: [events.event_type],
      partitionGranularity: "month",
      refreshKey: { every: "30 minutes" },
    },
  },
});
