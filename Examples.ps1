# SysAdminTools Usage Examples
# This script demonstrates how to use the SysAdminTools PowerShell module

# Import the module
Import-Module .\SysAdminTools.psd1

Write-Host "SysAdminTools Usage Examples" -ForegroundColor Green
Write-Host "============================" -ForegroundColor Green

Write-Host "`nAvailable Functions:" -ForegroundColor Cyan
Get-Command -Module SysAdminTools | ForEach-Object {
    Write-Host "  - $($_.Name)" -ForegroundColor White
}

Write-Host "`n=== COPY-DBADATABASE EXAMPLES ===" -ForegroundColor Magenta
Write-Host "Advanced Database Copy with Extensive Options" -ForegroundColor Magenta

Write-Host "`nA. Basic Complete Database Copy" -ForegroundColor Yellow
Write-Host "-------------------------------" -ForegroundColor Yellow
$dbExample1 = @'
# Copy entire database with all default options
Copy-DbaDatabase -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB"
'@
Write-Host $dbExample1 -ForegroundColor Gray

Write-Host "`nB. Structure-Only Copy (No Data)" -ForegroundColor Yellow
Write-Host "--------------------------------" -ForegroundColor Yellow
$dbExample2 = @'
# Copy database structure without table data
Copy-DbaDatabase -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevStructure" -IncludeTableData:$false
'@
Write-Host $dbExample2 -ForegroundColor Gray

Write-Host "`nC. Selective Copy with Exclusions" -ForegroundColor Yellow
Write-Host "---------------------------------" -ForegroundColor Yellow
$dbExample3 = @'
# Copy database excluding specific users, schemas, and permissions
Copy-DbaDatabase -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" `
    -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB" `
    -IncludeUserPermissions:$false `
    -ExcludeUsers @('sa', 'produser', 'serviceaccount') `
    -ExcludeSchemas @('temp', 'staging', 'archive')
'@
Write-Host $dbExample3 -ForegroundColor Gray

Write-Host "`nD. Backup/Restore Method with Logging" -ForegroundColor Yellow
Write-Host "-------------------------------------" -ForegroundColor Yellow
$dbExample4 = @'
# Use backup/restore method with comprehensive logging
$result = Copy-DbaDatabase -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" `
    -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB" `
    -Method BackupRestore -BackupPath "C:\Temp\Backups" `
    -ForceOverwrite -LogPath "C:\Logs" -Verify:$true

Write-Host "Copy completed in: $($result.Duration)" -ForegroundColor Green
Write-Host "Verification: Tables=$($result.VerificationResults.DestinationTableCount)" -ForegroundColor Cyan
'@
Write-Host $dbExample4 -ForegroundColor Gray

Write-Host "`nE. Production to Development Scenario" -ForegroundColor Yellow
Write-Host "------------------------------------" -ForegroundColor Yellow
$dbExample5 = @'
# Real-world production to development copy
Copy-DbaDatabase -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" `
    -SourceDatabase "CriticalApp" -DestinationDatabase "DevApp" `
    -IncludeTableData:$true `
    -IncludeUserPermissions:$false `
    -IncludeSystemObjects:$false `
    -ExcludeUsers @('produser1', 'produser2') `
    -ExcludeSchemas @('audit', 'logging') `
    -ForceOverwrite -BatchSize 50000 `
    -LogPath "C:\DatabaseMigrationLogs" -Verify:$true
'@
Write-Host $dbExample5 -ForegroundColor Gray

Write-Host "`n=== TABLE-SPECIFIC COPY EXAMPLES ===" -ForegroundColor Magenta
Write-Host "Fine-Grained Table Operations" -ForegroundColor Magenta

Write-Host "`n1. Basic Table Copy" -ForegroundColor Yellow
Write-Host "-------------------" -ForegroundColor Yellow
$example1 = @'
Copy-DbaUserTables -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB"
'@
Write-Host $example1 -ForegroundColor Gray

Write-Host "`n2. Advanced Table Copy with Force Overwrite" -ForegroundColor Yellow
Write-Host "--------------------------------------------" -ForegroundColor Yellow
$example2 = @'
Copy-DbaUserTables -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB" -Method Granular -ForceOverwrite -IncludeIndexes -IncludeConstraints -BatchSize 25000
'@
Write-Host $example2 -ForegroundColor Gray

Write-Host "`n3. Monitor Copy Progress" -ForegroundColor Yellow
Write-Host "-----------------------" -ForegroundColor Yellow
$example3 = @'
$progress = Get-CopyProgress -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB"
Write-Host "Copy Progress: $($progress.PercentComplete)% ($($progress.DestinationTableCount)/$($progress.SourceTableCount) tables)"

if ($progress.MissingTables.Count -gt 0) {
    Write-Host "Missing tables:"
    $progress.MissingTables | ForEach-Object { Write-Host "  - $_" }
}
'@
Write-Host $example3 -ForegroundColor Gray

Write-Host "`n4. Test Data Integrity" -ForegroundColor Yellow
Write-Host "----------------------" -ForegroundColor Yellow
$example4 = @'
# Test a specific table
$result = Test-TableDataIntegrity -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB" -TableSchema "dbo" -TableName "Users"

if ($result.Match) {
    Write-Host "✓ Data integrity verified for $($result.TableName)" -ForegroundColor Green
} else {
    Write-Warning "✗ Data mismatch: Source=$($result.SourceRows), Dest=$($result.DestinationRows)"
}
'@
Write-Host $example4 -ForegroundColor Gray

Write-Host "`n5. Comprehensive Integrity Check" -ForegroundColor Yellow
Write-Host "--------------------------------" -ForegroundColor Yellow
$example5 = @'
# Test all tables with progress display
$results = Test-AllTablesIntegrity -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB" -ShowProgress

# Check for failed tables
$failedTables = $results | Where-Object { -not $_.Match }
if ($failedTables.Count -gt 0) {
    Write-Warning "Found $($failedTables.Count) tables with integrity issues:"
    $failedTables | ForEach-Object {
        Write-Host "  - $($_.TableName): Source=$($_.SourceRows), Dest=$($_.DestinationRows)" -ForegroundColor Red
    }
} else {
    Write-Host "✓ All tables passed integrity check!" -ForegroundColor Green
}
'@
Write-Host $example5 -ForegroundColor Gray

Write-Host "`n6. Real-World Workflow Example" -ForegroundColor Yellow
Write-Host "------------------------------" -ForegroundColor Yellow
$example6 = @'
# Complete database migration workflow
try {
    # Step 1: Copy all tables
    Write-Host "Starting database migration..." -ForegroundColor Cyan
    Copy-DbaUserTables -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB" -ForceOverwrite
    
    # Step 2: Verify copy progress
    Write-Host "Checking copy progress..." -ForegroundColor Cyan
    $progress = Get-CopyProgress -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB"
    Write-Host "Migration: $($progress.PercentComplete)% complete"
    
    # Step 3: Validate data integrity
    Write-Host "Validating data integrity..." -ForegroundColor Cyan
    $integrityResults = Test-AllTablesIntegrity -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB"
    
    $passedTables = ($integrityResults | Where-Object { $_.Match }).Count
    $totalTables = $integrityResults.Count
    
    if ($passedTables -eq $totalTables) {
        Write-Host "✓ Migration completed successfully! All $totalTables tables validated." -ForegroundColor Green
    } else {
        Write-Warning "⚠ Migration completed with issues. $passedTables/$totalTables tables validated."
    }
}
catch {
    Write-Error "Migration failed: $($_.Exception.Message)"
}
'@
Write-Host $example6 -ForegroundColor Gray

Write-Host "`nGet Detailed Help:" -ForegroundColor Cyan
Write-Host "------------------" -ForegroundColor Cyan
Write-Host "Get-Help Copy-DbaDatabase -Full" -ForegroundColor Gray
Write-Host "Get-Help Copy-DbaUserTables -Full" -ForegroundColor Gray
Write-Host "Get-Help Test-TableDataIntegrity -Examples" -ForegroundColor Gray
Write-Host "Get-Help Get-CopyProgress -Detailed" -ForegroundColor Gray
Write-Host "Get-Help Test-AllTablesIntegrity -Full" -ForegroundColor Gray

Write-Host "`nTips:" -ForegroundColor Cyan
Write-Host "-----" -ForegroundColor Cyan
Write-Host "• Always test with non-production data first" -ForegroundColor Gray
Write-Host "• Use -ForceOverwrite carefully - it drops existing tables" -ForegroundColor Gray
Write-Host "• Monitor large migrations with Get-CopyProgress" -ForegroundColor Gray
Write-Host "• Validate results with Test-AllTablesIntegrity" -ForegroundColor Gray
Write-Host "• Use Granular method for maximum control over the process" -ForegroundColor Gray

Write-Host "`nReady to start! 🚀" -ForegroundColor Green
