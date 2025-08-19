WITH ExpensiveQueries AS (
    SELECT TOP 10
        qs.execution_count,
        qs.total_logical_reads,
        qs.total_elapsed_time,
        qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS avg_logical_reads,
        qs.total_elapsed_time / NULLIF(qs.execution_count, 0) AS avg_elapsed_time,
        qt.text AS query_text,
        qs.query_hash,
        qs.plan_handle
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
    WHERE qt.text LIKE '%YourTableName%'
    ORDER BY qs.total_logical_reads DESC
),
MissingIndexes AS (
    SELECT 
        mid.statement AS table_name,
        mid.equality_columns,
        mid.inequality_columns,
        mid.included_columns,
        migs.user_seeks,
        migs.avg_total_user_cost,
        migs.avg_user_impact,
        migs.avg_total_user_cost * migs.avg_user_impact AS impact_score,
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
)
SELECT 
    eq.execution_count,
    eq.total_logical_reads,
    eq.avg_logical_reads,
    eq.total_elapsed_time,
    eq.avg_elapsed_time,
    mi.avg_total_user_cost,
    mi.avg_user_impact,
    mi.impact_score,
    mi.user_seeks AS missing_index_seeks,
    LEFT(eq.query_text, 500) AS query_text_snippet,
    mi.create_statement AS suggested_index
FROM ExpensiveQueries eq
LEFT JOIN MissingIndexes mi 
    ON eq.query_text LIKE '%' + REPLACE(REPLACE(REPLACE(mi.table_name, '[', ''), ']', ''), '.', '%') + '%'
ORDER BY eq.total_logical_reads DESC, mi.impact_score DESC;