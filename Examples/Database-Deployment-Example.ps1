# Database Deployment Examples
# This script demonstrates how to use the Invoke-DatabaseDeployment function

# Import the SysAdminTools module
Import-Module .\SysAdminTools.psd1 -Force

# Example 1: Basic deployment with backup and rollback capability
Write-Host "Example 1: Basic Deployment" -ForegroundColor Green
Write-Host "=" * 50

try {
    $DeployResult = Invoke-DatabaseDeployment `
        -ZipFilePath "C:\Deploy\DatabaseChanges_v1.2.3.zip" `
        -ServerInstance "SQLSERVER01" `
        -DatabaseName "MyApplication" `
        -BackupPath "C:\DatabaseBackups" `
        -CreateRollbackScript
    
    Write-Host "Deployment completed successfully!" -ForegroundColor Green
    Write-Host "Deployment ID: $($DeployResult.DeploymentId)"
    Write-Host "Scripts executed: $($DeployResult.ExecutedScripts)"
    Write-Host "Backup location: $($DeployResult.BackupPath)"
    Write-Host "Log file: $($DeployResult.LogFile)"
}
catch {
    Write-Host "Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Example 2: Test deployment with WhatIf (validation only)
Write-Host "`nExample 2: Validation Mode (WhatIf)" -ForegroundColor Green
Write-Host "=" * 50

try {
    Invoke-DatabaseDeployment `
        -ZipFilePath "C:\Deploy\DatabaseChanges_v1.2.4.zip" `
        -ServerInstance "SQLSERVER01" `
        -DatabaseName "MyApplication" `
        -BackupPath "C:\DatabaseBackups" `
        -WhatIf
    
    Write-Host "Validation completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "Validation failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Example 3: Deployment with custom timeout and temp path
Write-Host "`nExample 3: Custom Configuration" -ForegroundColor Green
Write-Host "=" * 50

try {
    $DeployResult = Invoke-DatabaseDeployment `
        -ZipFilePath "C:\Deploy\LargeDeployment.zip" `
        -ServerInstance "SQLSERVER01" `
        -DatabaseName "MyApplication" `
        -BackupPath "D:\Backups\Database" `
        -TempPath "D:\Temp\SQLDeploy" `
        -ExecutionTimeout 600 `
        -CreateRollbackScript
    
    Write-Host "Large deployment completed!" -ForegroundColor Green
}
catch {
    Write-Host "Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Example 4: Automated deployment script for CI/CD pipeline
Write-Host "`nExample 4: CI/CD Pipeline Integration" -ForegroundColor Green
Write-Host "=" * 50

function Invoke-CICDDatabaseDeployment {
    param(
        [string]$Environment,
        [string]$Version,
        [string]$ZipPath
    )
    
    # Environment-specific configurations
    $Config = switch ($Environment) {
        "DEV" { 
            @{
                ServerInstance = "DEV-SQL01"
                DatabaseName = "MyApp_Dev"
                BackupPath = "\\FileServer\Backups\Dev"
            }
        }
        "TEST" { 
            @{
                ServerInstance = "TEST-SQL01"
                DatabaseName = "MyApp_Test"
                BackupPath = "\\FileServer\Backups\Test"
            }
        }
        "PROD" { 
            @{
                ServerInstance = "PROD-SQL01"
                DatabaseName = "MyApp_Production"
                BackupPath = "\\FileServer\Backups\Production"
            }
        }
        default { throw "Unknown environment: $Environment" }
    }
    
    Write-Host "Deploying version $Version to $Environment environment..." -ForegroundColor Yellow
    
    try {
        # First, validate the deployment
        Write-Host "Step 1: Validating deployment package..." -ForegroundColor Cyan
        Invoke-DatabaseDeployment `
            -ZipFilePath $ZipPath `
            -ServerInstance $Config.ServerInstance `
            -DatabaseName $Config.DatabaseName `
            -BackupPath $Config.BackupPath `
            -WhatIf
        
        # If validation passes, proceed with actual deployment
        if ($Environment -eq "PROD") {
            # For production, require additional confirmation
            $Confirmation = Read-Host "This is a PRODUCTION deployment. Are you sure? (Type 'DEPLOY' to confirm)"
            if ($Confirmation -ne "DEPLOY") {
                throw "Production deployment cancelled by user"
            }
        }
        
        Write-Host "Step 2: Executing deployment..." -ForegroundColor Cyan
        $Result = Invoke-DatabaseDeployment `
            -ZipFilePath $ZipPath `
            -ServerInstance $Config.ServerInstance `
            -DatabaseName $Config.DatabaseName `
            -BackupPath $Config.BackupPath `
            -CreateRollbackScript `
            -ExecutionTimeout 900
        
        Write-Host "Deployment to $Environment completed successfully!" -ForegroundColor Green
        return $Result
    }
    catch {
        Write-Host "Deployment to $Environment failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# Example usage of CI/CD function
# Invoke-CICDDatabaseDeployment -Environment "DEV" -Version "1.2.3" -ZipPath "C:\Deploy\Release_1.2.3.zip"

# Example 5: Batch deployment across multiple databases
Write-Host "`nExample 5: Multi-Database Deployment" -ForegroundColor Green
Write-Host "=" * 50

function Invoke-MultiDatabaseDeployment {
    param(
        [string]$ZipFilePath,
        [hashtable[]]$Databases,
        [string]$BackupRootPath
    )
    
    $Results = @()
    
    foreach ($db in $Databases) {
        Write-Host "Deploying to $($db.Server)\$($db.Database)..." -ForegroundColor Yellow
        
        try {
            $BackupPath = Join-Path $BackupRootPath $db.Database
            
            $Result = Invoke-DatabaseDeployment `
                -ZipFilePath $ZipFilePath `
                -ServerInstance $db.Server `
                -DatabaseName $db.Database `
                -BackupPath $BackupPath `
                -CreateRollbackScript
            
            $Results += [PSCustomObject]@{
                Server = $db.Server
                Database = $db.Database
                Status = "Success"
                DeploymentId = $Result.DeploymentId
                ScriptsExecuted = $Result.ExecutedScripts
            }
            
            Write-Host "✓ $($db.Server)\$($db.Database) - Success" -ForegroundColor Green
        }
        catch {
            $Results += [PSCustomObject]@{
                Server = $db.Server
                Database = $db.Database
                Status = "Failed"
                Error = $_.Exception.Message
                DeploymentId = $null
                ScriptsExecuted = 0
            }
            
            Write-Host "✗ $($db.Server)\$($db.Database) - Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    return $Results
}

# Example databases array
$DatabaseList = @(
    @{ Server = "SERVER01"; Database = "App_Region1" },
    @{ Server = "SERVER02"; Database = "App_Region2" },
    @{ Server = "SERVER03"; Database = "App_Region3" }
)

# Example usage (commented out)
# $MultiResults = Invoke-MultiDatabaseDeployment -ZipFilePath "C:\Deploy\Global_Update.zip" -Databases $DatabaseList -BackupRootPath "C:\Backups"
# $MultiResults | Format-Table -AutoSize

Write-Host "`nAll examples completed!" -ForegroundColor Magenta
Write-Host "Note: Most examples are commented out to prevent accidental execution." -ForegroundColor Yellow
Write-Host "Uncomment and modify the examples as needed for your environment." -ForegroundColor Yellow 