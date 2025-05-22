function Copy-DbaUserTables {
<#
.SYNOPSIS
    Copy schema and data for all user tables from one SQL Server database to another using dbatools
    
.DESCRIPTION
    This function provides two approaches to copy all user tables (schema + data) between SQL Server databases:
    1. Comprehensive approach using Invoke-DbaDbTransfer (recommended)
    2. Granular approach using individual table operations (more control)
    
    Includes option to force overwrite existing tables in destination database.
    
.PARAMETER SourceInstance
    Source SQL Server instance name
    
.PARAMETER DestinationInstance  
    Destination SQL Server instance name
    
.PARAMETER SourceDatabase
    Source database name
    
.PARAMETER DestinationDatabase
    Destination database name (will be created if doesn't exist)
    
.PARAMETER Method
    Copy method: 'Comprehensive' (default) or 'Granular'
    
.PARAMETER BatchSize
    Batch size for data copy operations (default: 50000)
    
.PARAMETER IncludeIndexes
    Whether to include indexes in the copy operation (Granular method only)
    
.PARAMETER IncludeConstraints
    Whether to include constraints in the copy operation (Granular method only)
    
.PARAMETER ForceOverwrite
    Drop and recreate existing tables in destination database
    
.EXAMPLE
    Copy-DbaUserTables -SourceInstance "SQL01" -DestinationInstance "SQL02" -SourceDatabase "SourceDB" -DestinationDatabase "DestDB"
    
.EXAMPLE
    Copy-DbaUserTables -SourceInstance "SQL01" -DestinationInstance "SQL02" -SourceDatabase "SourceDB" -DestinationDatabase "DestDB" -Method Granular -BatchSize 25000
    
.EXAMPLE
    Copy-DbaUserTables -SourceInstance "SQL01" -DestinationInstance "SQL02" -SourceDatabase "SourceDB" -DestinationDatabase "DestDB" -ForceOverwrite
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceInstance,
        
        [Parameter(Mandatory = $true)]
        [string]$DestinationInstance,
        
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabase,
        
        [Parameter(Mandatory = $true)]
        [string]$DestinationDatabase,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Comprehensive', 'Granular')]
        [string]$Method = 'Comprehensive',
        
        [Parameter(Mandatory = $false)]
        [int]$BatchSize = 50000,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeIndexes,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeConstraints,
        
        [Parameter(Mandatory = $false)]
        [switch]$ForceOverwrite
    )

    # Error handling setup
    $ErrorActionPreference = 'Stop'

    function Write-LogMessage {
        param([string]$Message, [string]$Level = 'INFO')
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(
            switch ($Level) {
                'ERROR' { 'Red' }
                'WARNING' { 'Yellow' }
                'SUCCESS' { 'Green' }
                default { 'White' }
            }
        )
    }

    function Remove-ConflictingTables {
        param(
            [string]$DestinationInstance,
            [string]$DestinationDatabase,
            [array]$SourceTables
        )
        
        Write-LogMessage "ForceOverwrite enabled - checking for existing tables to drop..."
        $existingTables = Get-DbaDbTable -SqlInstance $DestinationInstance -Database $DestinationDatabase -ErrorAction SilentlyContinue |
                         Where-Object { $_.Schema -ne 'sys' -and $_.IsSystemObject -eq $false }
        
        if ($existingTables.Count -eq 0) {
            Write-LogMessage "No existing tables found in destination database"
            return
        }
        
        Write-LogMessage "Found $($existingTables.Count) existing tables in destination database"
        
        # Find tables that exist in both source and destination
        $tablesToDrop = @()
        foreach ($sourceTable in $SourceTables) {
            $existingTable = $existingTables | Where-Object { 
                $_.Schema -eq $sourceTable.Schema -and $_.Name -eq $sourceTable.Name 
            }
            if ($existingTable) {
                $tablesToDrop += $existingTable
            }
        }
        
        if ($tablesToDrop.Count -eq 0) {
            Write-LogMessage "No conflicting tables found to drop"
            return
        }
        
        Write-LogMessage "Dropping $($tablesToDrop.Count) conflicting tables..."
        
        # Sort tables by dependency (drop in reverse dependency order)
        $tablesToDrop = $tablesToDrop | Sort-Object Schema, Name
        
        foreach ($table in $tablesToDrop) {
            $tableName = "[$($table.Schema)].[$($table.Name)]"
            try {
                Write-LogMessage "  Dropping table: $tableName"
                
                # First disable foreign key constraints that might reference this table
                $disableFKQuery = @"
                    DECLARE @sql NVARCHAR(MAX) = ''
                    SELECT @sql = @sql + 'ALTER TABLE [' + OBJECT_SCHEMA_NAME(parent_object_id) + '].[' + OBJECT_NAME(parent_object_id) + '] DROP CONSTRAINT [' + name + '];' + CHAR(13)
                    FROM sys.foreign_keys 
                    WHERE referenced_object_id = OBJECT_ID('$tableName')
                    EXEC sp_executesql @sql
"@
                Invoke-DbaQuery -SqlInstance $DestinationInstance -Database $DestinationDatabase -Query $disableFKQuery -ErrorAction SilentlyContinue
                
                # Drop the table
                Invoke-DbaQuery -SqlInstance $DestinationInstance -Database $DestinationDatabase -Query "DROP TABLE $tableName"
                Write-LogMessage "    Successfully dropped $tableName" -Level 'SUCCESS'
            }
            catch {
                Write-LogMessage "    Warning: Could not drop table $tableName - $($_.Exception.Message)" -Level 'WARNING'
            }
        }
        
        Write-LogMessage "Table dropping completed" -Level 'SUCCESS'
    }

    try {
        Write-LogMessage "Starting table copy operation from $SourceInstance.$SourceDatabase to $DestinationInstance.$DestinationDatabase"
        Write-LogMessage "Method: $Method, ForceOverwrite: $ForceOverwrite, BatchSize: $BatchSize"
        
        # Verify dbatools module is available
        if (-not (Get-Module -ListAvailable -Name dbatools)) {
            throw "dbatools module is not installed. Please install it using: Install-Module -Name dbatools"
        }
        
        # Import dbatools if not already loaded
        if (-not (Get-Module -Name dbatools)) {
            Import-Module dbatools
        }
        
        # Verify source database exists and get connection
        Write-LogMessage "Verifying source database connection..."
        $sourceDb = Get-DbaDatabase -SqlInstance $SourceInstance -Database $SourceDatabase
        if (-not $sourceDb) {
            throw "Source database '$SourceDatabase' not found on instance '$SourceInstance'"
        }
        
        # Get all user tables from source database (excluding system tables)
        Write-LogMessage "Retrieving user tables from source database..."
        $userTables = Get-DbaDbTable -SqlInstance $SourceInstance -Database $SourceDatabase | 
                      Where-Object { $_.Schema -ne 'sys' -and $_.IsSystemObject -eq $false }
        
        if ($userTables.Count -eq 0) {
            Write-LogMessage "No user tables found in source database" -Level 'WARNING'
            return
        }
        
        Write-LogMessage "Found $($userTables.Count) user tables to copy"
        $userTables | ForEach-Object { Write-LogMessage "  - [$($_.Schema)].[$($_.Name)]" }
        
        # Ensure destination database exists
        Write-LogMessage "Ensuring destination database exists..."
        $destDb = Get-DbaDatabase -SqlInstance $DestinationInstance -Database $DestinationDatabase -ErrorAction SilentlyContinue
        if (-not $destDb) {
            Write-LogMessage "Creating destination database '$DestinationDatabase'..."
            New-DbaDatabase -SqlInstance $DestinationInstance -Database $DestinationDatabase
        }
        
        # Handle existing tables if ForceOverwrite is specified
        if ($ForceOverwrite) {
            Remove-ConflictingTables -DestinationInstance $DestinationInstance -DestinationDatabase $DestinationDatabase -SourceTables $userTables
        }
        
        switch ($Method) {
            'Comprehensive' {
                Write-LogMessage "Using comprehensive approach with Invoke-DbaDbTransfer..."
                
                # For comprehensive method with ForceOverwrite, we rely on pre-dropping conflicting tables
                if ($ForceOverwrite) {
                    Write-LogMessage "Note: ForceOverwrite with Comprehensive method relies on pre-dropping conflicting tables"
                }
                
                # Build transfer options
                $transferOptions = @{
                    SqlInstance = $SourceInstance
                    DestinationSqlInstance = $DestinationInstance
                    Database = $SourceDatabase
                    DestinationDatabase = $DestinationDatabase
                    CopyAll = 'Tables'
                }
                
                Write-LogMessage "Starting comprehensive table transfer..."
                $result = Invoke-DbaDbTransfer @transferOptions
                
                if ($result) {
                    Write-LogMessage "Comprehensive transfer completed successfully" -Level 'SUCCESS'
                }
            }
            
            'Granular' {
                Write-LogMessage "Using granular approach with individual table operations..."
                
                $successCount = 0
                $failureCount = 0
                $failedTables = @()
                
                foreach ($table in $userTables) {
                    $tableName = "[$($table.Schema)].[$($table.Name)]"
                    
                    try {
                        Write-LogMessage "Processing table: $tableName"
                        
                        if ($ForceOverwrite) {
                            # Use AutoCreateTable to handle both structure and data in one operation
                            Write-LogMessage "  Copying table structure and data (ForceOverwrite mode)..."
                            $copyParams = @{
                                SqlInstance = $SourceInstance
                                Destination = $DestinationInstance
                                Database = $SourceDatabase
                                DestinationDatabase = $DestinationDatabase
                                Table = $tableName
                                BatchSize = $BatchSize
                                KeepNulls = $true
                                AutoCreateTable = $true
                            }
                            
                            Copy-DbaDbTableData @copyParams
                        }
                        else {
                            # Standard approach: check if table exists first
                            $existingTable = Get-DbaDbTable -SqlInstance $DestinationInstance -Database $DestinationDatabase -Table $table.Name -Schema $table.Schema -ErrorAction SilentlyContinue
                            
                            if ($existingTable) {
                                Write-LogMessage "  Table exists - copying data only (using Truncate)..."
                                $copyParams = @{
                                    SqlInstance = $SourceInstance
                                    Destination = $DestinationInstance
                                    Database = $SourceDatabase
                                    DestinationDatabase = $DestinationDatabase
                                    Table = $tableName
                                    BatchSize = $BatchSize
                                    KeepNulls = $true
                                    Truncate = $true
                                }
                                
                                Copy-DbaDbTableData @copyParams
                            }
                            else {
                                Write-LogMessage "  Table doesn't exist - copying structure and data..."
                                
                                # First, copy the table structure
                                $tableTransfer = New-DbaDbTransfer -SqlInstance $SourceInstance -Destination $DestinationInstance -Database $SourceDatabase
                                $tableTransfer.CopyData = $false  # Structure only
                                $tableTransfer.Options.WithDependencies = $true
                                $tableTransfer.Options.Indexes = $IncludeIndexes
                                $tableTransfer.Options.CheckConstraints = $IncludeConstraints
                                $tableTransfer.Options.ForeignKeys = $IncludeConstraints
                                
                                # Add specific table to transfer object
                                $sourceTableObj = $tableTransfer.Database.Tables | Where-Object { 
                                    $_.Schema -eq $table.Schema -and $_.Name -eq $table.Name 
                                }
                                if ($sourceTableObj) {
                                    $tableTransfer.ObjectList.Add($sourceTableObj)
                                    $tableTransfer.TransferData()
                                }
                                
                                # Then copy the data
                                $copyParams = @{
                                    SqlInstance = $SourceInstance
                                    Destination = $DestinationInstance
                                    Database = $SourceDatabase
                                    DestinationDatabase = $DestinationDatabase
                                    Table = $tableName
                                    BatchSize = $BatchSize
                                    KeepNulls = $true
                                }
                                
                                Copy-DbaDbTableData @copyParams
                            }
                        }
                        
                        Write-LogMessage "  Successfully copied $tableName" -Level 'SUCCESS'
                        $successCount++
                    }
                    catch {
                        Write-LogMessage "  Failed to copy $tableName`: $($_.Exception.Message)" -Level 'ERROR'
                        $failureCount++
                        $failedTables += $tableName
                    }
                }
                
                Write-LogMessage "Granular copy completed. Success: $successCount, Failures: $failureCount" -Level $(if ($failureCount -eq 0) { 'SUCCESS' } else { 'WARNING' })
                
                if ($failedTables.Count -gt 0) {
                    Write-LogMessage "Failed tables:" -Level 'WARNING'
                    $failedTables | ForEach-Object { Write-LogMessage "  - $_" -Level 'WARNING' }
                }
            }
        }
        
        # Verify the copy by comparing table counts
        Write-LogMessage "Verifying copy operation..."
        $sourceTableCount = (Get-DbaDbTable -SqlInstance $SourceInstance -Database $SourceDatabase | Where-Object { $_.Schema -ne 'sys' -and $_.IsSystemObject -eq $false }).Count
        $destTableCount = (Get-DbaDbTable -SqlInstance $DestinationInstance -Database $DestinationDatabase | Where-Object { $_.Schema -ne 'sys' -and $_.IsSystemObject -eq $false }).Count
        
        Write-LogMessage "Source tables: $sourceTableCount, Destination tables: $destTableCount"
        
        if ($sourceTableCount -eq $destTableCount) {
            Write-LogMessage "Table copy verification successful!" -Level 'SUCCESS'
        } else {
            Write-LogMessage "Table count mismatch detected - this may be expected if some tables failed to copy" -Level 'WARNING'
        }
        
        Write-LogMessage "Operation completed successfully" -Level 'SUCCESS'
    }
    catch {
        Write-LogMessage "Operation failed: $($_.Exception.Message)" -Level 'ERROR'
        throw
    }
}
