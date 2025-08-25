# PowerShell 7+ with nested parallelization

$instances = Invoke-Sqlcmd -ServerInstance "SCCMServer" -Database "CM_XXX" -Query @"
    SELECT DISTINCT
        s.Name0 AS ServerName,
        CASE 
            WHEN svc.Name0 = 'MSSQLSERVER' THEN s.Name0
            ELSE s.Name0 + '\' + SUBSTRING(svc.Name0, 7, LEN(svc.Name0))
        END AS FullInstanceName
    FROM v_R_System s
    INNER JOIN v_GS_SERVICE svc ON s.ResourceID = svc.ResourceID
    WHERE svc.Name0 LIKE 'MSSQL%'
      AND svc.Name0 NOT LIKE '%Agent%'
      AND svc.State0 = 'Running'
"@

$centralServer = "YourInventoryServer"
$inventoryDB = "YourInventoryDB"

# Process instances in parallel
$results = $instances | ForEach-Object -Parallel {
    $instance = $_.FullInstanceName
    $serverName = $_.ServerName
    
    try {
        # Get databases
        $databases = Invoke-Sqlcmd -ServerInstance $instance -Query "
            SELECT name FROM sys.databases 
            WHERE state = 0 AND database_id > 4" -ConnectionTimeout 10
        
        # Process databases in parallel for this instance
        $dbResults = $databases | ForEach-Object -Parallel {
            $db = $_.name
            $inst = $using:instance
            
            try {
                $columns = Invoke-Sqlcmd -ServerInstance $inst -Database $db -Query "
                    SELECT 
                        '$inst' AS Instance,
                        DB_NAME() AS DatabaseName,
                        s.name AS SchemaName,
                        t.name AS TableName,
                        c.name AS ColumnName,
                        TYPE_NAME(c.system_type_id) AS DataType,
                        c.max_length,
                        c.precision,
                        c.scale
                    FROM sys.columns c
                    INNER JOIN sys.tables t ON c.object_id = t.object_id
                    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
                    WHERE t.is_ms_shipped = 0" -ConnectionTimeout 5
                
                @{
                    Database = $db
                    Success = $true
                    Columns = $columns
                    Count = $columns.Count
                }
            }
            catch {
                @{
                    Database = $db
                    Success = $false
                    Error = $_.Exception.Message
                }
            }
        } -ThrottleLimit 5
        
        # Log success
        $dbCount = ($dbResults | Where Success).Count
        $columnCount = ($dbResults.Columns | Measure).Count
        
        Invoke-Sqlcmd -ServerInstance $using:centralServer -Database $using:inventoryDB -Query "
            EXEC inventory.LogConnectionAttempt 
                @ServerName = '$serverName',
                @InstanceName = '$($instance -replace '.*\\', 'DEFAULT')',
                @Success = 1,
                @DatabasesFound = $dbCount,
                @ColumnsInventoried = $columnCount"
        
        # Return results
        @{
            Instance = $instance
            Success = $true
            Databases = $dbResults
        }
    }
    catch {
        # Log failure
        Invoke-Sqlcmd -ServerInstance $using:centralServer -Database $using:inventoryDB -Query "
            EXEC inventory.LogConnectionAttempt 
                @ServerName = '$serverName',
                @InstanceName = '$($instance -replace '.*\\', 'DEFAULT')',
                @Success = 0,
                @ErrorMessage = '$($_.Exception.Message -replace "'", "''")''"
        
        @{
            Instance = $instance
            Success = $false
            Error = $_.Exception.Message
        }
    }
} -ThrottleLimit 10

# Flatten and bulk insert column inventory
$allColumns = $results | Where Success | ForEach { 
    $_.Databases | Where Success | ForEach { $_.Columns } 
}

$allColumns | Write-SqlTableData -ServerInstance $centralServer -DatabaseName $inventoryDB -SchemaName inventory -TableName ColumnInventory -Force