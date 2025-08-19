# SQL DBA Toolbox - Reference Queries

## 🔍 Index Analysis & Optimization

### Most Queried Tables/Columns Analysis
```sql
-- Find most expensive queries against a specific table
SELECT TOP 10
    qs.execution_count,
    qs.total_logical_reads,
    qs.total_elapsed_time,
    qs.avg_logical_reads,
    qt.text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qt.text LIKE '%YourTableName%'
ORDER BY qs.total_logical_reads DESC
```

### Missing Index Suggestions
```sql
-- Check missing index recommendations
SELECT 
    mid.statement AS table_name,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    migs.user_seeks,
    migs.avg_total_user_cost,
    migs.avg_user_impact,
    'CREATE INDEX IX_' + REPLACE(REPLACE(REPLACE(mid.statement, '[', ''), ']', ''), '.', '_') + '_Missing' +
    ' ON ' + mid.statement + 
    ' (' + ISNULL(mid.equality_columns, '') + 
    CASE WHEN mid.inequality_columns IS NOT NULL THEN 
        CASE WHEN mid.equality_columns IS NOT NULL THEN ', ' ELSE '' END + mid.inequality_columns 
    ELSE '' END + ')' +
    CASE WHEN mid.included_columns IS NOT NULL THEN ' INCLUDE (' + mid.included_columns + ')' ELSE '' END AS create_statement
FROM sys.dm_db_missing_index_details mid
JOIN sys.dm_db_missing_index_groups mig ON mid.index_handle = mig.index_handle
JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
WHERE mid.statement LIKE '%YourTableName%'
ORDER BY migs.avg_total_user_cost * migs.avg_user_impact DESC
```

### Index Usage Statistics
```sql
-- Check how existing indexes are being used
SELECT 
    t.name AS table_name,
    i.name AS index_name,
    i.type_desc,
    ius.user_seeks,
    ius.user_scans,
    ius.user_lookups,
    ius.user_updates,
    ius.last_user_seek,
    ius.last_user_scan,
    ius.last_user_lookup
FROM sys.tables t
JOIN sys.indexes i ON t.object_id = i.object_id
LEFT JOIN sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id AND i.index_id = ius.index_id
WHERE t.name = 'YourTableName'
ORDER BY ius.user_seeks + ius.user_scans + ius.user_lookups DESC
```

## 📊 Performance Monitoring

### Top Resource-Consuming Queries
```sql
-- Top queries by logical reads (I/O intensive)
SELECT TOP 20
    qs.execution_count,
    qs.total_logical_reads,
    qs.avg_logical_reads,
    qs.total_elapsed_time / 1000 AS total_elapsed_time_seconds,
    qs.avg_elapsed_time / 1000 AS avg_elapsed_time_seconds,
    qt.text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.avg_logical_reads DESC
```

### Plan Cache Analysis
```sql
-- Find queries with high CPU usage
SELECT TOP 20
    qs.execution_count,
    qs.total_worker_time / 1000 AS total_cpu_time_ms,
    qs.avg_worker_time / 1000 AS avg_cpu_time_ms,
    qs.max_worker_time / 1000 AS max_cpu_time_ms,
    qt.text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.avg_worker_time DESC
```

## 🔧 Execution Plan Analysis

### Parameter Sniffing Detection
```sql
-- Find queries with parameter sniffing issues
SELECT 
    qs.execution_count,
    qs.min_elapsed_time / 1000.0 AS min_elapsed_seconds,
    qs.max_elapsed_time / 1000.0 AS max_elapsed_seconds,
    qs.avg_elapsed_time / 1000.0 AS avg_elapsed_seconds,
    (qs.max_elapsed_time - qs.min_elapsed_time) / 1000.0 AS elapsed_variation_seconds,
    qt.text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qs.execution_count > 10
  AND (qs.max_elapsed_time - qs.min_elapsed_time) > (qs.avg_elapsed_time * 2)
ORDER BY elapsed_variation_seconds DESC
```

## 💾 Usage Notes

**How to Use These Queries:**
1. Replace `YourTableName` with the actual table you're analyzing
2. Run during low-activity periods for accurate results
3. Missing index suggestions should be carefully evaluated before implementation
4. Use these queries to build your daily monitoring routine

**Best Practices:**
- Save results to compare over time
- Document any indexes you create based on these recommendations
- Review index usage statistics quarterly to identify unused indexes

---

**Related Learning:**
- [[Phase 1 - Performance Tuning]]
- [[SQL Learning Dashboard]]
- Daily session notes for context on when/why these were used