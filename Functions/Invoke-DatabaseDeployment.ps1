function Invoke-DatabaseDeployment {
    <#
    .SYNOPSIS
    Deploys database changes from a zip file containing SQL scripts with backup and rollback capabilities.
    
    .DESCRIPTION
    This function extracts SQL scripts from a zip file, creates database backups, and executes the scripts
    in natural sort order. It provides rollback capabilities and comprehensive logging.
    
    .PARAMETER ZipFilePath
    Path to the zip file containing SQL scripts
    
    .PARAMETER ServerInstance
    SQL Server instance name
    
    .PARAMETER DatabaseName
    Target database name
    
    .PARAMETER BackupPath
    Directory path where database backups will be stored
    
    .PARAMETER TempPath
    Temporary directory for extracting scripts (defaults to system temp)
    
    .PARAMETER ExecutionTimeout
    SQL command timeout in seconds (default: 300)
    
    .PARAMETER WhatIf
    Shows what would be executed without actually running the scripts
    
    .PARAMETER CreateRollbackScript
    Creates a rollback script for potential future use
    
    .EXAMPLE
    Invoke-DatabaseDeployment -ZipFilePath "C:\Deploy\Release_1.2.3.zip" -ServerInstance "SQLSERVER01" -DatabaseName "MyApp" -BackupPath "C:\Backups"
    
    .EXAMPLE
    Invoke-DatabaseDeployment -ZipFilePath ".\scripts.zip" -ServerInstance "localhost" -DatabaseName "TestDB" -BackupPath ".\backups" -WhatIf
    #>
    
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ZipFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        
        [Parameter()]
        [string]$TempPath = [System.IO.Path]::GetTempPath(),
        
        [Parameter()]
        [int]$ExecutionTimeout = 300,
        
        [Parameter()]
        [switch]$CreateRollbackScript
    )
    
    begin {
        # Import required modules
        if (-not (Get-Module -Name SqlServer -ListAvailable)) {
            throw "SqlServer PowerShell module is required. Install with: Install-Module -Name SqlServer"
        }
        Import-Module SqlServer -Force
        
        # Initialize variables
        $DeploymentId = [System.Guid]::NewGuid().ToString("N")[0..7] -join ""
        $LogFile = Join-Path $BackupPath "deployment_log_$($DeploymentId)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $ExtractPath = Join-Path $TempPath "SQLDeploy_$DeploymentId"
        $BackupFileName = "$($DatabaseName)_PreDeploy_$(Get-Date -Format 'yyyyMMdd_HHmmss').bak"
        $BackupFilePath = Join-Path $BackupPath $BackupFileName
        
        # Ensure backup directory exists
        if (-not (Test-Path $BackupPath)) {
            New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
        }
        
        # Initialize log
        function Write-DeploymentLog {
            param([string]$Message, [string]$Level = "INFO")
            $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
            Write-Host $LogEntry
            Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8
        }
        
        Write-DeploymentLog "Starting database deployment - ID: $DeploymentId"
        Write-DeploymentLog "Target: $ServerInstance\$DatabaseName"
        Write-DeploymentLog "Source: $ZipFilePath"
    }
    
    process {
        try {
            # Step 1: Extract zip file
            Write-DeploymentLog "Extracting scripts from zip file..."
            if (Test-Path $ExtractPath) {
                Remove-Item $ExtractPath -Recurse -Force
            }
            
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipFilePath, $ExtractPath)
            
            # Step 2: Find and sort SQL files
            Write-DeploymentLog "Discovering SQL scripts..."
            $SqlFiles = Get-ChildItem -Path $ExtractPath -Filter "*.sql" -Recurse | 
                Sort-Object Name | 
                ForEach-Object { 
                    [PSCustomObject]@{
                        Name = $_.Name
                        FullName = $_.FullName
                        RelativePath = $_.FullName.Replace($ExtractPath, "").TrimStart('\', '/')
                    }
                }
            
            if ($SqlFiles.Count -eq 0) {
                throw "No SQL files found in the zip archive"
            }
            
            Write-DeploymentLog "Found $($SqlFiles.Count) SQL script(s):"
            foreach ($file in $SqlFiles) {
                Write-DeploymentLog "  - $($file.RelativePath)"
            }
            
            # Step 3: Verify database connectivity
            Write-DeploymentLog "Testing database connectivity..."
            try {
                $TestQuery = "SELECT DB_NAME() as DatabaseName, @@VERSION as Version"
                $TestResult = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $DatabaseName -Query $TestQuery -QueryTimeout 30
                Write-DeploymentLog "Connected successfully to $($TestResult.DatabaseName)"
            }
            catch {
                throw "Failed to connect to database: $($_.Exception.Message)"
            }
            
            # Step 4: Create database backup
            if (-not $WhatIfPreference) {
                Write-DeploymentLog "Creating database backup..."
                try {
                    $BackupQuery = @"
BACKUP DATABASE [$DatabaseName] 
TO DISK = N'$BackupFilePath'
WITH FORMAT, COMPRESSION, CHECKSUM, STATS = 10
"@
                    Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "master" -Query $BackupQuery -QueryTimeout 600
                    Write-DeploymentLog "Backup completed: $BackupFilePath"
                    
                    # Verify backup
                    $VerifyQuery = "RESTORE VERIFYONLY FROM DISK = N'$BackupFilePath'"
                    Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "master" -Query $VerifyQuery -QueryTimeout 60
                    Write-DeploymentLog "Backup verification successful"
                }
                catch {
                    throw "Backup creation failed: $($_.Exception.Message)"
                }
            }
            else {
                Write-DeploymentLog "[WHATIF] Would create backup: $BackupFilePath"
            }
            
            # Step 5: Execute scripts
            $ExecutedScripts = @()
            $FailedScript = $null
            
            foreach ($sqlFile in $SqlFiles) {
                Write-DeploymentLog "Processing script: $($sqlFile.Name)"
                
                try {
                    $SqlContent = Get-Content -Path $sqlFile.FullName -Raw -Encoding UTF8
                    
                    if ($WhatIfPreference) {
                        Write-DeploymentLog "[WHATIF] Would execute: $($sqlFile.Name)"
                        $ExecutedScripts += $sqlFile
                    }
                    else {
                        # Execute the script
                        Write-DeploymentLog "Executing: $($sqlFile.Name)"
                        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $DatabaseName -Query $SqlContent -QueryTimeout $ExecutionTimeout
                        Write-DeploymentLog "Successfully executed: $($sqlFile.Name)"
                        $ExecutedScripts += $sqlFile
                    }
                }
                catch {
                    $FailedScript = $sqlFile
                    $ErrorMessage = $_.Exception.Message
                    Write-DeploymentLog "FAILED to execute $($sqlFile.Name): $ErrorMessage" -Level "ERROR"
                    
                    # Offer rollback
                    Write-Host "`nDeployment failed on script: $($sqlFile.Name)" -ForegroundColor Red
                    Write-Host "Error: $ErrorMessage" -ForegroundColor Red
                    Write-Host "`nExecuted scripts before failure:" -ForegroundColor Yellow
                    foreach ($executed in $ExecutedScripts) {
                        Write-Host "  ✓ $($executed.Name)" -ForegroundColor Green
                    }
                    
                    if (-not $WhatIfPreference) {
                        $RollbackChoice = Read-Host "`nDo you want to rollback to the backup? (Y/N)"
                        if ($RollbackChoice -eq "Y" -or $RollbackChoice -eq "y") {
                            Write-DeploymentLog "Initiating rollback..." -Level "WARN"
                            Restore-DatabaseFromBackup -ServerInstance $ServerInstance -DatabaseName $DatabaseName -BackupFilePath $BackupFilePath
                            Write-DeploymentLog "Rollback completed" -Level "WARN"
                            throw "Deployment failed and was rolled back. Check log for details."
                        }
                        else {
                            Write-DeploymentLog "User chose not to rollback" -Level "WARN"
                            throw "Deployment failed. Database left in partial state."
                        }
                    }
                    else {
                        throw "Deployment validation failed on script: $($sqlFile.Name)"
                    }
                }
            }
            
            # Step 6: Create rollback script if requested
            if ($CreateRollbackScript -and -not $WhatIfPreference) {
                $RollbackScriptPath = Join-Path $BackupPath "rollback_script_$($DeploymentId).sql"
                $RollbackContent = @"
-- Rollback script for deployment $DeploymentId
-- Created: $(Get-Date)
-- Target: $ServerInstance\$DatabaseName
-- Backup: $BackupFilePath

USE [master]
GO

-- Restore database from backup
RESTORE DATABASE [$DatabaseName] 
FROM DISK = N'$BackupFilePath'
WITH REPLACE, STATS = 10
GO

PRINT 'Database rollback completed successfully'
GO
"@
                Set-Content -Path $RollbackScriptPath -Value $RollbackContent -Encoding UTF8
                Write-DeploymentLog "Rollback script created: $RollbackScriptPath"
            }
            
            Write-DeploymentLog "Deployment completed successfully!"
            Write-DeploymentLog "Executed $($ExecutedScripts.Count) script(s)"
            
            # Return deployment summary
            return [PSCustomObject]@{
                DeploymentId = $DeploymentId
                Status = "Success"
                ExecutedScripts = $ExecutedScripts.Count
                BackupPath = $BackupFilePath
                LogFile = $LogFile
                StartTime = $ExecutedScripts[0]
                EndTime = Get-Date
            }
        }
        catch {
            Write-DeploymentLog "Deployment failed: $($_.Exception.Message)" -Level "ERROR"
            throw
        }
        finally {
            # Cleanup temp directory
            if (Test-Path $ExtractPath) {
                Remove-Item $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-DeploymentLog "Cleaned up temporary files"
            }
        }
    }
}

function Restore-DatabaseFromBackup {
    <#
    .SYNOPSIS
    Restores a database from a backup file
    
    .PARAMETER ServerInstance
    SQL Server instance name
    
    .PARAMETER DatabaseName
    Database name to restore
    
    .PARAMETER BackupFilePath
    Path to the backup file
    #>
    param(
        [string]$ServerInstance,
        [string]$DatabaseName,
        [string]$BackupFilePath
    )
    
    try {
        Write-Host "Restoring database from backup..." -ForegroundColor Yellow
        
        $RestoreQuery = @"
USE [master]
GO

-- Set database to single user mode to drop connections
ALTER DATABASE [$DatabaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
GO

-- Restore database
RESTORE DATABASE [$DatabaseName] 
FROM DISK = N'$BackupFilePath'
WITH REPLACE, STATS = 10
GO

-- Set back to multi user
ALTER DATABASE [$DatabaseName] SET MULTI_USER
GO
"@
        
        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "master" -Query $RestoreQuery -QueryTimeout 600
        Write-Host "Database restored successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to restore database: $($_.Exception.Message)"
        throw
    }
}

# Functions are automatically exported by the main module 