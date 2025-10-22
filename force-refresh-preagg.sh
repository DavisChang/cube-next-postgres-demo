#!/bin/bash

# Force Refresh Pre-Aggregations
# Use when you need to rebuild pre-aggregation tables immediately

CUBE_API="http://localhost:4000/cubejs-api/v1"

echo "=========================================="
echo "Force Refresh Pre-Aggregations"
echo "=========================================="

# Method 1: Use /pre-aggregations/jobs API
echo -e "\nMethod 1: Trigger pre-aggregation build jobs\n"

# dailyByRegion
echo "🔄 Triggering events.dailyByRegion..."
curl -s -X POST "$CUBE_API/pre-aggregations/jobs" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "post",
    "selector": {
      "contexts": [{"securityContext": {}}],
      "timezones": ["UTC"],
      "dataSources": ["default"],
      "cubes": ["events"],
      "preAggregations": ["dailyByRegion"]
    }
  }' | jq '.'

# dailyByDevice
echo -e "\n🔄 Triggering events.dailyByDevice..."
curl -s -X POST "$CUBE_API/pre-aggregations/jobs" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "post",
    "selector": {
      "contexts": [{"securityContext": {}}],
      "timezones": ["UTC"],
      "dataSources": ["default"],
      "cubes": ["events"],
      "preAggregations": ["dailyByDevice"]
    }
  }' | jq '.'

# Method 2: Force refresh check via query
echo -e "\n\nMethod 2: Trigger refresh check via query\n"

curl -s -X POST "$CUBE_API/load" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "measures": ["events.pv", "events.uv"],
      "dimensions": ["events.region"],
      "timeDimensions": [{
        "dimension": "events.event_time",
        "granularity": "day",
        "dateRange": "Last 180 days"
      }]
    },
    "queryType": "regularQuery"
  }' | jq '{status: .query.status, duration: .query.total}'

echo -e "\n✅ Refresh requests sent"
echo "💡 Pre-aggregations will build asynchronously in the background, may take a few minutes"
echo "💡 Check Cube service logs to monitor build progress"
