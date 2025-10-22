#!/bin/bash

# Cube API Test Script Collection
# Usage: bash test-cube-api.sh

# Set API URL and Token (development mode usually doesn't require a real token)
API_URL="http://localhost:4000/cubejs-api/v1/load"
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3MDAwMDAwMDAsImV4cCI6MTgwMDAwMDAwMH0.test"

echo "=== Test 1: Basic Query - PV and UV by Region (Last 7 days) ==="
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "query": {
      "measures": ["events.pv", "events.uv"],
      "dimensions": ["events.region"],
      "timeDimensions": [{
        "dimension": "events.event_time",
        "dateRange": "Last 7 days"
      }],
      "order": {
        "events.pv": "desc"
      },
      "limit": 10
    }
  }' | jq '.'

echo -e "\n\n=== Test 2: Time Series - Daily PV/UV/Revenue Trends (Last 30 days) ==="
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "query": {
      "measures": ["events.pv", "events.uv", "events.revenue"],
      "timeDimensions": [{
        "dimension": "events.event_time",
        "granularity": "day",
        "dateRange": "Last 30 days"
      }],
      "order": {
        "events.event_time": "asc"
      }
    }
  }' | jq '.'

echo -e "\n\n=== Test 3: All Metrics by Device (Last 180 days) ==="
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "query": {
      "measures": ["events.pv", "events.uv", "events.revenue", "events.avg_session"],
      "dimensions": ["events.device"],
      "timeDimensions": [{
        "dimension": "events.event_time",
        "dateRange": "Last 180 days"
      }],
      "order": {
        "events.revenue": "desc"
      }
    }
  }' | jq '.'

echo -e "\n\n=== Test 4: Cross-Analysis - Source and Region (Specific date range) ==="
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "query": {
      "measures": ["events.pv", "events.uv", "events.revenue"],
      "dimensions": ["events.source", "events.region"],
      "timeDimensions": [{
        "dimension": "events.event_time",
        "dateRange": ["2024-01-01", "2024-12-31"]
      }],
      "order": {
        "events.pv": "desc"
      },
      "limit": 20
    }
  }' | jq '.'

echo -e "\n\n=== Test 5: Weekly Trends - by Device (Last 90 days) ==="
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "query": {
      "measures": ["events.pv", "events.uv"],
      "dimensions": ["events.device"],
      "timeDimensions": [{
        "dimension": "events.event_time",
        "granularity": "week",
        "dateRange": "Last 90 days"
      }],
      "order": {
        "events.event_time": "asc"
      }
    }
  }' | jq '.'

echo -e "\n\n✅ Tests completed!"
