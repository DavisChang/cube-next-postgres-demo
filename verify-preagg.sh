#!/bin/bash

# Pre-aggregation Data Verification Script
# Compare Cube API (using pre-aggregations) and PostgreSQL raw data

echo "=========================================="
echo "Pre-Aggregation Data Verification Tool"
echo "=========================================="

# Configuration
CUBE_API="http://localhost:4000/cubejs-api/v1/load"
PG_HOST="localhost"
PG_PORT="5432"
PG_USER="analytics"
PG_DB="analytics"
PG_PASSWORD="pass"

# Function to execute psql commands via Docker
run_psql() {
  docker compose exec -T -e PGPASSWORD="$PG_PASSWORD" postgres psql -U "$PG_USER" -d "$PG_DB" -c "$1"
}

# Test date range
START_DATE="2025-09-01"
END_DATE="2025-10-22"

echo -e "\n📅 Test Date Range: $START_DATE to $END_DATE\n"

# ==========================================
# Test 1: Statistics by Region (PV/UV/Revenue)
# ==========================================
echo "=========================================="
echo "Test 1: Statistics by Region (dailyByRegion pre-agg)"
echo "=========================================="

echo -e "\n🔹 Method 1: Query PostgreSQL raw data directly"
run_psql "
SELECT 
    region,
    COUNT(*) as pv,
    COUNT(DISTINCT user_id) as uv,
    SUM(revenue)::int as revenue,
    AVG(session_duration_seconds)::int as avg_session
FROM public.events
WHERE event_time >= '$START_DATE'::date 
  AND event_time < '$END_DATE'::date + interval '1 day'
GROUP BY region
ORDER BY pv DESC;
"

echo -e "\n🔹 Method 2: Query via Cube API (will use pre-aggregations)"
curl -s -X POST "$CUBE_API" \
  -H "Content-Type: application/json" \
  -d "{
    \"query\": {
      \"measures\": [\"events.pv\", \"events.uv\", \"events.revenue\", \"events.avg_session\"],
      \"dimensions\": [\"events.region\"],
      \"timeDimensions\": [{
        \"dimension\": \"events.event_time\",
        \"dateRange\": [\"$START_DATE\", \"$END_DATE\"]
      }],
      \"order\": { \"events.pv\": \"desc\" }
    }
  }" | jq -r '
    if .data then
      "Region\t\tPV\tUV\tRevenue\t\tAvg Session",
      "------\t\t--\t--\t-------\t\t-----------",
      (.data[] | 
        "\(.["events.region"])\t\t\(.["events.pv"])\t\(.["events.uv"])\t\(.["events.revenue"] | tonumber | floor)\t\t\(.["events.avg_session"] | tonumber | floor)"
      )
    else
      "Error: " + (.error // "Unknown error")
    end
  '

# ==========================================
# Test 2: Statistics by Device
# ==========================================
echo -e "\n\n=========================================="
echo "Test 2: Statistics by Device (dailyByDevice pre-agg)"
echo "=========================================="

echo -e "\n🔹 Method 1: Query PostgreSQL directly"
run_psql "
SELECT 
    device,
    COUNT(*) as pv,
    COUNT(DISTINCT user_id) as uv
FROM public.events
WHERE event_time >= '$START_DATE'::date 
  AND event_time < '$END_DATE'::date + interval '1 day'
GROUP BY device
ORDER BY pv DESC;
"

echo -e "\n🔹 Method 2: Query via Cube API"
curl -s -X POST "$CUBE_API" \
  -H "Content-Type: application/json" \
  -d "{
    \"query\": {
      \"measures\": [\"events.pv\", \"events.uv\"],
      \"dimensions\": [\"events.device\"],
      \"timeDimensions\": [{
        \"dimension\": \"events.event_time\",
        \"dateRange\": [\"$START_DATE\", \"$END_DATE\"]
      }],
      \"order\": { \"events.pv\": \"desc\" }
    }
  }" | jq -r '
    if .data then
      "Device\t\tPV\tUV",
      "------\t\t--\t--",
      (.data[] | "\(.["events.device"])\t\t\(.["events.pv"])\t\(.["events.uv"])")
    else
      "Error: " + (.error // "Unknown error")
    end
  '

# ==========================================
# Test 3: Daily Trend Statistics (last 7 days)
# ==========================================
echo -e "\n\n=========================================="
echo "Test 3: Daily Trend Statistics (last 7 days)"
echo "=========================================="

RECENT_START=$(date -v-7d +%Y-%m-%d)
RECENT_END=$(date +%Y-%m-%d)

echo -e "\n🔹 Method 1: Query PostgreSQL directly (aggregated by day)"
run_psql "
SELECT 
    DATE(event_time) as day,
    COUNT(*) as pv,
    COUNT(DISTINCT user_id) as uv,
    SUM(revenue)::int as revenue
FROM public.events
WHERE event_time >= '$RECENT_START'::date 
  AND event_time < '$RECENT_END'::date + interval '1 day'
GROUP BY DATE(event_time)
ORDER BY day DESC;
"

echo -e "\n🔹 Method 2: Query via Cube API (day granularity)"
curl -s -X POST "$CUBE_API" \
  -H "Content-Type: application/json" \
  -d "{
    \"query\": {
      \"measures\": [\"events.pv\", \"events.uv\", \"events.revenue\"],
      \"timeDimensions\": [{
        \"dimension\": \"events.event_time\",
        \"granularity\": \"day\",
        \"dateRange\": [\"$RECENT_START\", \"$RECENT_END\"]
      }],
      \"order\": { \"events.event_time\": \"desc\" }
    }
  }" | jq -r '
    if .data then
      "Day\t\t\tPV\tUV\tRevenue",
      "---\t\t\t--\t--\t-------",
      (.data[] | "\(.["events.event_time.day"])\t\(.["events.pv"])\t\(.["events.uv"])\t\(.["events.revenue"] | tonumber | floor)")
    else
      "Error: " + (.error // "Unknown error")
    end
  '

# ==========================================
# Test 4: Check Pre-Aggregation Usage
# ==========================================
echo -e "\n\n=========================================="
echo "Test 4: Check Pre-Aggregation Usage"
echo "=========================================="

echo -e "\nQuerying and checking usedPreAggregations field..."
curl -s -X POST "$CUBE_API" \
  -H "Content-Type: application/json" \
  -d "{
    \"query\": {
      \"measures\": [\"events.pv\", \"events.uv\", \"events.revenue\"],
      \"dimensions\": [\"events.region\"],
      \"timeDimensions\": [{
        \"dimension\": \"events.event_time\",
        \"granularity\": \"day\",
        \"dateRange\": [\"$START_DATE\", \"$END_DATE\"]
      }]
    }
  }" | jq '{
    usedPreAggregations: .usedPreAggregations,
    external: .external,
    slowQuery: .slowQuery
  }'

echo -e "\n=========================================="
echo "✅ Verification Complete!"
echo "=========================================="
echo -e "\n💡 Tips:"
echo "1. Compare values from both methods for consistency"
echo "2. Minor differences may occur due to:"
echo "   - Pre-aggregations not yet refreshed (30-minute interval)"
echo "   - Data type conversions (float vs int)"
echo "3. Check 'usedPreAggregations' field to confirm pre-aggregation usage"
