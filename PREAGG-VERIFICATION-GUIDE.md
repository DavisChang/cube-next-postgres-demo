# Pre-Aggregation 驗證指南

## 📊 驗證結果對比

### 測試 1：最近 7 天數據對比

#### 方法 A：直接查詢 PostgreSQL 原始數據
```sql
SELECT region, COUNT(*) as pv, COUNT(DISTINCT user_id) as uv, SUM(revenue)::int as revenue 
FROM public.events 
WHERE event_time >= NOW() - INTERVAL '7 days' 
GROUP BY region 
ORDER BY pv DESC 
LIMIT 5;
```

**結果：**
```
 region | pv  | uv  | revenue 
--------+-----+-----+---------
 JP     | 724 | 721 |   12336
 US     | 680 | 679 |   11797
 CA     | 674 | 670 |   11020
 AU     | 660 | 655 |   11026
 TW     | 654 | 650 |   11855
```

#### 方法 B：通過 Cube API 查詢（使用 Pre-Aggregations）
```bash
curl -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{"query":{...}}'
```

**結果：**
```
Region  PV   UV   Revenue
JP      825  822  14056.83
US      752  750  12931.14
TW      747  742  13315.85
FR      743  738  12492.60
CA      742  738  12143.63
```

**使用的 Pre-Aggregation：**
```json
{
  "usedPreAggregations": {
    "dev_pre_aggregations.events_daily_by_region": {
      "targetTableName": "UNION ALL 9月和10月分區",
      "external": true,
      "lastUpdatedAt": "2025-10-22T16:08:35.000Z"
    }
  }
}
```

---

## ✅ 驗證要點

### 1. **確認使用了 Pre-Aggregations**

查看 API 響應中的關鍵字段：
```json
{
  "usedPreAggregations": {
    "dev_pre_aggregations.events_daily_by_region": {...}
  },
  "external": true,           // true = 從 Cube Store 讀取
  "dbType": "postgres",        // 原始數據源類型
  "extDbType": "cubestore",   // 實際查詢的存儲引擎
  "slowQuery": false          // 查詢性能
}
```

**判斷標準：**
- ✅ `usedPreAggregations` **不為空** → 使用了預聚合
- ✅ `external: true` → 數據來自 Cube Store（不是直接查 PostgreSQL）
- ❌ `usedPreAggregations: {}` → 直接查詢原始表

---

### 2. **數據一致性檢查**

#### 為什麼會有差異？

比較上面的結果，數值有些不同，可能原因：

| 差異類型 | 原因 | 解決方案 |
|---------|------|---------|
| **數值完全不同** | 時區問題（UTC vs 本地時間） | 統一使用 UTC |
| **數值接近但不完全相同** | "Last 7 days" 計算方式不同 | 使用明確的日期範圍 |
| **Pre-agg 數據較舊** | 還沒到刷新時間（30分鐘間隔） | 等待或手動觸發刷新 |
| **精度差異** | Float vs Int 轉換 | 四捨五入或 FLOOR |

#### 推薦驗證方法：使用相同的日期範圍

```bash
# PostgreSQL
docker compose exec -e PGPASSWORD=pass postgres psql -U analytics -d analytics -c "
SELECT region, COUNT(*) as pv, COUNT(DISTINCT user_id) as uv 
FROM public.events 
WHERE event_time >= '2025-10-01'::date 
  AND event_time < '2025-10-22'::date 
GROUP BY region 
ORDER BY pv DESC;"

# Cube API
curl -X POST "http://localhost:4000/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "measures": ["events.pv", "events.uv"],
      "dimensions": ["events.region"],
      "timeDimensions": [{
        "dimension": "events.event_time",
        "dateRange": ["2025-10-01", "2025-10-21"]
      }]
    }
  }'
```

---

### 3. **查看 Cube Store 中的實際表**

連接到 Cube SQL 接口：
```bash
# Cube 提供的 PostgreSQL 協議接口
psql -h localhost -p 15432 -U analytics -d analytics

# 或使用 Docker
docker compose exec -e PGPASSWORD=pass postgres \
  psql "postgresql://analytics:pass@host.docker.internal:15432/analytics"
```

查詢 pre-aggregation 表：
```sql
-- 列出所有 pre-aggregation 表
\dt dev_pre_aggregations.*

-- 查看特定表的結構
\d dev_pre_aggregations.events_daily_by_region20251001_*

-- 查詢預聚合數據
SELECT * FROM dev_pre_aggregations.events_daily_by_region20251001_5gqk1dzc_fkw32jwm_1kfhvvj 
LIMIT 10;
```

---

### 4. **檢查 Pre-Aggregation 分區**

你的配置：
```javascript
pre_aggregations: {
  dailyByRegion: {
    type: "rollup",
    partitionGranularity: "month",  // 按月分區
    refreshKey: { every: "30 minutes" }
  }
}
```

**分區命名規則：**
```
events_daily_by_region20250901_xxx  // 2025年9月分區
events_daily_by_region20251001_xxx  // 2025年10月分區
```

查詢會自動 UNION ALL 相關分區：
```sql
SELECT * FROM (...partition_sept...) 
UNION ALL 
SELECT * FROM (...partition_oct...)
```

---

## 🔧 驗證工具

### 工具 1：自動對比腳本
```bash
./verify-preagg.sh
```
自動執行多組對比測試，輸出結果

### 工具 2：強制刷新 Pre-Aggregations
```bash
./force-refresh-preagg.sh
```
立即觸發預聚合表重建（不等 30 分鐘）

### 工具 3：查看 Cube Store 表結構
```bash
psql -h localhost -p 15432 -U analytics -d analytics -f check-preagg-tables.sql
```

---

## 📈 性能對比

### 不使用 Pre-Aggregations（直接查 PostgreSQL）
```
查詢 180 天數據：約 500-2000ms
查詢複雜聚合：約 1000-5000ms
```

### 使用 Pre-Aggregations（從 Cube Store 讀取）
```
查詢 180 天數據：約 5-50ms
查詢複雜聚合：約 10-100ms
```

**性能提升：10-100x** 🚀

---

## ❓ 常見問題

### Q1: 為什麼 `usedPreAggregations` 為空？

可能原因：
1. **Pre-aggregation 還沒構建** → 等待首次構建（約 1-2 分鐘）
2. **查詢條件不匹配** → 確保 measures、dimensions、granularity 都匹配定義
3. **時間範圍超出分區** → 檢查 `partitionGranularity` 和查詢日期範圍
4. **Pre-aggregation 被禁用** → 檢查環境變量

### Q2: 如何確認 Pre-Aggregation 已經構建完成？

檢查 Cube 日誌：
```
✅ 看到這些表示成功：
- "Performing query completed"
- "PartitionCompaction"
- "Persisting metastore snapshot"

❌ 看到這些表示失敗：
- "Error while querying"
- "Unable to start Cube Store"
```

或查詢 API：
```bash
curl http://localhost:4000/cubejs-api/v1/pre-aggregations | jq '.'
```

### Q3: 數據更新後，多久能在 Pre-Aggregation 中看到？

根據你的配置：
```javascript
refreshKey: { every: "30 minutes" }
```
**最長延遲：30 分鐘**

可以手動觸發立即刷新：
```bash
./force-refresh-preagg.sh
```

---

## 📝 驗證檢查清單

- [ ] Pre-aggregation 已構建（`usedPreAggregations` 不為空）
- [ ] 數據來自 Cube Store（`external: true`）
- [ ] 查詢性能顯著提升（< 100ms）
- [ ] 數值與 PostgreSQL 直查基本一致（允許小差異）
- [ ] 分區正確（月份分區對應查詢日期範圍）
- [ ] 刷新機制正常（30 分鐘更新一次）
- [ ] Cube Store 日誌無錯誤

---

## 🎯 最佳實踐

1. **使用明確的日期範圍**，避免 "Last X days" 的時區歧義
2. **監控 Pre-Aggregation 表大小**，避免分區過大
3. **定期檢查數據一致性**，使用自動化腳本
4. **調整刷新頻率**，平衡實時性和性能
5. **查看查詢計劃**，確認使用了正確的預聚合表

---

生成時間：2025-10-22
Cube 版本：1.3.81

