# Quick Start Guide: Database Deployment

This guide will get you started with the `Invoke-DatabaseDeployment` function for automated database deployments.

## Prerequisites

1. **Install Required Modules**:
   ```powershell
   Install-Module -Name SqlServer -Scope CurrentUser
   Install-Module -Name dbatools -Scope CurrentUser  # Optional, for other functions
   ```

2. **Import SysAdminTools**:
   ```powershell
   Import-Module .\SysAdminTools.psd1
   ```

## Step 1: Prepare Your SQL Scripts

### Naming Convention
Name your SQL scripts so they execute in the correct order using natural sort:
- `001_CreateTables.sql`
- `002_AddIndexes.sql` 
- `003_InsertData.sql`
- `004_UpdateSchema.sql`

### Example Script Structure
```sql
-- 001_CreateTables.sql
USE [YourDatabase]
GO

CREATE TABLE dbo.Users (
    UserID int IDENTITY(1,1) PRIMARY KEY,
    Username nvarchar(50) NOT NULL,
    Email nvarchar(255) NOT NULL,
    CreatedDate datetime2 DEFAULT GETDATE()
);

PRINT 'Tables created successfully';
GO
```

### Create Deployment Package
1. Put all SQL scripts in a folder
2. Create a zip file containing the scripts
3. Example structure:
   ```
   DeploymentPackage.zip
   ├── 001_CreateTables.sql
   ├── 002_AddIndexes.sql
   ├── 003_InsertData.sql
   └── 004_UpdateSchema.sql
   ```

## Step 2: Test the Deployment

### Run in Validation Mode First
```powershell
# Test the deployment without executing (WhatIf mode)
Invoke-DatabaseDeployment `
    -ZipFilePath "C:\Deploy\Release_v1.0.0.zip" `
    -ServerInstance "localhost" `
    -DatabaseName "TestDB" `
    -BackupPath "C:\Backups" `
    -WhatIf
```

This will:
- ✅ Validate the zip file contents
- ✅ Test database connectivity
- ✅ Show which scripts would be executed
- ✅ Verify the execution order

## Step 3: Run the Deployment

### Basic Deployment
```powershell
$result = Invoke-DatabaseDeployment `
    -ZipFilePath "C:\Deploy\Release_v1.0.0.zip" `
    -ServerInstance "localhost" `
    -DatabaseName "TestDB" `
    -BackupPath "C:\Backups"

# Check results
Write-Host "Deployment ID: $($result.DeploymentId)"
Write-Host "Scripts executed: $($result.ExecutedScripts)"
```

### Deployment with Rollback Script Generation
```powershell
Invoke-DatabaseDeployment `
    -ZipFilePath "C:\Deploy\Release_v1.0.0.zip" `
    -ServerInstance "localhost" `
    -DatabaseName "TestDB" `
    -BackupPath "C:\Backups" `
    -CreateRollbackScript
```

## Step 4: Handle Deployment Failures

If a script fails during deployment, the function will:

1. **Stop execution** at the failed script
2. **Show progress** - which scripts succeeded and which failed
3. **Offer rollback** - prompt you to restore from the backup
4. **Provide detailed logs** for troubleshooting

### Example Failure Scenario
```
2024-12-19 14:30:25 [ERROR] FAILED to execute 003_InsertData.sql: Cannot insert duplicate key

Deployment failed on script: 003_InsertData.sql
Error: Cannot insert duplicate key row in object 'dbo.Users'

Executed scripts before failure:
  ✓ 001_CreateTables.sql
  ✓ 002_AddIndexes.sql

Do you want to rollback to the backup? (Y/N): Y

Restoring database from backup...
Database restored successfully
```

## Step 5: Production Deployment Best Practices

### 1. Use a Deployment Checklist
```powershell
# 1. Validate deployment package
Invoke-DatabaseDeployment -ZipFilePath $ZipPath -ServerInstance $Server -DatabaseName $DB -BackupPath $BackupPath -WhatIf

# 2. Create additional backup (optional)
# Manual backup commands here

# 3. Deploy with rollback script generation
Invoke-DatabaseDeployment -ZipFilePath $ZipPath -ServerInstance $Server -DatabaseName $DB -BackupPath $BackupPath -CreateRollbackScript

# 4. Verify deployment
# Run your verification queries here
```

### 2. CI/CD Integration Example
```powershell
function Deploy-ToEnvironment {
    param(
        [string]$Environment,
        [string]$ZipFilePath
    )
    
    $config = switch ($Environment) {
        "DEV"  { @{ Server = "DEV-SQL01";  DB = "App_Dev";  BackupPath = "\\Backups\Dev" } }
        "TEST" { @{ Server = "TEST-SQL01"; DB = "App_Test"; BackupPath = "\\Backups\Test" } }
        "PROD" { @{ Server = "PROD-SQL01"; DB = "App_Prod"; BackupPath = "\\Backups\Prod" } }
    }
    
    Write-Host "Deploying to $Environment..."
    
    # Always validate first
    Invoke-DatabaseDeployment -ZipFilePath $ZipFilePath -ServerInstance $config.Server -DatabaseName $config.DB -BackupPath $config.BackupPath -WhatIf
    
    # Production requires confirmation
    if ($Environment -eq "PROD") {
        $confirm = Read-Host "Deploy to PRODUCTION? Type 'DEPLOY' to confirm"
        if ($confirm -ne "DEPLOY") {
            Write-Host "Deployment cancelled" -ForegroundColor Yellow
            return
        }
    }
    
    # Execute deployment
    $result = Invoke-DatabaseDeployment -ZipFilePath $ZipFilePath -ServerInstance $config.Server -DatabaseName $config.DB -BackupPath $config.BackupPath -CreateRollbackScript
    
    Write-Host "Deployment completed successfully!" -ForegroundColor Green
    return $result
}

# Usage
Deploy-ToEnvironment -Environment "DEV" -ZipFilePath "C:\Deploy\Release_v1.0.0.zip"
```

## Troubleshooting

### Common Issues

#### 1. "SqlServer module not found"
```powershell
Install-Module -Name SqlServer -Scope CurrentUser -Force
```

#### 2. "Cannot connect to database"
- Verify server name and database exist
- Check SQL Server authentication/permissions
- Ensure SQL Server is running and accessible

#### 3. "No SQL files found in zip"
- Verify zip file contains .sql files
- Check file extensions are exactly `.sql`
- Ensure files are not in nested folders (or update script to handle recursion)

#### 4. "Access denied to backup path"
- Verify the backup directory exists
- Check write permissions to backup location
- Ensure SQL Server service account has access

### Log Files

The function creates detailed log files in the backup directory:
- `deployment_log_[ID]_[timestamp].txt` - Deployment execution log
- `rollback_script_[ID].sql` - Generated rollback script (if requested)

### Getting Help

```powershell
# View detailed help
Get-Help Invoke-DatabaseDeployment -Detailed

# View examples
Get-Help Invoke-DatabaseDeployment -Examples

# Test the module
.\Test-DatabaseDeployment.ps1 -CreateTestData
```

## Next Steps

1. **Create test environment**: Set up a test database to practice deployments
2. **Develop naming standards**: Establish script naming conventions for your team
3. **Integration**: Incorporate into your CI/CD pipeline
4. **Monitoring**: Set up alerting for deployment failures
5. **Documentation**: Document your deployment processes and rollback procedures

---

**Need more help?** Check the main README.md or create an issue in the repository. 