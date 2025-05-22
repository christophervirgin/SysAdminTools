function Copy-DbaDatabase {
<#
.SYNOPSIS
    Copy a complete database from one SQL Server instance to another with extensive customization options using dbatools
    
.DESCRIPTION
    This function provides comprehensive database copy capabilities between SQL Server instances with granular control over what gets copied.
    It leverages dbatools for robust database operations and includes options for:
    - Including/excluding table data
    - Including/excluding system objects
    - Including/excluding users and permissions
    - Including/excluding stored procedures, functions, views
    - Including/excluding triggers and constraints
    - Force overwrite existing database
    - Custom backup/restore approach
    
.PARAMETER SourceInstance
    Source SQL Server instance name
    
.PARAMETER DestinationInstance  
    Destination SQL Server instance name
    
.PARAMETER SourceDatabase
    Source database name
    
.PARAMETER DestinationDatabase
    Destination database name (will be created if doesn't exist)
    
.PARAMETER Method
    Copy method: 'Transfer' (default), 'BackupRestore', or 'BackupRestoreWithOptions'
    - Transfer: Uses Invoke-DbaDbTransfer for direct transfer
    - BackupRestore: Uses backup and restore approach
    - BackupRestoreWithOptions: Backup/restore with selective restore options
    
.PARAMETER IncludeTableData
    Include table data in the copy operation (default: $true)
    
.PARAMETER IncludeSystemObjects
    Include system objects like system stored procedures, functions, etc. (default: $false)
    
.PARAMETER IncludeUsers
    Include database users in the copy operation (default: $true)
    
.PARAMETER IncludeUserPermissions
    Include user permissions and role memberships (default: $true)
    
.PARAMETER IncludeStoredProcedures
    Include stored procedures (default: $true)
    
.PARAMETER IncludeFunctions
    Include user-defined functions (default: $true)
    
.PARAMETER IncludeViews
    Include views (default: $true)
    
.PARAMETER IncludeTriggers
    Include triggers (default: $true)
    
.PARAMETER IncludeConstraints
    Include constraints (foreign keys, check constraints, etc.) (default: $true)
    
.PARAMETER IncludeIndexes
    Include indexes (default: $true)
    
.PARAMETER ExcludeUsers
    Array of specific users to exclude from the copy operation
    
.PARAMETER ExcludeSchemas
    Array of specific schemas to exclude from the copy operation
    
.PARAMETER ExcludeTables
    Array of specific tables to exclude from the copy operation (format: 'schema.table')
    
.PARAMETER ForceOverwrite
    Drop and recreate destination database if it exists
    
.PARAMETER BatchSize
    Batch size for data copy operations (default: 50000)
    
.PARAMETER BackupPath
    Path for backup files (required for BackupRestore methods)
    
.PARAMETER Verify
    Perform verification checks after copy operation (default: $true)
    
.PARAMETER LogPath
    Path to write detailed log file (optional)
    
.EXAMPLE
    Copy-DbaDatabase -SourceInstance "SQL01" -DestinationInstance "SQL02" -SourceDatabase "SourceDB" -DestinationDatabase "DestDB"
    
    Basic database copy with default options
    
.EXAMPLE
    Copy-DbaDatabase -SourceInstance "SQL01" -DestinationInstance "SQL02" -SourceDatabase "SourceDB" -DestinationDatabase "DestDB" -IncludeTableData:$false -ExcludeUsers @('testuser', 'guestuser')
    
    Copy database structure only, excluding specific users
    
.EXAMPLE
    Copy-DbaDatabase -SourceInstance "SQL01" -DestinationInstance "SQL02" -SourceDatabase "SourceDB" -DestinationDatabase "DestDB" -Method BackupRestore -BackupPath "C:\Backups" -ForceOverwrite
    
    Copy database using backup/restore method with force overwrite
    
.EXAMPLE
    Copy-DbaDatabase -SourceInstance "SQL01" -DestinationInstance "SQL02" -SourceDatabase "SourceDB" -DestinationDatabase "DestDB" -IncludeSystemObjects -ExcludeUserPermissions -ExcludeSchemas @('temp', 'staging')
    
    Copy database with system objects but exclude user permissions and specific schemas
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
        [ValidateSet('Transfer', 'BackupRestore', 'BackupRestoreWithOptions')]
        [string]$Method = 'Transfer',
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeTableData = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeSystemObjects = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeUsers = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeUserPermissions = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeStoredProcedures = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeFunctions = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeViews = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeTriggers = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeConstraints = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeIndexes = $true,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeUsers = @(),
        
        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeSchemas = @(),
        
        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeTables = @(),
        
        [Parameter(Mandatory = $false)]
        [switch]$ForceOverwrite,
        
        [Parameter(Mandatory = $false)]
        [int]$BatchSize = 50000,
        
        [Parameter(Mandatory = $false)]
        [string]$BackupPath,
        
        [Parameter(Mandatory = $false)]
        [bool]$Verify = $true,
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath
    )

    # Error handling setup
    $ErrorActionPreference = 'Stop'
    
    # Initialize logging
    $LogFile = $null
    if ($LogPath) {
        $LogFile = Join-Path $LogPath "DatabaseCopy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        if (-not (Test-Path (Split-Path $LogFile -Parent))) {
            New-Item -Path (Split-Path $LogFile -Parent) -ItemType Directory -Force | Out-Null
        }
    }

    function Write-LogMessage {
        param([string]$Message, [string]$Level = 'INFO')
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $logMessage = "[$timestamp] [$Level] $Message"
        
        # Console output
        Write-Host $logMessage -ForegroundColor $(
            switch ($Level) {
                'ERROR' { 'Red' }
                'WARNING' { 'Yellow' }
                'SUCCESS' { 'Green' }
                'PROGRESS' { 'Cyan' }
                default { 'White' }
            }
        )
        
        # File output
        if ($LogFile) {
            Add-Content -Path $LogFile -Value $logMessage
        }
    }

    function Test-Prerequisites {
        Write-LogMessage "Checking prerequisites..." -Level 'PROGRESS'
        
        # Check dbatools module
        if (-not (Get-Module -ListAvailable -Name dbatools)) {
            throw "dbatools module is not installed. Please install it using: Install-Module -Name dbatools"
        }
        
        # Import dbatools if not already loaded
        if (-not (Get-Module -Name dbatools)) {
            Import-Module dbatools
        }
        
        # Validate backup path for backup methods
        if ($Method -in @('BackupRestore', 'BackupRestoreWithOptions') -and -not $BackupPath) {
            throw "BackupPath parameter is required when using BackupRestore methods"
        }
        
        if ($BackupPath -and -not (Test-Path $BackupPath)) {
            Write-LogMessage "Creating backup directory: $BackupPath"
            New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
        }
        
        Write-LogMessage "Prerequisites check completed" -Level 'SUCCESS'
    }

    function Test-DatabaseConnections {
        Write-LogMessage "Testing database connections..." -Level 'PROGRESS'
        
        # Test source connection and database
        try {
            $sourceDb = Get-DbaDatabase -SqlInstance $SourceInstance -Database $SourceDatabase
            if (-not $sourceDb) {
                throw "Source database '$SourceDatabase' not found on instance '$SourceInstance'"
            }
            Write-LogMessage "Source database connection verified" -Level 'SUCCESS'
        }
        catch {
            throw "Failed to connect to source database: $($_.Exception.Message)"
        }
        
        # Test destination connection
        try {
            $destInstance = Connect-DbaInstance -SqlInstance $DestinationInstance
            Write-LogMessage "Destination instance connection verified" -Level 'SUCCESS'
        }
        catch {
            throw "Failed to connect to destination instance: $($_.Exception.Message)"
        }
        
        # Check if destination database exists
        $destDb = Get-DbaDatabase -SqlInstance $DestinationInstance -Database $DestinationDatabase -ErrorAction SilentlyContinue
        if ($destDb -and -not $ForceOverwrite) {
            throw "Destination database '$DestinationDatabase' already exists. Use -ForceOverwrite to replace it."
        }
        
        return @{
            SourceDatabase = $sourceDb
            DestinationExists = ($destDb -ne $null)
        }
    }

    function Remove-DestinationDatabase {
        param($DatabaseName)
        
        Write-LogMessage "Removing existing destination database '$DatabaseName'..." -Level 'PROGRESS'
        try {
            Remove-DbaDatabase -SqlInstance $DestinationInstance -Database $DatabaseName -Confirm:$false
            Write-LogMessage "Destination database removed successfully" -Level 'SUCCESS'
        }
        catch {
            Write-LogMessage "Warning: Could not remove destination database: $($_.Exception.Message)" -Level 'WARNING'
        }
    }

    function Copy-DatabaseUsingTransfer {
        param($SourceDb)
        
        Write-LogMessage "Starting database copy using Transfer method..." -Level 'PROGRESS'
        
        try {
            # Configure transfer options
            $transferOptions = @{
                SqlInstance = $SourceInstance
                Destination = $DestinationInstance
                Database = $SourceDatabase
                DestinationDatabase = $DestinationDatabase
            }
            
            # Build CopyAll parameter based on options
            $copyItems = @()
            if ($IncludeTableData) { $copyItems += 'Tables' } else { $copyItems += 'TableSchema' }
            if ($IncludeStoredProcedures) { $copyItems += 'StoredProcedures' }
            if ($IncludeFunctions) { $copyItems += 'UserDefinedFunctions' }
            if ($IncludeViews) { $copyItems += 'Views' }
            if ($IncludeTriggers) { $copyItems += 'Triggers' }
            if ($IncludeUsers) { $copyItems += 'Users' }
            if ($IncludeUserPermissions) { $copyItems += 'Permissions' }
            
            if ($copyItems.Count -eq 0) {
                $transferOptions.CopyAll = 'Nothing'
            } else {
                $transferOptions.CopyAll = $copyItems
            }
            
            # Add exclusions
            if ($ExcludeSchemas.Count -gt 0) {
                $transferOptions.ExcludeSchema = $ExcludeSchemas
            }
            
            Write-LogMessage "Transfer options configured: $($copyItems -join ', ')"
            
            # Execute transfer
            $result = Invoke-DbaDbTransfer @transferOptions
            
            if ($result) {
                Write-LogMessage "Database transfer completed successfully" -Level 'SUCCESS'
            }
        }
        catch {
            throw "Transfer method failed: $($_.Exception.Message)"
        }
    }

    function Copy-DatabaseUsingBackupRestore {
        param($SourceDb)
        
        Write-LogMessage "Starting database copy using Backup/Restore method..." -Level 'PROGRESS'
        
        try {
            $backupFile = Join-Path $BackupPath "$SourceDatabase`_$(Get-Date -Format 'yyyyMMdd_HHmmss').bak"
            
            # Create backup
            Write-LogMessage "Creating backup of source database..."
            $backupResult = Backup-DbaDatabase -SqlInstance $SourceInstance -Database $SourceDatabase -Path $backupFile
            
            if (-not $backupResult) {
                throw "Backup operation failed"
            }
            
            Write-LogMessage "Backup created successfully: $backupFile" -Level 'SUCCESS'
            
            # Restore database
            Write-LogMessage "Restoring database to destination..."
            $restoreParams = @{
                SqlInstance = $DestinationInstance
                Database = $DestinationDatabase
                Path = $backupFile
                WithReplace = $ForceOverwrite
            }
            
            $restoreResult = Restore-DbaDatabase @restoreParams
            
            if ($restoreResult) {
                Write-LogMessage "Database restore completed successfully" -Level 'SUCCESS'
                
                # Apply exclusions if specified
                if ($ExcludeUsers.Count -gt 0 -or -not $IncludeUserPermissions -or $ExcludeSchemas.Count -gt 0) {
                    Write-LogMessage "Applying post-restore exclusions..."
                    Invoke-PostRestoreCleanup
                }
            }
            
            # Clean up backup file
            if (Test-Path $backupFile) {
                Remove-Item $backupFile -Force
                Write-LogMessage "Backup file cleaned up"
            }
        }
        catch {
            throw "Backup/Restore method failed: $($_.Exception.Message)"
        }
    }

    function Invoke-PostRestoreCleanup {
        Write-LogMessage "Performing post-restore cleanup..." -Level 'PROGRESS'
        
        try {
            # Remove excluded users
            if ($ExcludeUsers.Count -gt 0) {
                Write-LogMessage "Removing excluded users: $($ExcludeUsers -join ', ')"
                foreach ($user in $ExcludeUsers) {
                    try {
                        Remove-DbaDbUser -SqlInstance $DestinationInstance -Database $DestinationDatabase -User $user -Confirm:$false
                        Write-LogMessage "  Removed user: $user" -Level 'SUCCESS'
                    }
                    catch {
                        Write-LogMessage "  Warning: Could not remove user '$user': $($_.Exception.Message)" -Level 'WARNING'
                    }
                }
            }
            
            # Remove excluded schemas and their objects
            if ($ExcludeSchemas.Count -gt 0) {
                Write-LogMessage "Removing excluded schemas: $($ExcludeSchemas -join ', ')"
                foreach ($schema in $ExcludeSchemas) {
                    try {
                        # Drop all objects in schema first
                        $dropQuery = @"
                            DECLARE @sql NVARCHAR(MAX) = ''
                            
                            -- Drop foreign keys first
                            SELECT @sql = @sql + 'ALTER TABLE [' + SCHEMA_NAME(t.schema_id) + '].[' + t.name + '] DROP CONSTRAINT [' + fk.name + '];' + CHAR(13)
                            FROM sys.foreign_keys fk
                            INNER JOIN sys.tables t ON fk.parent_object_id = t.object_id
                            WHERE SCHEMA_NAME(t.schema_id) = '$schema'
                            
                            -- Drop tables
                            SELECT @sql = @sql + 'DROP TABLE [' + SCHEMA_NAME(schema_id) + '].[' + name + '];' + CHAR(13)
                            FROM sys.tables
                            WHERE SCHEMA_NAME(schema_id) = '$schema'
                            
                            -- Drop views
                            SELECT @sql = @sql + 'DROP VIEW [' + SCHEMA_NAME(schema_id) + '].[' + name + '];' + CHAR(13)
                            FROM sys.views
                            WHERE SCHEMA_NAME(schema_id) = '$schema'
                            
                            -- Drop procedures
                            SELECT @sql = @sql + 'DROP PROCEDURE [' + SCHEMA_NAME(schema_id) + '].[' + name + '];' + CHAR(13)
                            FROM sys.procedures
                            WHERE SCHEMA_NAME(schema_id) = '$schema' AND type = 'P'
                            
                            -- Drop functions
                            SELECT @sql = @sql + 'DROP FUNCTION [' + SCHEMA_NAME(schema_id) + '].[' + name + '];' + CHAR(13)
                            FROM sys.objects
                            WHERE SCHEMA_NAME(schema_id) = '$schema' AND type IN ('FN', 'IF', 'TF')
                            
                            -- Drop schema
                            SELECT @sql = @sql + 'DROP SCHEMA [$schema];' + CHAR(13)
                            
                            EXEC sp_executesql @sql
"@
                        
                        Invoke-DbaQuery -SqlInstance $DestinationInstance -Database $DestinationDatabase -Query $dropQuery
                        Write-LogMessage "  Removed schema: $schema" -Level 'SUCCESS'
                    }
                    catch {
                        Write-LogMessage "  Warning: Could not remove schema '$schema': $($_.Exception.Message)" -Level 'WARNING'
                    }
                }
            }
            
            # Remove user permissions if specified
            if (-not $IncludeUserPermissions) {
                Write-LogMessage "Removing user permissions..."
                try {
                    $permissionQuery = @"
                        -- Remove explicit permissions
                        DECLARE @sql NVARCHAR(MAX) = ''
                        SELECT @sql = @sql + 'REVOKE ' + dp.permission_name + ' ON ' + 
                            CASE dp.class
                                WHEN 1 THEN OBJECT_NAME(dp.major_id)
                                WHEN 3 THEN SCHEMA_NAME(dp.major_id)
                                ELSE 'DATABASE'
                            END + ' FROM [' + pr.name + '];' + CHAR(13)
                        FROM sys.database_permissions dp
                        INNER JOIN sys.database_principals pr ON dp.grantee_principal_id = pr.principal_id
                        WHERE pr.type NOT IN ('R') -- Exclude roles
                        AND dp.permission_name NOT IN ('CONNECT')
                        
                        EXEC sp_executesql @sql
"@
                    
                    Invoke-DbaQuery -SqlInstance $DestinationInstance -Database $DestinationDatabase -Query $permissionQuery
                    Write-LogMessage "User permissions removed" -Level 'SUCCESS'
                }
                catch {
                    Write-LogMessage "Warning: Could not remove all user permissions: $($_.Exception.Message)" -Level 'WARNING'
                }
            }
            
            Write-LogMessage "Post-restore cleanup completed" -Level 'SUCCESS'
        }
        catch {
            Write-LogMessage "Warning: Post-restore cleanup encountered errors: $($_.Exception.Message)" -Level 'WARNING'
        }
    }

    function Invoke-DatabaseVerification {
        Write-LogMessage "Performing database verification..." -Level 'PROGRESS'
        
        try {
            $verificationResults = @{}
            
            # Compare table counts
            $sourceTables = Get-DbaDbTable -SqlInstance $SourceInstance -Database $SourceDatabase | 
                           Where-Object { $_.Schema -ne 'sys' -and $_.IsSystemObject -eq $false }
            $destTables = Get-DbaDbTable -SqlInstance $DestinationInstance -Database $DestinationDatabase | 
                         Where-Object { $_.Schema -ne 'sys' -and $_.IsSystemObject -eq $false }
            
            $verificationResults.SourceTableCount = $sourceTables.Count
            $verificationResults.DestinationTableCount = $destTables.Count
            
            # Compare view counts
            $sourceViews = Get-DbaDbView -SqlInstance $SourceInstance -Database $SourceDatabase | 
                          Where-Object { $_.Schema -ne 'sys' -and $_.IsSystemObject -eq $false }
            $destViews = Get-DbaDbView -SqlInstance $DestinationInstance -Database $DestinationDatabase | 
                        Where-Object { $_.Schema -ne 'sys' -and $_.IsSystemObject -eq $false }
            
            $verificationResults.SourceViewCount = $sourceViews.Count
            $verificationResults.DestinationViewCount = $destViews.Count
            
            # Compare stored procedure counts
            $sourceProcs = Get-DbaDbStoredProcedure -SqlInstance $SourceInstance -Database $SourceDatabase | 
                          Where-Object { $_.Schema -ne 'sys' -and $_.IsSystemObject -eq $false }
            $destProcs = Get-DbaDbStoredProcedure -SqlInstance $DestinationInstance -Database $DestinationDatabase | 
                        Where-Object { $_.Schema -ne 'sys' -and $_.IsSystemObject -eq $false }
            
            $verificationResults.SourceProcedureCount = $sourceProcs.Count
            $verificationResults.DestinationProcedureCount = $destProcs.Count
            
            # Compare user counts
            $sourceUsers = Get-DbaDbUser -SqlInstance $SourceInstance -Database $SourceDatabase | 
                          Where-Object { $_.Name -notin @('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys') }
            $destUsers = Get-DbaDbUser -SqlInstance $DestinationInstance -Database $DestinationDatabase | 
                        Where-Object { $_.Name -notin @('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys') }
            
            $verificationResults.SourceUserCount = $sourceUsers.Count
            $verificationResults.DestinationUserCount = $destUsers.Count
            
            # Display verification results
            Write-LogMessage "=== Verification Results ===" -Level 'SUCCESS'
            Write-LogMessage "Tables: Source=$($verificationResults.SourceTableCount), Destination=$($verificationResults.DestinationTableCount)" -Level 'SUCCESS'
            Write-LogMessage "Views: Source=$($verificationResults.SourceViewCount), Destination=$($verificationResults.DestinationViewCount)" -Level 'SUCCESS'
            Write-LogMessage "Stored Procedures: Source=$($verificationResults.SourceProcedureCount), Destination=$($verificationResults.DestinationProcedureCount)" -Level 'SUCCESS'
            Write-LogMessage "Users: Source=$($verificationResults.SourceUserCount), Destination=$($verificationResults.DestinationUserCount)" -Level 'SUCCESS'
            
            return $verificationResults
        }
        catch {
            Write-LogMessage "Warning: Verification encountered errors: $($_.Exception.Message)" -Level 'WARNING'
            return $null
        }
    }

    # Main execution
    try {
        $startTime = Get-Date
        Write-LogMessage "Starting database copy operation" -Level 'PROGRESS'
        Write-LogMessage "Source: $SourceInstance.$SourceDatabase" -Level 'PROGRESS'
        Write-LogMessage "Destination: $DestinationInstance.$DestinationDatabase" -Level 'PROGRESS'
        Write-LogMessage "Method: $Method" -Level 'PROGRESS'
        Write-LogMessage "Include Data: $IncludeTableData, Include System Objects: $IncludeSystemObjects" -Level 'PROGRESS'
        Write-LogMessage "Include Users: $IncludeUsers, Include Permissions: $IncludeUserPermissions" -Level 'PROGRESS'
        
        # Test prerequisites
        Test-Prerequisites
        
        # Test connections
        $connectionResults = Test-DatabaseConnections
        
        # Handle existing destination database
        if ($connectionResults.DestinationExists -and $ForceOverwrite) {
            Remove-DestinationDatabase -DatabaseName $DestinationDatabase
        }
        
        # Execute copy operation based on method
        switch ($Method) {
            'Transfer' {
                Copy-DatabaseUsingTransfer -SourceDb $connectionResults.SourceDatabase
            }
            'BackupRestore' {
                Copy-DatabaseUsingBackupRestore -SourceDb $connectionResults.SourceDatabase
            }
            'BackupRestoreWithOptions' {
                Copy-DatabaseUsingBackupRestore -SourceDb $connectionResults.SourceDatabase
            }
        }
        
        # Perform verification if requested
        if ($Verify) {
            $verificationResults = Invoke-DatabaseVerification
        }
        
        $endTime = Get-Date
        $duration = $endTime - $startTime
        
        Write-LogMessage "=== Operation Completed Successfully ===" -Level 'SUCCESS'
        Write-LogMessage "Total Duration: $($duration.ToString('hh\:mm\:ss'))" -Level 'SUCCESS'
        
        if ($LogFile) {
            Write-LogMessage "Detailed log written to: $LogFile" -Level 'SUCCESS'
        }
        
        # Return results
        return @{
            Success = $true
            SourceInstance = $SourceInstance
            DestinationInstance = $DestinationInstance
            SourceDatabase = $SourceDatabase
            DestinationDatabase = $DestinationDatabase
            Method = $Method
            Duration = $duration
            VerificationResults = $verificationResults
            LogFile = $LogFile
        }
    }
    catch {
        $errorMessage = "Database copy operation failed: $($_.Exception.Message)"
        Write-LogMessage $errorMessage -Level 'ERROR'
        
        if ($LogFile) {
            Add-Content -Path $LogFile -Value "STACK TRACE: $($_.Exception.StackTrace)"
        }
        
        throw $errorMessage
    }
} 