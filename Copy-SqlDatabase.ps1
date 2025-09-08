<#
.SYNOPSIS
    Copy SQL Database from one server to another with selective object copying
.DESCRIPTION
    This script provides flexible options to copy a SQL database from source to destination
    with various levels of granularity - full backup/restore, schema only, data only, or
    selective object copying.
.PARAMETER SourceServer
    Source SQL Server instance name
.PARAMETER SourceDatabase
    Source database name
.PARAMETER DestinationServer
    Destination SQL Server instance name
.PARAMETER DestinationDatabase
    Destination database name
.PARAMETER CopyMode
    Mode of copy operation: Full, SchemaOnly, DataOnly, Selective
.EXAMPLE
    .\Copy-SqlDatabase.ps1 -SourceServer "PROD01" -SourceDatabase "MyDB" -DestinationServer "DEV01" -DestinationDatabase "MyDB_Dev" -CopyMode "Full"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourceServer,
    
    [Parameter(Mandatory=$true)]
    [string]$SourceDatabase,
    
    [Parameter(Mandatory=$true)]
    [string]$DestinationServer,
    
    [Parameter(Mandatory=$true)]
    [string]$DestinationDatabase,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("Full", "SchemaOnly", "DataOnly", "Selective", "Custom")]
    [string]$CopyMode,
    
    [Parameter(Mandatory=$false)]
    [string]$BackupPath = "C:\SQLBackups",
    
    [Parameter(Mandatory=$false)]
    [PSCredential]$SourceCredential,
    
    [Parameter(Mandatory=$false)]
    [PSCredential]$DestinationCredential,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseCompression = $true,
    
    [Parameter(Mandatory=$false)]
    [switch]$OverwriteDestination = $false
)

# Import required modules
Import-Module dbatools -ErrorAction Stop

# Configuration class for selective copying
class CopyConfiguration {
    [bool]$CopyTables = $true
    [bool]$CopyViews = $true
    [bool]$CopyStoredProcedures = $true
    [bool]$CopyFunctions = $true
    [bool]$CopyIndexes = $true
    [bool]$CopyTriggers = $true
    [bool]$CopyConstraints = $true
    [bool]$CopyPermissions = $true
    [bool]$CopyUsers = $false
    [bool]$CopyLogins = $false
    [bool]$CopyData = $true
    [string[]]$IncludeTables = @()
    [string[]]$ExcludeTables = @()
    [string[]]$IncludeSchemas = @()
    [string[]]$ExcludeSchemas = @()
    [hashtable]$TableDataFilters = @{}
}

# Function to get custom configuration from user
function Get-CustomConfiguration {
    $config = [CopyConfiguration]::new()
    
    Write-Host "`n=== Database Copy Configuration ===" -ForegroundColor Cyan
    
    # Schema objects
    Write-Host "`nSchema Objects:" -ForegroundColor Yellow
    $config.CopyTables = (Read-Host "Copy Tables? (Y/N) [Y]") -ne 'N'
    $config.CopyViews = (Read-Host "Copy Views? (Y/N) [Y]") -ne 'N'
    $config.CopyStoredProcedures = (Read-Host "Copy Stored Procedures? (Y/N) [Y]") -ne 'N'
    $config.CopyFunctions = (Read-Host "Copy Functions? (Y/N) [Y]") -ne 'N'
    $config.CopyIndexes = (Read-Host "Copy Indexes? (Y/N) [Y]") -ne 'N'
    $config.CopyTriggers = (Read-Host "Copy Triggers? (Y/N) [Y]") -ne 'N'
    $config.CopyConstraints = (Read-Host "Copy Constraints? (Y/N) [Y]") -ne 'N'
    
    # Security objects
    Write-Host "`nSecurity Objects:" -ForegroundColor Yellow
    $config.CopyPermissions = (Read-Host "Copy Permissions? (Y/N) [Y]") -ne 'N'
    $config.CopyUsers = (Read-Host "Copy Database Users? (Y/N) [N]") -eq 'Y'
    $config.CopyLogins = (Read-Host "Copy Server Logins? (Y/N) [N]") -eq 'Y'
    
    # Data options
    Write-Host "`nData Options:" -ForegroundColor Yellow
    $config.CopyData = (Read-Host "Copy Table Data? (Y/N) [Y]") -ne 'N'
    
    if ($config.CopyTables -and $config.CopyData) {
        $includeSpecific = Read-Host "Include specific tables only? (Y/N) [N]"
        if ($includeSpecific -eq 'Y') {
            $tables = Read-Host "Enter comma-separated table names (schema.table)"
            $config.IncludeTables = $tables -split ',' | ForEach-Object { $_.Trim() }
        }
        
        $excludeSpecific = Read-Host "Exclude specific tables? (Y/N) [N]"
        if ($excludeSpecific -eq 'Y') {
            $tables = Read-Host "Enter comma-separated table names to exclude"
            $config.ExcludeTables = $tables -split ',' | ForEach-Object { $_.Trim() }
        }
    }
    
    return $config
}

# Function to perform full backup and restore
function Copy-FullBackupRestore {
    param(
        [string]$SourceServer,
        [string]$SourceDatabase,
        [string]$DestinationServer,
        [string]$DestinationDatabase,
        [string]$BackupPath,
        [PSCredential]$SourceCredential,
        [PSCredential]$DestinationCredential,
        [bool]$UseCompression,
        [bool]$OverwriteDestination
    )
    
    try {
        Write-Host "`nStarting Full Backup and Restore..." -ForegroundColor Green
        
        # Connect to servers
        $sourceConn = Connect-DbaInstance -SqlInstance $SourceServer -SqlCredential $SourceCredential
        $destConn = Connect-DbaInstance -SqlInstance $DestinationServer -SqlCredential $DestinationCredential
        
        # Create backup filename
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupFile = Join-Path $BackupPath "$($SourceDatabase)_$timestamp.bak"
        
        # Perform backup
        Write-Host "Backing up $SourceDatabase to $backupFile..." -ForegroundColor Yellow
        $backup = Backup-DbaDatabase -SqlInstance $sourceConn -Database $SourceDatabase `
            -Path $BackupPath -FilePath $backupFile -CompressBackup:$UseCompression `
            -Verify -ErrorAction Stop
        
        if ($backup.BackupComplete -eq $true) {
            Write-Host "Backup completed successfully!" -ForegroundColor Green
        } else {
            throw "Backup failed!"
        }
        
        # Check if destination database exists
        $destDb = Get-DbaDatabase -SqlInstance $destConn -Database $DestinationDatabase
        if ($destDb -and -not $OverwriteDestination) {
            throw "Destination database exists! Use -OverwriteDestination to replace it."
        }
        
        # Restore database
        Write-Host "Restoring to $DestinationDatabase on $DestinationServer..." -ForegroundColor Yellow
        $restore = Restore-DbaDatabase -SqlInstance $destConn -Path $backupFile `
            -DatabaseName $DestinationDatabase -ReplaceDatabase -ErrorAction Stop
        
        if ($restore.RestoreComplete -eq $true) {
            Write-Host "Restore completed successfully!" -ForegroundColor Green
        } else {
            throw "Restore failed!"
        }
        
        # Clean up backup file if needed
        if (Test-Path $backupFile) {
            Remove-Item $backupFile -Force
            Write-Host "Backup file cleaned up." -ForegroundColor Gray
        }
        
    } catch {
        Write-Error "Full Backup/Restore failed: $_"
        throw
    }
}

# Function to copy schema only
function Copy-SchemaOnly {
    param(
        [string]$SourceServer,
        [string]$SourceDatabase,
        [string]$DestinationServer,
        [string]$DestinationDatabase,
        [PSCredential]$SourceCredential,
        [PSCredential]$DestinationCredential,
        [CopyConfiguration]$Config
    )
    
    try {
        Write-Host "`nCopying Schema Only..." -ForegroundColor Green
        
        # Connect to servers
        $sourceConn = Connect-DbaInstance -SqlInstance $SourceServer -SqlCredential $SourceCredential
        $destConn = Connect-DbaInstance -SqlInstance $DestinationServer -SqlCredential $DestinationCredential
        
        # Create destination database if it doesn't exist
        $destDb = Get-DbaDatabase -SqlInstance $destConn -Database $DestinationDatabase
        if (-not $destDb) {
            Write-Host "Creating destination database..." -ForegroundColor Yellow
            New-DbaDatabase -SqlInstance $destConn -Name $DestinationDatabase
        }
        
        # Script out schema objects
        $scriptingOptions = New-DbaScriptingOption
        $scriptingOptions.ScriptData = $false
        $scriptingOptions.ScriptSchema = $true
        $scriptingOptions.ScriptIndexes = $Config.CopyIndexes
        $scriptingOptions.ScriptTriggers = $Config.CopyTriggers
        $scriptingOptions.DriAll = $Config.CopyConstraints
        $scriptingOptions.Permissions = $Config.CopyPermissions
        
        # Export schema
        Write-Host "Exporting schema objects..." -ForegroundColor Yellow
        $export = Export-DbaScript -InputObject (Get-DbaDatabase -SqlInstance $sourceConn -Database $SourceDatabase) `
            -ScriptingOption $scriptingOptions -Passthru
        
        # Execute schema scripts on destination
        Write-Host "Creating schema objects on destination..." -ForegroundColor Yellow
        foreach ($script in $export) {
            Invoke-DbaQuery -SqlInstance $destConn -Database $DestinationDatabase -Query $script
        }
        
        Write-Host "Schema copy completed!" -ForegroundColor Green
        
    } catch {
        Write-Error "Schema copy failed: $_"
        throw
    }
}

# Function to copy data only
function Copy-DataOnly {
    param(
        [string]$SourceServer,
        [string]$SourceDatabase,
        [string]$DestinationServer,
        [string]$DestinationDatabase,
        [PSCredential]$SourceCredential,
        [PSCredential]$DestinationCredential,
        [CopyConfiguration]$Config
    )
    
    try {
        Write-Host "`nCopying Data Only..." -ForegroundColor Green
        
        # Connect to servers
        $sourceConn = Connect-DbaInstance -SqlInstance $SourceServer -SqlCredential $SourceCredential
        $destConn = Connect-DbaInstance -SqlInstance $DestinationServer -SqlCredential $DestinationCredential
        
        # Get list of tables to copy
        $tables = Get-DbaDbTable -SqlInstance $sourceConn -Database $SourceDatabase
        
        # Filter tables based on configuration
        if ($Config.IncludeTables.Count -gt 0) {
            $tables = $tables | Where-Object { 
                "$($_.Schema).$($_.Name)" -in $Config.IncludeTables 
            }
        }
        
        if ($Config.ExcludeTables.Count -gt 0) {
            $tables = $tables | Where-Object { 
                "$($_.Schema).$($_.Name)" -notin $Config.ExcludeTables 
            }
        }
        
        # Copy data for each table
        foreach ($table in $tables) {
            $tableName = "$($table.Schema).$($table.Name)"
            Write-Host "Copying data for $tableName..." -ForegroundColor Yellow
            
            try {
                # Disable constraints temporarily
                Invoke-DbaQuery -SqlInstance $destConn -Database $DestinationDatabase `
                    -Query "ALTER TABLE $tableName NOCHECK CONSTRAINT ALL"
                
                # Truncate destination table
                Invoke-DbaQuery -SqlInstance $destConn -Database $DestinationDatabase `
                    -Query "TRUNCATE TABLE $tableName"
                
                # Copy data using bulk copy
                $copyParams = @{
                    SqlInstance = $destConn
                    Destination = $DestinationDatabase
                    DestinationTable = $tableName
                    Query = "SELECT * FROM $tableName"
                    QueryTimeout = 0
                    BulkCopyTimeout = 0
                    EnableException = $true
                }
                
                # Add WHERE clause if filter exists
                if ($Config.TableDataFilters.ContainsKey($tableName)) {
                    $copyParams.Query = "SELECT * FROM $tableName WHERE $($Config.TableDataFilters[$tableName])"
                }
                
                # Execute bulk copy
                $sourceData = Invoke-DbaQuery -SqlInstance $sourceConn -Database $SourceDatabase `
                    -Query $copyParams.Query -As DataTable
                
                Write-DbaDataTable -SqlInstance $destConn -Database $DestinationDatabase `
                    -Table $tableName -InputObject $sourceData -BulkCopyTimeout 0
                
                # Re-enable constraints
                Invoke-DbaQuery -SqlInstance $destConn -Database $DestinationDatabase `
                    -Query "ALTER TABLE $tableName CHECK CONSTRAINT ALL"
                
                Write-Host "  Copied $($sourceData.Rows.Count) rows" -ForegroundColor Gray
                
            } catch {
                Write-Warning "Failed to copy data for $tableName : $_"
            }
        }
        
        Write-Host "Data copy completed!" -ForegroundColor Green
        
    } catch {
        Write-Error "Data copy failed: $_"
        throw
    }
}

# Function for selective copying
function Copy-Selective {
    param(
        [string]$SourceServer,
        [string]$SourceDatabase,
        [string]$DestinationServer,
        [string]$DestinationDatabase,
        [PSCredential]$SourceCredential,
        [PSCredential]$DestinationCredential,
        [CopyConfiguration]$Config
    )
    
    try {
        Write-Host "`nPerforming Selective Copy..." -ForegroundColor Green
        
        # First copy schema if needed
        if ($Config.CopyTables -or $Config.CopyViews -or $Config.CopyStoredProcedures -or 
            $Config.CopyFunctions) {
            Copy-SchemaOnly -SourceServer $SourceServer -SourceDatabase $SourceDatabase `
                -DestinationServer $DestinationServer -DestinationDatabase $DestinationDatabase `
                -SourceCredential $SourceCredential -DestinationCredential $DestinationCredential `
                -Config $Config
        }
        
        # Then copy data if needed
        if ($Config.CopyData) {
            Copy-DataOnly -SourceServer $SourceServer -SourceDatabase $SourceDatabase `
                -DestinationServer $DestinationServer -DestinationDatabase $DestinationDatabase `
                -SourceCredential $SourceCredential -DestinationCredential $DestinationCredential `
                -Config $Config
        }
        
        Write-Host "Selective copy completed!" -ForegroundColor Green
        
    } catch {
        Write-Error "Selective copy failed: $_"
        throw
    }
}

# Main execution
try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "    SQL Database Copy Tool" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    Write-Host "Source: $SourceServer.$SourceDatabase" -ForegroundColor Gray
    Write-Host "Destination: $DestinationServer.$DestinationDatabase" -ForegroundColor Gray
    Write-Host "Mode: $CopyMode`n" -ForegroundColor Gray
    
    # Execute based on copy mode
    switch ($CopyMode) {
        "Full" {
            Copy-FullBackupRestore -SourceServer $SourceServer -SourceDatabase $SourceDatabase `
                -DestinationServer $DestinationServer -DestinationDatabase $DestinationDatabase `
                -BackupPath $BackupPath -SourceCredential $SourceCredential `
                -DestinationCredential $DestinationCredential -UseCompression $UseCompression `
                -OverwriteDestination $OverwriteDestination
        }
        
        "SchemaOnly" {
            $config = [CopyConfiguration]::new()
            $config.CopyData = $false
            Copy-SchemaOnly -SourceServer $SourceServer -SourceDatabase $SourceDatabase `
                -DestinationServer $DestinationServer -DestinationDatabase $DestinationDatabase `
                -SourceCredential $SourceCredential -DestinationCredential $DestinationCredential `
                -Config $config
        }
        
        "DataOnly" {
            $config = [CopyConfiguration]::new()
            Copy-DataOnly -SourceServer $SourceServer -SourceDatabase $SourceDatabase `
                -DestinationServer $DestinationServer -DestinationDatabase $DestinationDatabase `
                -SourceCredential $SourceCredential -DestinationCredential $DestinationCredential `
                -Config $config
        }
        
        "Selective" {
            # Use predefined selective configuration
            $config = [CopyConfiguration]::new()
            $config.CopyUsers = $false
            $config.CopyLogins = $false
            Copy-Selective -SourceServer $SourceServer -SourceDatabase $SourceDatabase `
                -DestinationServer $DestinationServer -DestinationDatabase $DestinationDatabase `
                -SourceCredential $SourceCredential -DestinationCredential $DestinationCredential `
                -Config $config
        }
        
        "Custom" {
            # Get custom configuration from user
            $config = Get-CustomConfiguration
            Copy-Selective -SourceServer $SourceServer -SourceDatabase $SourceDatabase `
                -DestinationServer $DestinationServer -DestinationDatabase $DestinationDatabase `
                -SourceCredential $SourceCredential -DestinationCredential $DestinationCredential `
                -Config $config
        }
    }
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "    Database Copy Completed Successfully!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
} catch {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "    Database Copy Failed!" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Red
    Write-Error $_
    exit 1
}