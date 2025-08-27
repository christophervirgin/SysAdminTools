# ================================================================
# SQL Server Column Inventory and Sensitive Data Detection Script
# PowerShell Data Collection Script
# ================================================================

param(
    [string]$CacheServer = "YourCacheServer",
    [string]$CacheDatabase = "ColumnInventory",
    [string]$SCCMServer = "YourSCCMServer",
    [string]$SCCMDatabase = "CM_YourSiteCode",
    [string]$OutputPath = "C:\ColumnInventory",
    [switch]$UseCachedInstances,
    [switch]$SkipSCCMQuery,
    [int]$ConnectionTimeout = 30,
    [int]$QueryTimeout = 60
)

# Import required modules
Import-Module SqlServer -ErrorAction SilentlyContinue
if (-not (Get-Module SqlServer)) {
    Write-Error "SqlServer module not found. Please install with: Install-Module -Name SqlServer"
    exit 1
}

# Create output directory
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# ================================================================
# HELPER FUNCTIONS
# ================================================================

function Log-Message {
    param($Message, $Level = "Info")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "Error" { Write-Host $logMessage -ForegroundColor Red }
        "Warning" { Write-Host $logMessage -ForegroundColor Yellow }
        "Success" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor White }
    }
    
    # Also write to log file
    $logFile = Join-Path $OutputPath "inventory_log_$(Get-Date -Format 'yyyyMMdd').txt"
    Add-Content -Path $logFile -Value $logMessage
}

function Log-ConnectionAttempt {
    param($ServerName, $InstanceName, $Success, $ErrorNumber, $ErrorMessage, $DatabasesFound, $ColumnsInventoried, $Duration)
    
    $logQuery = @"
EXEC inventory.LogConnectionAttempt 
    @ServerName = '$($ServerName -replace "'", "''")',
    @InstanceName = '$($InstanceName -replace "'", "''")', 
    @Success = $Success,
    @ErrorNumber = $ErrorNumber,
    @ErrorMessage = '$($ErrorMessage -replace "'", "''")',
    @DatabasesFound = $DatabasesFound,
    @ColumnsInventoried = $ColumnsInventoried,
    @Duration_ms = $Duration
"@
    
    try {
        Invoke-Sqlcmd -ServerInstance $CacheServer -Database $CacheDatabase -Query $logQuery -ConnectionTimeout $ConnectionTimeout
    }
    catch {
        Log-Message "Failed to log connection attempt to cache: $_" "Warning"
    }
}

function Invoke-SensitiveDataAnalysis {
    param($ServerName, $InstanceName, $DatabaseName, $SchemaName, $TableName, $ColumnName, $DataType)
    
    $analysisQuery = @"
EXEC inventory.AnalyzeSensitiveData 
    @ServerName = '$($ServerName -replace "'", "''")',
    @InstanceName = '$($InstanceName -replace "'", "''")',
    @DatabaseName = '$($DatabaseName -replace "'", "''")', 
    @SchemaName = '$($SchemaName -replace "'", "''")',
    @TableName = '$($TableName -replace "'", "''")',
    @ColumnName = '$($ColumnName -replace "'", "''")',
    @DataType = '$($DataType -replace "'", "''")'
"@
    
    try {
        Invoke-Sqlcmd -ServerInstance $CacheServer -Database $CacheDatabase -Query $analysisQuery -ConnectionTimeout $ConnectionTimeout
    }
    catch {
        Log-Message "Failed to analyze sensitive data for $ColumnName : $_" "Warning"
    }
}

function Get-InstancesFromSCCM {
    if ($SkipSCCMQuery) {
        Log-Message "Skipping SCCM query as requested"
        return @()
    }
    
    Log-Message "Querying SCCM for SQL Server instances..."
    
    $sccmQuery = @"
SELECT DISTINCT
    s.Name0 AS ServerName,
    svc.Name0 AS ServiceName,
    CASE 
        WHEN svc.Name0 = 'MSSQLSERVER' THEN 'DEFAULT'
        WHEN svc.Name0 LIKE 'MSSQL$%' THEN SUBSTRING(svc.Name0, 7, LEN(svc.Name0))
        ELSE svc.Name0
    END AS InstanceName,
    CASE 
        WHEN svc.Name0 = 'MSSQLSERVER' THEN s.Name0
        WHEN svc.Name0 LIKE 'MSSQL$%' THEN s.Name0 + '\' + SUBSTRING(svc.Name0, 7, LEN(svc.Name0))
        ELSE s.Name0
    END AS FullInstanceName
FROM v_R_System s
INNER JOIN v_GS_SERVICE svc ON s.ResourceID = svc.ResourceID
WHERE svc.Name0 LIKE 'MSSQL%'
  AND svc.Name0 NOT LIKE '%Agent%'
  AND svc.Name0 NOT LIKE '%Browser%'
  AND svc.Name0 NOT LIKE '%Writer%'
  AND svc.State0 = 'Running'
  AND s.Operating_System_Name_and0 LIKE '%Server%'
ORDER BY s.Name0, InstanceName
"@
    
    try {
        $instances = Invoke-Sqlcmd -ServerInstance $SCCMServer -Database $SCCMDatabase -Query $sccmQuery -ConnectionTimeout $ConnectionTimeout
        Log-Message "Found $($instances.Count) SQL Server instances in SCCM" "Success"
        return $instances
    }
    catch {
        Log-Message "Failed to query SCCM: $_" "Error"
        return @()
    }
}

function Get-InstancesFromCache {
    Log-Message "Retrieving instances from cache..."
    
    $cacheQuery = @"
SELECT ServerName, InstanceName, FullInstanceName 
FROM inventory.SQLInstances 
WHERE IsActive = 1 
  AND (ConsecutiveFailures < 3 OR LastSuccessfulConnection > DATEADD(day, -7, GETDATE()))
ORDER BY ServerName, InstanceName
"@
    
    try {
        $instances = Invoke-Sqlcmd -ServerInstance $CacheServer -Database $CacheDatabase -Query $cacheQuery -ConnectionTimeout $ConnectionTimeout
        Log-Message "Found $($instances.Count) instances in cache" "Success"
        return $instances
    }
    catch {
        Log-Message "Failed to query cache: $_" "Error"
        return @()
    }
}

# ================================================================
# MAIN SCRIPT
# ================================================================

Log-Message "Starting SQL Server Column Inventory process"
Log-Message "Output directory: $OutputPath"
Log-Message "Cache Server: $CacheServer"
Log-Message "Cache Database: $CacheDatabase"

# Get list of instances to process
if ($UseCachedInstances) {
    $servers = Get-InstancesFromCache
} else {
    $servers = Get-InstancesFromSCCM
    if ($servers.Count -eq 0) {
        Log-Message "No instances from SCCM, falling back to cache"
        $servers = Get-InstancesFromCache
    }
}

if ($servers.Count -eq 0) {
    Log-Message "No SQL Server instances found to process" "Error"
    exit 1
}

# Initialize results collection
$allResults = @()
$processedCount = 0
$successCount = 0
$failedCount = 0

# Process each server
foreach ($server in $servers) {
    $processedCount++
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $totalDatabases = 0
    $totalColumns = 0
    
    Log-Message "Processing $($server.FullInstanceName) ($processedCount of $($servers.Count))..."
    
    try {
        # Test connection first
        $testQuery = "SELECT @@VERSION AS SqlVersion, @@SERVERNAME AS ServerName"
        $serverInfo = Invoke-Sqlcmd -ServerInstance $server.FullInstanceName -Query $testQuery -ConnectionTimeout $ConnectionTimeout
        
        Log-Message "Connected successfully. SQL Version: $($serverInfo.SqlVersion.Split("`n")[0])"
        
        # Get databases (exclude system and reporting databases)
        $databaseQuery = @"
SELECT name, database_id, create_date, collation_name
FROM sys.databases 
WHERE state = 0 
  AND database_id > 4 
  AND name NOT IN ('ReportServer', 'ReportServerTempDB', 'SSISDB')
  AND is_read_only = 0
ORDER BY name
"@
        
        $databases = Invoke-Sqlcmd -ServerInstance $server.FullInstanceName -Query $databaseQuery -ConnectionTimeout $ConnectionTimeout
        $totalDatabases = $databases.Count
        
        Log-Message "Found $totalDatabases user databases"
        
        # Process each database
        foreach ($db in $databases) {
            Log-Message "  Scanning database: $($db.name)"
            
            $columnQuery = @"
SELECT 
    s.name AS SchemaName,
    t.name AS TableName,
    c.name AS ColumnName,
    TYPE_NAME(c.system_type_id) AS DataType,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    c.is_identity,
    CASE WHEN pk.column_id IS NOT NULL THEN 1 ELSE 0 END AS IsPrimaryKey
FROM sys.columns c
INNER JOIN sys.tables t ON c.object_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
LEFT JOIN (
    SELECT ic.object_id, ic.column_id
    FROM sys.index_columns ic
    INNER JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    WHERE i.is_primary_key = 1
) pk ON c.object_id = pk.object_id AND c.column_id = pk.column_id
WHERE t.is_ms_shipped = 0
  AND s.name NOT IN ('sys', 'INFORMATION_SCHEMA')
ORDER BY s.name, t.name, c.column_id
"@
            
            try {
                $columns = Invoke-Sqlcmd -ServerInstance $server.FullInstanceName -Database $db.name -Query $columnQuery -ConnectionTimeout $QueryTimeout
                
                foreach ($col in $columns) {
                    # Analyze each column for sensitive data patterns
                    Invoke-SensitiveDataAnalysis -ServerName $server.ServerName -InstanceName $server.InstanceName -DatabaseName $db.name -SchemaName $col.SchemaName -TableName $col.TableName -ColumnName $col.ColumnName -DataType $col.DataType
                    
                    # Add to results collection
                    $result = [PSCustomObject]@{
                        ServerName = $server.ServerName
                        InstanceName = $server.InstanceName
                        FullInstanceName = $server.FullInstanceName
                        DatabaseName = $db.name
                        DatabaseId = $db.database_id
                        CreateDate = $db.create_date
                        Collation = $db.collation_name
                        SchemaName = $col.SchemaName
                        TableName = $col.TableName
                        ColumnName = $col.ColumnName
                        DataType = $col.DataType
                        MaxLength = $col.max_length
                        Precision = $col.precision
                        Scale = $col.scale
                        IsNullable = $col.is_nullable
                        IsIdentity = $col.is_identity
                        IsPrimaryKey = $col.IsPrimaryKey
                        ScanDate = Get-Date
                    }
                    $allResults += $result
                }
                
                $totalColumns += $columns.Count
                Log-Message "    Found $($columns.Count) columns"
            }
            catch {
                Log-Message "    Failed to scan database $($db.name): $_" "Warning"
            }
        }
        
        $stopwatch.Stop()
        $successCount++
        
        # Log successful connection
        Log-ConnectionAttempt -ServerName $server.ServerName -InstanceName $server.InstanceName -Success $true -DatabasesFound $totalDatabases -ColumnsInventoried $totalColumns -Duration $stopwatch.ElapsedMilliseconds
        
        Log-Message "✓ Success: $totalDatabases databases, $totalColumns columns ($(([math]::Round($stopwatch.ElapsedMilliseconds/1000,1))) seconds)" "Success"
    }
    catch {
        $stopwatch.Stop()
        $failedCount++
        $errorNum = if ($_.Exception.InnerException.Number) { $_.Exception.InnerException.Number } else { $null }
        
        # Log failed connection
        Log-ConnectionAttempt -ServerName $server.ServerName -InstanceName $server.InstanceName -Success $false -ErrorNumber $errorNum -ErrorMessage $_.Exception.Message -Duration $stopwatch.ElapsedMilliseconds
        
        Log-Message "✗ Failed: $($_.Exception.Message)" "Error"
    }
}

# ================================================================
# EXPORT RESULTS
# ================================================================

if ($allResults.Count -gt 0) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputFile = Join-Path $OutputPath "column_inventory_$timestamp.csv"
    
    Log-Message "Exporting $($allResults.Count) column records to: $outputFile"
    $allResults | Export-Csv -Path $outputFile -NoTypeInformation
    
    # Create summary file
    $summaryFile = Join-Path $OutputPath "inventory_summary_$timestamp.txt"
    $summary = @"
SQL Server Column Inventory Summary
Generated: $(Get-Date)

Servers Processed: $processedCount
Successful Connections: $successCount  
Failed Connections: $failedCount
Total Columns Inventoried: $($allResults.Count)
Total Databases Scanned: $($allResults | Select-Object ServerName, DatabaseName -Unique).Count
Total Tables Scanned: $($allResults | Select-Object ServerName, DatabaseName, TableName -Unique).Count

Output Files:
- Column Inventory: $outputFile
- Log File: $(Join-Path $OutputPath "inventory_log_$(Get-Date -Format 'yyyyMMdd').txt")

Top 10 Most Common Column Names:
$($allResults | Group-Object ColumnName | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { "  $($_.Name): $($_.Count)" } | Out-String)

Data Types Distribution:
$($allResults | Group-Object DataType | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { "  $($_.Name): $($_.Count)" } | Out-String)
"@
    
    Set-Content -Path $summaryFile -Value $summary
    Log-Message "Summary saved to: $summaryFile"
} else {
    Log-Message "No data collected to export" "Warning"
}

# ================================================================
# COMPLETION
# ================================================================

$totalTime = (Get-Date) - $startTime
Log-Message "Inventory process completed in $($totalTime.ToString('mm\:ss'))"
Log-Message "Successfully processed: $successCount servers"
Log-Message "Failed to process: $failedCount servers"

if ($allResults.Count -gt 0) {
    Log-Message "Total columns inventoried: $($allResults.Count)" "Success"
    Log-Message "Run the following query on your cache database to view sensitive data findings:"
    Log-Message "SELECT * FROM inventory.SensitiveDataSummary ORDER BY RiskLevel, ColumnCount DESC"
} else {
    Log-Message "No column data was collected" "Warning"
}

# Return summary object for programmatic use
return [PSCustomObject]@{
    ProcessedServers = $processedCount
    SuccessfulConnections = $successCount
    FailedConnections = $failedCount  
    TotalColumns = $allResults.Count
    OutputFile = if ($allResults.Count -gt 0) { $outputFile } else { $null }
    Summary = $summary
}