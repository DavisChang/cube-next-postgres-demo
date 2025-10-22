#!/bin/bash

# Cube Service Health Check Script
# Quick check of all critical metrics

echo "=========================================="
echo "🏥 Cube Service Health Check"
echo "=========================================="
echo "Check Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check counters
PASSED=0
FAILED=0
WARNINGS=0

# ==========================================
# 1. Service Availability Check
# ==========================================
echo "1️⃣  Service Availability"
echo "---"

# Cube API health check
echo -n "Cube API (port 4000): "
HEALTH_RESPONSE=$(curl -s http://localhost:4000/readyz 2>/dev/null)
if echo "$HEALTH_RESPONSE" | grep -q "HEALTH"; then
    echo -e "${GREEN}✅ Running${NC}"
    ((PASSED++))
else
    echo -e "${RED}❌ Cannot connect${NC}"
    ((FAILED++))
fi

# Cube Store check
echo -n "Cube Store (port 3030): "
if lsof -nP -iTCP:3030 -sTCP:LISTEN > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Running${NC}"
    ((PASSED++))
else
    echo -e "${RED}❌ Not running${NC}"
    ((FAILED++))
fi

# PostgreSQL connection check
echo -n "PostgreSQL Connection: "
if docker compose exec -T -e PGPASSWORD=pass postgres psql -U analytics -d analytics -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Connected${NC}"
    ((PASSED++))
else
    echo -e "${RED}❌ Connection failed${NC}"
    ((FAILED++))
fi

echo ""

# ==========================================
# 2. Pre-Aggregation Status
# ==========================================
echo "2️⃣  Pre-Aggregation Status"
echo "---"

# Test query to check pre-aggregations
RESPONSE=$(curl -s -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "measures": ["events.pv", "events.uv"],
      "dimensions": ["events.region"],
      "timeDimensions": [{
        "dimension": "events.event_time",
        "granularity": "day",
        "dateRange": "Last 7 days"
      }]
    }
  }')

# Check if pre-aggregations are used
USED_PREAGG=$(echo "$RESPONSE" | jq -r '.usedPreAggregations | length')
IS_EXTERNAL=$(echo "$RESPONSE" | jq -r '.external')
IS_SLOW=$(echo "$RESPONSE" | jq -r '.slowQuery')

echo -n "Pre-Aggregations Usage: "
if [ "$USED_PREAGG" != "null" ] && [ "$USED_PREAGG" -gt 0 ]; then
    echo -e "${GREEN}✅ Using ($USED_PREAGG pre-agg)${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠️  Not used (querying PostgreSQL directly)${NC}"
    ((WARNINGS++))
fi

echo -n "Data Source: "
if [ "$IS_EXTERNAL" = "true" ]; then
    echo -e "${GREEN}✅ Cube Store (pre-aggregated)${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠️  PostgreSQL (raw tables)${NC}"
    ((WARNINGS++))
fi

echo -n "Query Performance: "
if [ "$IS_SLOW" = "false" ] || [ "$IS_SLOW" = "null" ]; then
    echo -e "${GREEN}✅ Normal${NC}"
    ((PASSED++))
else
    echo -e "${RED}❌ Slow query${NC}"
    ((FAILED++))
fi

echo ""

# ==========================================
# 3. Performance Metrics
# ==========================================
echo "3️⃣  Performance Metrics"
echo "---"

# Test query response time (using curl's built-in timing)
RESPONSE_TIME=$(curl -s -w "%{time_total}" -o /dev/null -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{"query":{"measures":["events.pv"],"timeDimensions":[{"dimension":"events.event_time","dateRange":"Last 7 days"}]}}' 2>/dev/null)

# Convert to milliseconds (curl returns seconds)
if [ -n "$RESPONSE_TIME" ]; then
    RESPONSE_TIME_MS=$(echo "$RESPONSE_TIME * 1000" | bc 2>/dev/null || echo "0")
    RESPONSE_TIME_MS=${RESPONSE_TIME_MS%.*}  # Integer part
    
    echo -n "API Response Time: ${RESPONSE_TIME_MS}ms - "
    if [ "$RESPONSE_TIME_MS" -lt 100 ] 2>/dev/null; then
        echo -e "${GREEN}✅ Excellent${NC}"
        ((PASSED++))
    elif [ "$RESPONSE_TIME_MS" -lt 500 ] 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Acceptable${NC}"
        ((WARNINGS++))
    else
        echo -e "${RED}❌ Slow or cannot connect${NC}"
        ((FAILED++))
    fi
else
    echo -e "${RED}❌ Cannot measure (service may not be running)${NC}"
    ((FAILED++))
fi

echo ""

# ==========================================
# 4. Resource Usage
# ==========================================
echo "4️⃣  Resource Usage"
echo "---"

# Cube Store disk usage
if [ -d "apps/cube/.cubestore" ]; then
    CUBESTORE_SIZE=$(du -sh apps/cube/.cubestore 2>/dev/null | cut -f1)
    echo "Cube Store Disk Usage: $CUBESTORE_SIZE"
    
    # Simple check for >5GB (adjustable)
    SIZE_IN_MB=$(du -sm apps/cube/.cubestore 2>/dev/null | cut -f1)
    if [ -n "$SIZE_IN_MB" ] && [ "$SIZE_IN_MB" -gt 5120 ] 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Large disk usage, consider cleaning old partitions${NC}"
        ((WARNINGS++))
    else
        echo -e "${GREEN}✅ Disk usage normal${NC}"
        ((PASSED++))
    fi
else
    echo -e "${YELLOW}⚠️  .cubestore directory does not exist${NC}"
    ((WARNINGS++))
fi

echo ""

# ==========================================
# 5. Data Consistency (simplified check)
# ==========================================
echo "5️⃣  Data Consistency (simplified)"
echo "---"

# Compare PostgreSQL and Cube API total PV
PG_COUNT=$(docker compose exec -T -e PGPASSWORD=pass postgres \
  psql -U analytics -d analytics -t -c \
  "SELECT COUNT(*) FROM events WHERE event_time >= NOW() - INTERVAL '1 day';" 2>/dev/null | tr -d ' ')

CUBE_COUNT=$(curl -s -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{"query":{"measures":["events.pv"],"timeDimensions":[{"dimension":"events.event_time","dateRange":"Last 1 day"}]}}' \
  | jq -r '.data[0]."events.pv" // 0')

echo "PostgreSQL Count (last 1 day): $PG_COUNT"
echo "Cube API Count (last 1 day): $CUBE_COUNT"

# Handle empty values or non-numbers
if [ -z "$PG_COUNT" ]; then PG_COUNT=0; fi
if [ -z "$CUBE_COUNT" ]; then CUBE_COUNT=0; fi

if [ "$PG_COUNT" = "$CUBE_COUNT" ]; then
    echo -e "${GREEN}✅ Data consistent${NC}"
    ((PASSED++))
elif [ "$PG_COUNT" = "0" ] && [ "$CUBE_COUNT" = "0" ]; then
    echo -e "${YELLOW}⚠️  No data in last 1 day (may be normal)${NC}"
    ((WARNINGS++))
else
    # Calculate difference (handling numbers)
    if [ "$PG_COUNT" -ge 0 ] 2>/dev/null && [ "$CUBE_COUNT" -ge 0 ] 2>/dev/null; then
        DIFF=$((PG_COUNT - CUBE_COUNT))
        DIFF=${DIFF#-}  # Absolute value
        if [ "$DIFF" -le 5 ] 2>/dev/null; then
            echo -e "${YELLOW}⚠️  Small difference (±$DIFF), acceptable${NC}"
            ((WARNINGS++))
        else
            echo -e "${RED}❌ Data inconsistent (difference: $DIFF)${NC}"
            ((FAILED++))
        fi
    else
        echo -e "${YELLOW}⚠️  Cannot compare data${NC}"
        ((WARNINGS++))
    fi
fi

echo ""

# ==========================================
# Summary
# ==========================================
echo "=========================================="
echo "📊 Check Summary"
echo "=========================================="
echo -e "${GREEN}✅ Passed: $PASSED${NC}"
echo -e "${YELLOW}⚠️  Warnings: $WARNINGS${NC}"
echo -e "${RED}❌ Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}🎉 All checks passed! Service is running well.${NC}"
    exit 0
elif [ $FAILED -eq 0 ]; then
    echo -e "${YELLOW}⚡ Service is normal, but $WARNINGS warnings need attention.${NC}"
    exit 0
else
    echo -e "${RED}🚨 Found $FAILED issues, please check and fix.${NC}"
    echo ""
    echo "Recommended Actions:"
    echo "1. Check Cube service logs"
    echo "2. Run full verification: ./verify-preagg.sh"
    echo "3. Check troubleshooting section in apps/cube/README.md"
    exit 1
fi

