-- 檢查 Cube Store 中的 Pre-Aggregation 表
-- 連接方式: psql -h localhost -p 15432 -U analytics -d analytics

-- 1. 查看所有 pre-aggregation 表
SELECT table_schema, table_name 
FROM information_schema.tables 
WHERE table_schema = 'db_public'
ORDER BY table_name;

-- 2. 查看特定 pre-aggregation 的數據 (dailyByRegion)
-- 注意：實際表名可能包含 hash，需要先執行上面的查詢找到確切表名
-- 示例：
-- SELECT * FROM db_public.events_daily_by_region_xyz123 LIMIT 10;

-- 3. 統計 pre-aggregation 表的行數
SELECT 
    table_name,
    (xpath('/row/cnt/text()', 
        query_to_xml('SELECT count(*) as cnt FROM db_public.' || table_name, false, true, ''))
    )[1]::text::int as row_count
FROM information_schema.tables
WHERE table_schema = 'db_public'
  AND table_name LIKE '%events%'
ORDER BY table_name;

-- 4. 比較 pre-aggregation 和原始表的數據量
-- 原始表總行數
SELECT 'Original events table' as source, COUNT(*) as total_rows
FROM public.events;

-- 5. 查看 pre-aggregation 的最新更新時間
-- (這個查詢依賴於 Cube Store 的內部結構，可能需要調整)

