-- ================================================================
-- SQL Server Column Inventory and Sensitive Data Detection System
-- Sample Queries and Reports
-- ================================================================

-- ================================================================
-- BASIC SYSTEM HEALTH QUERIES
-- ================================================================

-- 1. Check system status
SELECT 'Instance Status' AS ReportType;
SELECT 
    HealthStatus,
    COUNT(*) AS InstanceCount,
    STRING_AGG(ServerName + '.' + InstanceName, ', ') AS Instances
FROM inventory.InstanceStatus
GROUP BY HealthStatus
ORDER BY 
    CASE HealthStatus 
        WHEN 'Critical' THEN 1
        WHEN 'Warning' THEN 2  
        WHEN 'Healthy' THEN 3
    END;

-- 2. Recent connection attempts
SELECT 'Recent Connection Attempts' AS ReportType;
SELECT TOP 20
    si.ServerName,
    si.InstanceName,
    cl.AttemptDate,
    cl.Success,
    cl.ErrorMessage,
    cl.DatabasesFound,
    cl.ColumnsInventoried,
    cl.Duration_ms
FROM inventory.ConnectionLog cl
INNER JOIN inventory.SQLInstances si ON cl.InstanceID = si.InstanceID
ORDER BY cl.AttemptDate DESC;

-- ================================================================
-- SENSITIVE DATA ANALYSIS QUERIES
-- ================================================================

-- 3. Executive Summary - Sensitive Data by Risk Level
SELECT 'Sensitive Data Risk Summary' AS ReportType;
SELECT 
    RiskLevel,
    ColumnCount,
    DatabaseCount,
    ServerCount,
    ComplianceFrameworks
FROM inventory.SensitiveDataSummary
ORDER BY 
    CASE RiskLevel 
        WHEN 'Critical' THEN 1
        WHEN 'High' THEN 2
        WHEN 'Medium' THEN 3
        WHEN 'Low' THEN 4
    END,
    ColumnCount DESC;

-- 4. Critical Findings Requiring Immediate Attention
SELECT 'CRITICAL FINDINGS - Immediate Action Required' AS ReportType;
SELECT 
    ServerName + '.' + InstanceName AS Instance,
    DatabaseName,
    CriticalColumns,
    Categories,
    ComplianceImpact,
    LEFT(AffectedColumns, 100) + CASE WHEN LEN(AffectedColumns) > 100 THEN '...' ELSE '' END AS SampleColumns
FROM inventory.CriticalFindings
ORDER BY CriticalColumns DESC;

-- 5. Detailed Sensitive Data Inventory
SELECT 'Detailed Sensitive Data Inventory' AS ReportType;
SELECT TOP 50
    ServerName,
    DatabaseName,
    SchemaName + '.' + TableName AS TablePath,
    ColumnName,
    DataType,
    CategoryName,
    RiskLevel,
    ComplianceFramework,
    ReviewStatus,
    DetectedDate
FROM inventory.SensitiveDataInventory
WHERE RiskLevel IN ('Critical', 'High')
ORDER BY 
    CASE RiskLevel 
        WHEN 'Critical' THEN 1
        WHEN 'High' THEN 2
    END,
    DetectedDate DESC;

-- 6. Compliance Framework Impact Analysis
SELECT 'Compliance Framework Analysis' AS ReportType;
WITH ComplianceBreakdown AS (
    SELECT 
        TRIM(value) AS Framework,
        RiskLevel,
        COUNT(*) AS ColumnCount
    FROM inventory.SensitiveColumns
    CROSS APPLY STRING_SPLIT(ComplianceFramework, ',')
    WHERE IsConfirmed IS NULL OR IsConfirmed = 1
    GROUP BY TRIM(value), RiskLevel
)
SELECT 
    Framework,
    SUM(ColumnCount) AS TotalColumns,
    SUM(CASE WHEN RiskLevel = 'Critical' THEN ColumnCount ELSE 0 END) AS CriticalColumns,
    SUM(CASE WHEN RiskLevel = 'High' THEN ColumnCount ELSE 0 END) AS HighColumns,
    SUM(CASE WHEN RiskLevel = 'Medium' THEN ColumnCount ELSE 0 END) AS MediumColumns,
    SUM(CASE WHEN RiskLevel = 'Low' THEN ColumnCount ELSE 0 END) AS LowColumns
FROM ComplianceBreakdown
GROUP BY Framework
ORDER BY TotalColumns DESC;

-- ================================================================
-- COLUMN ANALYSIS QUERIES  
-- ================================================================

-- 7. Most Common Column Names (Potential Patterns)
SELECT 'Most Common Column Names' AS ReportType;
SELECT TOP 20
    sc.ColumnName,
    COUNT(*) AS Occurrences,
    COUNT(DISTINCT sc.ServerName) AS ServerCount,
    COUNT(DISTINCT sc.DatabaseName) AS DatabaseCount,
    CASE WHEN sens.ColumnName IS NOT NULL THEN 'SENSITIVE' ELSE 'Not Flagged' END AS SensitiveStatus
FROM (
    -- This would come from your CSV data - create a temporary table
    -- For now, showing the structure
    SELECT 'Example' AS ColumnName, 'Server1' AS ServerName, 'DB1' AS DatabaseName
    WHERE 1=0
) sc
LEFT JOIN inventory.SensitiveColumns sens ON sc.ColumnName = sens.ColumnName
GROUP BY sc.ColumnName, CASE WHEN sens.ColumnName IS NOT NULL THEN 'SENSITIVE' ELSE 'Not Flagged' END
ORDER BY COUNT(*) DESC;

-- 8. Data Type Distribution Analysis
SELECT 'Data Type Distribution' AS ReportType;
-- Create temporary table from your CSV export first, then run:
/*
SELECT 
    DataType,
    COUNT(*) AS ColumnCount,
    COUNT(DISTINCT ServerName) AS ServerCount,
    COUNT(DISTINCT DatabaseName) AS DatabaseCount,
    AVG(CAST(MaxLength AS FLOAT)) AS AvgLength,
    COUNT(CASE WHEN IsNullable = 1 THEN 1 END) AS NullableCount
FROM #ColumnInventory  -- Your imported CSV data
GROUP BY DataType
ORDER BY COUNT(*) DESC;
*/

-- 9. Server Inventory Coverage Report
SELECT 'Server Coverage Analysis' AS ReportType;
SELECT 
    si.ServerName,
    si.InstanceName,
    si.LastSuccessfulConnection,
    si.ConsecutiveFailures,
    COALESCE(recent.DatabasesFound, 0) AS DatabasesFound,
    COALESCE(recent.ColumnsInventoried, 0) AS ColumnsInventoried,
    COALESCE(sens.SensitiveColumns, 0) AS SensitiveColumnsFound
FROM inventory.SQLInstances si
LEFT JOIN (
    SELECT 
        cl.InstanceID,
        cl.DatabasesFound,
        cl.ColumnsInventoried,
        ROW_NUMBER() OVER (PARTITION BY cl.InstanceID ORDER BY cl.AttemptDate DESC) as rn
    FROM inventory.ConnectionLog cl
    WHERE cl.Success = 1
) recent ON si.InstanceID = recent.InstanceID AND recent.rn = 1
LEFT JOIN (
    SELECT 
        ServerName,
        InstanceName,
        COUNT(*) AS SensitiveColumns
    FROM inventory.SensitiveColumns
    WHERE IsConfirmed IS NULL OR IsConfirmed = 1
    GROUP BY ServerName, InstanceName
) sens ON si.ServerName = sens.ServerName AND si.InstanceName = sens.InstanceName
WHERE si.IsActive = 1
ORDER BY si.LastSuccessfulConnection DESC;

-- ================================================================
-- SECURITY AND AUDIT QUERIES
-- ================================================================

-- 10. Password and Authentication Columns (CRITICAL)
SELECT 'Password and Authentication Columns - CRITICAL REVIEW' AS ReportType;
SELECT 
    ServerName,
    InstanceName,
    DatabaseName,
    SchemaName + '.' + TableName + '.' + ColumnName AS FullPath,
    DataType,
    PatternName,
    DetectedDate,
    ReviewStatus
FROM inventory.SensitiveDataInventory
WHERE CategoryName = 'Auth'
ORDER BY DetectedDate DESC;

-- 11. Financial Data Exposure
SELECT 'Financial Data Exposure Analysis' AS ReportType;
SELECT 
    ServerName,
    DatabaseName,
    COUNT(*) AS FinancialColumns,
    STRING_AGG(ColumnName, ', ') AS ColumnList
FROM inventory.SensitiveColumns
WHERE CategoryName = 'Financial'
  AND (IsConfirmed IS NULL OR IsConfirmed = 1)
GROUP BY ServerName, DatabaseName
ORDER BY COUNT(*) DESC;

-- 12. PII Distribution Across Environment
SELECT 'PII Distribution Analysis' AS ReportType;
SELECT 
    sc.ServerName,
    COUNT(*) AS PIIColumns,
    COUNT(DISTINCT sc.DatabaseName) AS DatabasesWithPII,
    STRING_AGG(DISTINCT sc.PatternName, ', ') AS PIITypes
FROM inventory.SensitiveColumns sc
WHERE sc.CategoryName = 'PII'
  AND (sc.IsConfirmed IS NULL OR sc.IsConfirmed = 1)
GROUP BY sc.ServerName
ORDER BY COUNT(*) DESC;

-- ================================================================
-- REVIEW AND MAINTENANCE QUERIES
-- ================================================================

-- 13. Pending Review Items
SELECT 'Items Pending Review' AS ReportType;
SELECT 
    COUNT(*) AS PendingItems,
    COUNT(CASE WHEN RiskLevel = 'Critical' THEN 1 END) AS CriticalPending,
    COUNT(CASE WHEN RiskLevel = 'High' THEN 1 END) AS HighPending,
    MIN(DetectedDate) AS OldestDetection,
    MAX(DetectedDate) AS NewestDetection
FROM inventory.SensitiveColumns
WHERE IsConfirmed IS NULL;

-- Show details of pending items
SELECT TOP 20
    ServerName + '.' + DatabaseName AS Location,
    SchemaName + '.' + TableName + '.' + ColumnName AS FullPath,
    CategoryName,
    PatternName,
    RiskLevel,
    DetectedDate,
    DATEDIFF(day, DetectedDate, GETDATE()) AS DaysOld
FROM inventory.SensitiveColumns
WHERE IsConfirmed IS NULL
ORDER BY 
    CASE RiskLevel 
        WHEN 'Critical' THEN 1
        WHEN 'High' THEN 2
        WHEN 'Medium' THEN 3
        WHEN 'Low' THEN 4
    END,
    DetectedDate;

-- 14. False Positive Analysis
SELECT 'False Positive Analysis' AS ReportType;
SELECT 
    PatternName,
    COUNT(*) AS TotalDetections,
    COUNT(CASE WHEN IsConfirmed = 0 THEN 1 END) AS FalsePositives,
    COUNT(CASE WHEN IsConfirmed = 1 THEN 1 END) AS ConfirmedSensitive,
    COUNT(CASE WHEN IsConfirmed IS NULL THEN 1 END) AS PendingReview,
    CASE 
        WHEN COUNT(*) = 0 THEN 0
        ELSE CAST(COUNT(CASE WHEN IsConfirmed = 0 THEN 1 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))
    END AS FalsePositiveRate
FROM inventory.SensitiveColumns
GROUP BY PatternName
HAVING COUNT(*) > 5  -- Only patterns with enough data
ORDER BY FalsePositiveRate DESC;

-- ================================================================
-- MAINTENANCE AND CLEANUP SCRIPTS
-- ================================================================

-- 15. Update Pattern Performance (Run periodically)
-- Mark obvious false positives for common patterns
UPDATE inventory.SensitiveColumns
SET IsConfirmed = 0, ReviewedBy = 'System', ReviewedDate = GETDATE(), Notes = 'Auto-marked: System table or common non-sensitive pattern'
WHERE IsConfirmed IS NULL
  AND (
    SchemaName IN ('sys', 'INFORMATION_SCHEMA') OR
    TableName LIKE 'sys%' OR
    (CategoryName = 'Contact' AND ColumnName IN ('Title', 'Description', 'Notes')) OR
    (CategoryName = 'Employment' AND ColumnName IN ('Status', 'Type', 'Category'))
  );

-- 16. Cleanup old connection log entries (Run monthly)
DELETE FROM inventory.ConnectionLog
WHERE AttemptDate < DATEADD(month, -6, GETDATE());

-- 17. Archive old sensitive data findings (Run quarterly) 
-- Create archive table first:
/*
CREATE TABLE inventory.SensitiveColumns_Archive (
    LIKE inventory.SensitiveColumns INCLUDING ALL
);

INSERT INTO inventory.SensitiveColumns_Archive
SELECT * FROM inventory.SensitiveColumns
WHERE DetectedDate < DATEADD(month, -12, GETDATE())
  AND IsConfirmed = 0;

DELETE FROM inventory.SensitiveColumns
WHERE DetectedDate < DATEADD(month, -12, GETDATE())
  AND IsConfirmed = 0;
*/

-- ================================================================
-- EXAMPLE REVIEW WORKFLOW
-- ================================================================

-- 18. Review and confirm/reject findings
-- To confirm a finding as sensitive:
/*
UPDATE inventory.SensitiveColumns
SET IsConfirmed = 1, ReviewedBy = 'YourUsername', ReviewedDate = GETDATE(), Notes = 'Confirmed - contains actual sensitive data'
WHERE SensitiveColumnID = 123;
*/

-- To mark as false positive:
/*
UPDATE inventory.SensitiveColumns  
SET IsConfirmed = 0, ReviewedBy = 'YourUsername', ReviewedDate = GETDATE(), Notes = 'False positive - column name misleading'
WHERE SensitiveColumnID = 124;
*/

-- ================================================================
-- CUSTOM REPORTING EXAMPLES
-- ================================================================

-- 19. Create custom compliance report
SELECT 'Custom GDPR Compliance Report' AS ReportType;
WITH GDPRData AS (
    SELECT *
    FROM inventory.SensitiveColumns
    WHERE ComplianceFramework LIKE '%GDPR%'
      AND (IsConfirmed IS NULL OR IsConfirmed = 1)
)
SELECT 
    'GDPR Compliance Summary' AS Section,
    COUNT(*) AS TotalGDPRColumns,
    COUNT(DISTINCT ServerName) AS ServersAffected,
    COUNT(DISTINCT DatabaseName) AS DatabasesAffected,
    COUNT(CASE WHEN RiskLevel = 'Critical' THEN 1 END) AS CriticalIssues
FROM GDPRData
UNION ALL
SELECT 
    'By Category' AS Section,
    CategoryName,
    COUNT(*),
    NULL,
    NULL
FROM GDPRData
GROUP BY CategoryName;

-- 20. Generate audit trail report
SELECT 'Audit Trail Report' AS ReportType;
SELECT 
    'Review Activity Summary' AS Activity,
    COUNT(*) AS TotalReviewed,
    COUNT(CASE WHEN IsConfirmed = 1 THEN 1 END) AS ConfirmedSensitive,
    COUNT(CASE WHEN IsConfirmed = 0 THEN 1 END) AS FalsePositives,
    COUNT(DISTINCT ReviewedBy) AS ReviewersActive
FROM inventory.SensitiveColumns
WHERE ReviewedDate >= DATEADD(month, -1, GETDATE())
UNION ALL
SELECT 
    ReviewedBy,
    COUNT(*),
    COUNT(CASE WHEN IsConfirmed = 1 THEN 1 END),
    COUNT(CASE WHEN IsConfirmed = 0 THEN 1 END),
    NULL
FROM inventory.SensitiveColumns
WHERE ReviewedDate >= DATEADD(month, -1, GETDATE())
  AND ReviewedBy IS NOT NULL
GROUP BY ReviewedBy;

PRINT '========================================'
PRINT 'Sample queries completed!'
PRINT 'Key Views Available:'
PRINT '- inventory.InstanceStatus'
PRINT '- inventory.SensitiveDataSummary' 
PRINT '- inventory.SensitiveDataInventory'
PRINT '- inventory.CriticalFindings'
PRINT ''
PRINT 'Next Steps:'
PRINT '1. Run PowerShell script to collect data'
PRINT '2. Review critical findings'
PRINT '3. Confirm/reject sensitive data patterns'
PRINT '4. Generate compliance reports'
PRINT '========================================'