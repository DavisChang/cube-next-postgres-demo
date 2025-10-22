# Cube + Next.js + PostgreSQL (180-day demo)

This is a runnable sample project:
- **DB**: PostgreSQL (started via `docker run`)
- **Backend**: Cube Server (semantic layer + pre-aggregations)
- **Frontend**: Next.js (calls Cube `/cubejs-api/v1/load` directly)
- **Seed**: `seed.js` generates 180 days of sample data (configurable rows per day)

---

## 0) Requirements
- Node.js 18+
- Docker (to start Postgres)

---

## 1) Start Postgres (Docker Compose)

```bash
# Run from project root
docker compose up -d
# Defaults:
# user=analytics, password=pass, db=analytics, port 5432
```

Stop services with `docker compose down`; add `-v` to remove volumes.

---

## 2) Generate Sample Data (180 days)

```bash
# Install dependencies (first time only)
cd apps/cube
npm i

# Set environment variables (.env.test optional; seed.js reads values or uses defaults)
export PGHOST=localhost
export PGPORT=5432
export PGUSER=analytics
export PGPASSWORD=pass
export PGDATABASE=analytics

# Optional tuning
export SEED_DAYS=180         # total days
export ROWS_PER_DAY=1000     # rows per day (lower to speed up)
export BATCH_SIZE=5000       # insert batch size

# Run seed script
node seed/seed.js
```

After seeding the database contains:
- `public.events` table (with indexes)
- 180 days of synthetic data (~`SEED_DAYS * ROWS_PER_DAY` rows by default)

### 2.1 Seed Data Shape & Tuning
- Each record includes `event_time`, `region`, `device`, `source`, `user_id`, `session_duration_seconds`, `revenue`, etc.
- `region` / `device` / `source` are randomly selected from fixed lists to simulate multi-channel traffic.
- `revenue` and `session_duration_seconds` stay in realistic ranges (adjust the random helpers inside `seed/seed.js`).
- Adjust `SEED_DAYS`, `ROWS_PER_DAY`, or `BATCH_SIZE` to control data volume and batching pressure.
- To re-import from scratch, run `TRUNCATE TABLE public.events` before seeding again.

---

## 3) Start Cube (connected to Postgres)

```bash
cd apps/cube
cp .env.example .env   # customise DB connection (defaults to localhost:5432)
npm i                  # install dependencies (first time)
npm run start          # server on http://localhost:4000
```

> Scheduled Refresh is enabled by default, timezone set to Asia/Taipei.

### 3.1 Cube API Usage
- **Playground**: open `http://localhost:4000` to explore queries and copy REST/GraphQL examples.
- **REST API**: send POST requests to `http://localhost:4000/cubejs-api/v1/load` with headers `Authorization: Bearer <CUBEJS_API_TOKEN>` and `Content-Type: application/json`.
- **Development token**: when `.env` lacks JWT settings and `CUBEJS_DEV_MODE=true`, use the generated `CUBEJS_API_TOKEN` (shown in the terminal or Playground settings).
- **Sample request**:

```bash
curl -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Authorization: Bearer ${CUBEJS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "measures": ["events.pv", "events.uv"],
      "timeDimensions": [{ "dimension": "events.event_time", "dateRange": "Last 7 days" }],
      "dimensions": ["events.region"]
    }
  }'
```

- **Testing tips**:
  - Use the Playground `Run` button to verify pre-aggregation hits.
  - Send the sample JSON via `curl` or Postman and inspect the `data`, `query`, and `refreshKey` fields.
  - Watch the Cube server logs for `PreAggregations load cache` to confirm rollups are used.

---

## 4) Start Next.js Frontend

```bash
cd apps/web
cp .env.local.example .env.local   # set API URL / token (DEV_TOKEN works for dev)
npm i
npm run dev         # open http://localhost:3000/analytics
```

Frontend pages:
- `http://localhost:3000/`: landing page
- `http://localhost:3000/analytics`: interactive analytics (dimension/metric/date switches)

> Cube prioritises **pre-aggregations** (rollups); only misses fall back to Postgres.

---

## 5) Project Structure

```
cube-next-postgres-demo/
├─ docker-compose.yml           # Postgres service config
├─ apps/
│  ├─ cube/                     # Cube backend
│  │  ├─ server.js
│  │  ├─ package.json
│  │  ├─ .env.example
│  │  ├─ model/
│  │  │  └─ cubes/
│  │  │     └─ events.js        # Cube schema definition
│  │  └─ seed/
│  │     └─ seed.js             # 180-day seed script (tunable rows/batch)
│  └─ web/                      # Next.js frontend (App Router)
│     ├─ package.json
│     ├─ next.config.js
│     ├─ tsconfig.json
│     ├─ app/
│     │  ├─ layout.tsx
│     │  ├─ page.tsx
│     │  └─ analytics/
│     │     └─ page.tsx
│     └─ .env.local.example
└─ README.md
```

---

## 6) Maintenance & Monitoring

### Quick Health Check

```bash
# Simple health check
curl http://localhost:4000/readyz

# Full automated check (9 checks in 5 seconds)
./health-check.sh
```

### Available Tools

| Tool | Purpose | Usage |
|------|---------|-------|
| `health-check.sh` | Quick health check (5 categories) | `./health-check.sh` |
| `verify-preagg.sh` | Full data verification | `./verify-preagg.sh` |
| `force-refresh-preagg.sh` | Force pre-aggregation refresh | `./force-refresh-preagg.sh` |
| `test-cube-api.sh` | Test Cube API (5 query scenarios) | `./test-cube-api.sh` |

### Documentation

- **`PREAGG-VERIFICATION-GUIDE.md`** - Complete pre-aggregation verification guide
- **`MAINTENANCE-SUMMARY.md`** - Maintenance checklists and quick reference
- **`CUBE-API-REFERENCE.md`** - API endpoints reference
- **`apps/cube/README.md`** - Detailed Cube service documentation with troubleshooting

### Regular Maintenance Tasks

**Daily (5 minutes):**
```bash
./health-check.sh
```

**Weekly (15 minutes):**
```bash
./verify-preagg.sh
du -sh apps/cube/.cubestore/
```

**Monthly (30 minutes):**
- Review query patterns
- Optimize pre-aggregation definitions
- Check for dependency updates: `cd apps/cube && npm outdated`

### Key Metrics

✅ **Healthy State:**
- API response time: <100ms (P50)
- Pre-aggregation hit rate: >90%
- Data consistency: >99%
- Service uptime: 99.9%+

⚠️ **Warning Thresholds:**
- API P99 response time: >1s
- Disk usage: >80%
- Slow queries: >5%

---

## 7) Design Notes

- **Pre-aggregations**:
  - `dailyByRegion`: `day × region`, measures `pv/uv/revenue/avg_session`
  - `dailyByDevice`: `day × device`, measures `pv/uv`
  - Granularity `day`; partition `month`; refresh every 30 minutes (align with ingest cadence)
- **Query range**: frontend defaults to **180 days**, adjust as needed.
- **Indexes**: ensure `event_time`, `region`, `device`, `source` indexes exist on `events`.
- **Security**: use `DEV_TOKEN` in dev; in production issue JWTs (with `securityContext` for multi-tenant support).

---

## 8) Troubleshooting

### Service Not Running

```bash
# Check if Cube is running
curl http://localhost:4000/readyz

# Check Cube Store
lsof -nP -iTCP:3030 -sTCP:LISTEN

# Check PostgreSQL
docker compose ps
```

### Pre-Aggregations Not Working

```bash
# Check if pre-aggregations are being used
curl -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{"query":{"measures":["events.pv"],"dimensions":["events.region"],"timeDimensions":[{"dimension":"events.event_time","granularity":"day","dateRange":"Last 7 days"}]}}' \
  | jq '.usedPreAggregations'

# Force refresh
./force-refresh-preagg.sh
```

### Slow Queries

```bash
# Verify data is coming from Cube Store
curl -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{"query":{...}}' | jq '{external, slowQuery, usedPreAggregations}'

# Check response time
time curl -X POST "http://localhost:4000/cubejs-api/v1/load" ...
```

### Port Conflicts

```bash
# Find process using port 3030
lsof -nP -iTCP:3030 -sTCP:LISTEN

# Kill the process
kill -9 <PID>

# Or restart Docker
docker compose down && docker compose up -d
```

For detailed troubleshooting, see `apps/cube/README.md` (Maintenance & Monitoring section).

---

## 9) Verification Results

Last verified: **2025-10-22**

| Test | PostgreSQL | Cube API | Consistency |
|------|-----------|----------|-------------|
| By Region (7 days) | 6384 PV / 6014 UV | 6384 PV / 6014 UV | ✅ 100% |
| By Device (52 days) | 16796/14258/16412 | 16796/14258/16412 | ✅ 100% |
| Daily Trends (7 days) | 1000 PV avg | 1000 PV avg | ✅ 99.99% |

**Pre-Aggregations Status:**
- ✅ Using `dev_pre_aggregations.events_daily_by_region`
- ✅ Data from Cube Store (external: true)
- ✅ Response time: 6-21ms (excellent)

Run `./verify-preagg.sh` for full verification.

---

## 10) Additional Resources

- [Cube.js Documentation](https://cube.dev/docs)
- [Pre-Aggregations Guide](https://cube.dev/docs/caching/pre-aggregations/getting-started)
- [REST API Reference](https://cube.dev/docs/rest-api)
- Project-specific docs:
  - `apps/cube/README.md` - Cube service architecture and maintenance
  - `PREAGG-VERIFICATION-GUIDE.md` - Pre-aggregation verification
  - `MAINTENANCE-SUMMARY.md` - Maintenance checklists
  - `CUBE-API-REFERENCE.md` - API endpoints reference
