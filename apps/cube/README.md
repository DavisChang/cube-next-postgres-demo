# Cube Service Overview

This document explains the Cube.js service under `apps/cube`: architecture, boot process, schema design, and how it connects to PostgreSQL, builds pre-aggregations, and serves API queries.

## Architecture Overview
- **Semantic layer (Cube.js Server)**: powered by `@cubejs-backend/server`, managing models, security, and caching.
- **Data source (PostgreSQL)**: pulls rows from `public.events` as the fact table.
- **Pre-aggregations**: rollups defined in Cube.js, precomputing frequent queries and storing them (default Cube Store).
- **API / SDK**: the frontend (`apps/web`) or external clients query `/cubejs-api/v1/load`, Cube responds using schema definitions.

```
PostgreSQL ──> Cube.js Schema ──> Pre-Aggregations ──> Cube.js API ──> Frontend Visualisation
```

## Boot Flow & Key Files
- `.env`: database connection and Cube.js server settings (e.g., `CUBEJS_DB_HOST`, `CUBEJS_SCHEDULED_REFRESH`).
- `server.js`: loads env vars, creates the `CubejsServer` instance, and starts HTTP on `http://localhost:4000`.
- `model/cubes/`: contains cube schemas (one file per dataset). `events.js` defines measures, dimensions, and pre-aggregations for the events fact table.
- `package.json`:
  - scripts: `start` launches the semantic layer with `node server.js`.
  - dependencies:
    - `@cubejs-backend/server`: core semantic layer framework.
    - `@cubejs-backend/postgres-driver`: PostgreSQL driver.
    - `pg`: Node.js PostgreSQL client.
    - `dotenv`: loads `.env` variables.

Start PostgreSQL with the project root `docker-compose.yml`, run `seed/seed.js` to populate data, and the Cube.js service is ready for queries.

## Cube.js Functional Modules
- **Schema layer**: defines data models, column types, and derived metrics via JavaScript—Cube.js generates SQL.
- **Pre-aggregations**: configures rollup types, granularity, and refresh policies to lighten load on base tables.
- **Query orchestration**: handles refresh scheduling, cache hits, concurrency inside Cube.js.
- **Security & multi-tenancy** (optional): configure API tokens, JWTs, or `securityContext` in `server.js` or environment.

## model/cubes/events.js Walkthrough
`events.js` declares a dataset with `cube()`, mapping to the PostgreSQL `public.events` table.

```javascript
cube(`events`, {
  sql_table: `public.events`,

  data_source: `default`,

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
  },

  pre_aggregations: {
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
      measures: [events.pv, events.uv],
      timeDimension: events.event_time,
      granularity: "day",
      dimensions: [events.device],
      partitionGranularity: "month",
      refreshKey: { every: "30 minutes" },
    },
  },
});
```

- **SQL source**: the `sql_table` block points to `public.events` table.
- **Measures**:
  - `count`: counts all event rows.
  - `pv`: counts event rows (page views).
  - `uv`: distinct count of `user_id` (unique visitors).
  - `revenue`: sum of `revenue`.
  - `avg_session`: average of `session_duration_seconds`.
- **Dimensions**: slice by `region`, `device`, `source`, and time dimension `event_time`.
- **Pre-aggregations**:
  - `dailyByRegion`: day × region rollup, aggregating multiple measures, monthly partitions, refresh every 30 minutes.
  - `dailyByDevice`: day × device rollup for `pv` and `uv`, same partitioning and refresh.

This schema lets the frontend query metrics (`pv/uv/revenue/avg_session`) while hitting precomputed rollups for the 180-day window, keeping performance consistent.

## Typical Extensions
- Add new columns by extending `dimensions` or `measures`, plus matching pre-aggregations when necessary.
- For finer time granularity (e.g., `hour`), clone an existing rollup and adjust `granularity` and `partitionGranularity`.
- Support multi-tenancy by leveraging `context` or `securityContext` in schema SQL logic.

---

## Maintenance & Monitoring

### 1. Service Health Checks

**Check if Cube is running:**
```bash
# Health check endpoint (readyz or livez)
curl http://localhost:4000/readyz

# Expected response: {"health":"HEALTH"}
```

**Check Cube Store status:**
```bash
# Cube Store should be listening on port 3030
lsof -nP -iTCP:3030 -sTCP:LISTEN

# Check Cube Store HTTP endpoint
curl http://localhost:3030/
```

**Monitor service logs:**
```bash
cd apps/cube
npm run start

# Watch for:
✅ "Cube is listening on http://localhost:4000"
✅ "Cube Store is assigned to 3030 port"
❌ "Unable to start Cube Store" - port conflict
❌ "Error while querying" - database connection issues
```

---

### 2. Pre-Aggregation Monitoring

**Check which pre-aggregations are used:**
```bash
curl -s -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "measures": ["events.pv", "events.uv"],
      "dimensions": ["events.region"],
      "timeDimensions": [{
        "dimension": "events.event_time",
        "granularity": "day",
        "dateRange": "Last 30 days"
      }]
    }
  }' | jq '{
    usedPreAggregations,
    external,
    slowQuery
  }'
```

**Key indicators:**
- `usedPreAggregations` **not empty** ✅ = pre-aggregations are working
- `external: true` ✅ = data from Cube Store (not PostgreSQL)
- `slowQuery: false` ✅ = good performance
- `usedPreAggregations: {}` ❌ = querying raw tables directly

**List all pre-aggregations:**
```bash
curl -s http://localhost:4000/cubejs-api/v1/pre-aggregations \
  | jq '.preAggregations[] | {cube, preAggregationName, status}'
```

**Force refresh pre-aggregations:**
```bash
# Run the refresh script
../force-refresh-preagg.sh

# Or manually trigger via API
curl -X POST "http://localhost:4000/cubejs-api/v1/pre-aggregations/jobs" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "post",
    "selector": {
      "contexts": [{"securityContext": {}}],
      "timezones": ["UTC"],
      "dataSources": ["default"],
      "cubes": ["events"]
    }
  }'
```

---

### 3. Performance Metrics

**Query response time monitoring:**
```bash
# Test query performance
time curl -s -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{"query":{...}}'

# Typical response times:
# With pre-aggregations: 10-100ms ✅
# Without pre-aggregations: 100-2000ms ⚠️
# Slow queries (>2s): investigate ❌
```

**Watch for slow queries in logs:**
```bash
# Cube logs queries with timing:
Performing query completed: xxx-span-1 (21ms)  ✅ Good
Performing query completed: xxx-span-1 (2500ms)  ❌ Slow

# Slow query indicators:
"slowQuery": true  ❌
Error while querying  ❌
```

---

### 4. Cube Store Maintenance

**Check Cube Store disk usage:**
```bash
# Pre-aggregation data stored in .cubestore/
du -sh .cubestore/

# Typical sizes:
# Metastore: 10-100 MB
# Cachestore: depends on data volume (can be GB)
```

**Monitor Cube Store compaction:**
```bash
# Watch logs for compaction jobs:
Running job completed: PartitionCompaction ✅
Running job completed: NodeInMemoryChunksCompaction ✅

# These run automatically, optimizing storage
```

**Clean old Cube Store data (if needed):**
```bash
# Stop Cube service first
# Remove Cube Store data (forces rebuild)
rm -rf .cubestore/

# Restart Cube - will rebuild pre-aggregations
npm run start
```

---

### 5. Database Connection Monitoring

**Test PostgreSQL connectivity:**
```bash
# From Cube container or local machine
docker compose exec -e PGPASSWORD=pass postgres \
  psql -U analytics -d analytics -c "SELECT COUNT(*) FROM public.events;"

# Should return row count without errors
```

**Monitor connection pool:**
- Default: Cube uses connection pooling automatically
- Watch for connection errors in logs:
  - `ECONNREFUSED` ❌ - PostgreSQL not running
  - `too many connections` ❌ - connection pool exhausted
  - `password authentication failed` ❌ - credential issues

---

### 6. Data Consistency Checks

**Verify pre-aggregation accuracy:**
```bash
# Run automated verification
../verify-preagg.sh

# Check for:
✅ Values match between PostgreSQL and Cube API
⚠️ Small differences (±1) are normal for float conversions
❌ Large differences indicate stale pre-aggregations
```

**Check last refresh time:**
```json
// In API response:
{
  "lastRefreshTime": "2025-10-22T16:08:35.000Z",
  "usedPreAggregations": {
    "...": {
      "lastUpdatedAt": 1761148915000
    }
  }
}
```

**If data seems stale:**
1. Check refresh interval: `refreshKey: { every: "30 minutes" }`
2. Force refresh: `../force-refresh-preagg.sh`
3. Check logs for refresh errors

---

### 7. Common Issues & Solutions

#### Issue: Pre-Aggregations Not Being Used

**Symptoms:**
- `usedPreAggregations: {}`
- Queries are slow (>500ms)

**Solutions:**
1. Check query matches pre-aggregation definition:
   - Same measures, dimensions, granularity
   - Time range within partition range
2. Wait for initial build (1-2 minutes after startup)
3. Check Cube Store is running: `lsof -nP -iTCP:3030`
4. Force rebuild: `rm -rf .cubestore/ && npm run start`

#### Issue: Port Conflicts

**Symptoms:**
```
error binding to 0.0.0.0:3030: Address already in use
Unable to start Cube Store
```

**Solutions:**
```bash
# Find process using port 3030
lsof -nP -iTCP:3030 -sTCP:LISTEN

# Kill the process
kill -9 <PID>

# Or change Cube Store port in .env:
CUBEJS_CUBESTORE_PORT=3040
```

#### Issue: Slow Query Performance

**Symptoms:**
- Response time >2s
- `slowQuery: true`

**Solutions:**
1. Verify pre-aggregations are being used
2. Check PostgreSQL indexes on `event_time`, `region`, `device`
3. Consider adding more specific pre-aggregations
4. Reduce date range in queries
5. Monitor PostgreSQL query plans

#### Issue: Memory/Disk Usage Growing

**Symptoms:**
- `.cubestore/` directory growing large
- High memory usage

**Solutions:**
1. Adjust partition granularity (monthly → quarterly)
2. Reduce retention in pre-aggregations
3. Clean old partitions manually
4. Monitor and set disk space alerts

---

### 8. Regular Maintenance Tasks

**Daily:**
- [ ] Check service health: `curl http://localhost:4000/readyz`
- [ ] Monitor query performance in logs
- [ ] Watch for error patterns

**Weekly:**
- [ ] Run data consistency checks: `../verify-preagg.sh`
- [ ] Review slow query logs
- [ ] Check Cube Store disk usage: `du -sh .cubestore/`

**Monthly:**
- [ ] Review and optimize pre-aggregation definitions
- [ ] Analyze query patterns, add new pre-aggregations if needed
- [ ] Clean up old Cube Store partitions (if needed)
- [ ] Update Cube.js dependencies: `npm outdated`

---

### 9. Key Metrics to Monitor

**Service Availability:**
- Uptime: should be 99.9%+
- Health check response time: <50ms

**Query Performance:**
- P50 response time: <100ms with pre-aggregations
- P99 response time: <500ms
- Pre-aggregation hit rate: >90%

**Resource Usage:**
- Cube Store disk: monitor growth rate
- Memory: typically 200-500MB for small datasets
- CPU: spikes during pre-aggregation builds (normal)

**Data Freshness:**
- Pre-aggregation lag: max 30 minutes (per refreshKey)
- Last refresh timestamp: check in API responses

---

### 10. Useful Commands Quick Reference

```bash
# Health check
curl http://localhost:4000/readyz

# Test query with pre-agg check
curl -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{"query":{...}}' | jq '.usedPreAggregations'

# Verify data accuracy
../verify-preagg.sh

# Force pre-aggregation refresh
../force-refresh-preagg.sh

# Check Cube Store disk usage
du -sh .cubestore/

# View recent logs
tail -f <cube-service-logs>

# Check PostgreSQL connection
docker compose exec -e PGPASSWORD=pass postgres \
  psql -U analytics -d analytics -c "SELECT COUNT(*) FROM events;"

# Check port usage
lsof -nP -iTCP:4000,3030,15432 -sTCP:LISTEN
```

---

For more configuration options, see the [Cube.js documentation](https://cube.dev/docs) or the project root `README.md` for end-to-end setup instructions.

