# Cube API Endpoints 快速參考

## 🔗 可用的 Endpoints

### 1️⃣ **健康檢查 Endpoints**

#### `/readyz` - Ready Check
```bash
curl http://localhost:4000/readyz
```
**響應：**
```json
{"health":"HEALTH"}
```

#### `/livez` - Liveness Check
```bash
curl http://localhost:4000/livez
```
**響應：**
```json
{"health":"HEALTH"}
```

**用途：**
- Kubernetes readiness probes
- 自動化健康檢查
- 監控系統集成

---

### 2️⃣ **數據查詢 Endpoint**

#### `/cubejs-api/v1/load` - Load Data
```bash
curl -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "measures": ["events.pv", "events.uv"],
      "dimensions": ["events.region"],
      "timeDimensions": [{
        "dimension": "events.event_time",
        "dateRange": "Last 7 days"
      }]
    }
  }'
```

**響應示例：**
```json
{
  "query": {...},
  "data": [
    {
      "events.region": "JP",
      "events.pv": "825",
      "events.uv": "822"
    }
  ],
  "lastRefreshTime": "2025-10-22T16:08:35.000Z",
  "usedPreAggregations": {
    "dev_pre_aggregations.events_daily_by_region": {...}
  },
  "external": true,
  "slowQuery": false
}
```

---

### 3️⃣ **Pre-Aggregations 管理**

#### `/cubejs-api/v1/pre-aggregations` - List Pre-Aggregations
```bash
curl http://localhost:4000/cubejs-api/v1/pre-aggregations
```

**響應示例：**
```json
{
  "preAggregations": [
    {
      "cube": "events",
      "preAggregationName": "dailyByRegion",
      "status": "ready"
    }
  ]
}
```

#### `/cubejs-api/v1/pre-aggregations/jobs` - Trigger Refresh
```bash
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

### 4️⃣ **Cube Playground (UI)**

#### `/` - Web Interface
```bash
# 在瀏覽器中打開
open http://localhost:4000
```

**功能：**
- 互動式查詢構建器
- Schema 瀏覽器
- 查詢測試工具
- 生成代碼示例

---

### 5️⃣ **Cube SQL Interface**

#### PostgreSQL 協議接口
```bash
# 使用 psql 連接
psql -h localhost -p 15432 -U analytics -d analytics

# 或使用任何支持 PostgreSQL 協議的工具
```

**用途：**
- BI 工具連接（Tableau, Metabase, Superset）
- SQL 客戶端查詢
- 直接查看 pre-aggregation 表

---

## 📊 常用檢查命令

### 快速健康檢查
```bash
# 檢查服務是否運行
curl -s http://localhost:4000/readyz | jq '.'

# 預期: {"health":"HEALTH"}
```

### 檢查 Pre-Aggregations 使用情況
```bash
curl -s -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "measures": ["events.pv"],
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

### 測試查詢性能
```bash
time curl -s -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "measures": ["events.pv"],
      "timeDimensions": [{
        "dimension": "events.event_time",
        "dateRange": "Last 7 days"
      }]
    }
  }' > /dev/null
```

---

## 🚨 錯誤的 Endpoints

以下 endpoints **不存在**，請勿使用：

- ❌ `/cubejs-api/v1/ready` → 使用 `/readyz` 或 `/livez`
- ❌ `/api/health` → 使用 `/readyz` 或 `/livez`
- ❌ `/health` → 使用 `/readyz` 或 `/livez`

---

## 🔧 Kubernetes 健康檢查配置

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cube
spec:
  containers:
  - name: cube
    image: cube-app
    ports:
    - containerPort: 4000
    livenessProbe:
      httpGet:
        path: /livez
        port: 4000
      initialDelaySeconds: 30
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /readyz
        port: 4000
      initialDelaySeconds: 10
      periodSeconds: 5
```

---

## 📝 開發模式 vs 生產模式

### 開發模式（當前）
- ✅ 無需 Authorization header
- ✅ 可以直接訪問 Playground
- ✅ 詳細的錯誤信息

### 生產模式
```bash
# 需要設置環境變量
export NODE_ENV=production
export CUBEJS_API_SECRET=your-secret-key

# 查詢需要 JWT token
curl -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{...}'
```

---

## 🎯 快速測試

### 1. 測試服務可用性
```bash
curl -s http://localhost:4000/readyz && echo " ✅ Cube 運行正常" || echo " ❌ Cube 無法連接"
```

### 2. 測試數據查詢
```bash
curl -s -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{"query":{"measures":["events.pv"],"timeDimensions":[{"dimension":"events.event_time","dateRange":"Last 1 day"}]}}' \
  | jq -r '.data[0]."events.pv" // "查詢失敗"'
```

### 3. 測試 Pre-Aggregations
```bash
curl -s -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{"query":{"measures":["events.pv","events.uv"],"dimensions":["events.region"],"timeDimensions":[{"dimension":"events.event_time","granularity":"day","dateRange":"Last 7 days"}]}}' \
  | jq -r 'if (.usedPreAggregations | length) > 0 then "✅ 使用了 Pre-Aggregations" else "⚠️  未使用 Pre-Aggregations" end'
```

---

## 📚 相關文檔

- [Cube 官方文檔](https://cube.dev/docs)
- [REST API 參考](https://cube.dev/docs/rest-api)
- [Pre-Aggregations 指南](https://cube.dev/docs/caching/pre-aggregations/getting-started)

---

**最後更新**: 2025-10-22
**Cube 版本**: 1.3.81

