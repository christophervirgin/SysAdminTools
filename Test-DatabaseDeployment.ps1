# Test script for Database Deployment functionality
# This script tests the deployment function without requiring live database connections

param(
    [switch]$CreateTestData
)

Write-Host "Testing Database Deployment Function" -ForegroundColor Green
Write-Host "=" * 50

# Import the module
try {
    Import-Module .\SysAdminTools.psd1 -Force
    Write-Host "✓ SysAdminTools module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to load module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Check if the function is available
if (Get-Command Invoke-DatabaseDeployment -ErrorAction SilentlyContinue) {
    Write-Host "✓ Invoke-DatabaseDeployment function is available" -ForegroundColor Green
}
else {
    Write-Host "✗ Invoke-DatabaseDeployment function not found" -ForegroundColor Red
    exit 1
}

# Create test data if requested
if ($CreateTestData) {
    Write-Host "`nCreating test data..." -ForegroundColor Yellow
    
    # Create test directory structure
    $TestDir = ".\TestData"
    $ScriptsDir = Join-Path $TestDir "Scripts"
    $BackupsDir = Join-Path $TestDir "Backups"
    
    New-Item -Path $TestDir -ItemType Directory -Force | Out-Null
    New-Item -Path $ScriptsDir -ItemType Directory -Force | Out-Null
    New-Item -Path $BackupsDir -ItemType Directory -Force | Out-Null
    
    # Create sample SQL scripts with proper naming for natural sort order
    $Scripts = @(
        @{
            Name = "001_CreateTables.sql"
            Content = @"
-- Script 001: Create Tables
-- This script creates the initial table structure

CREATE TABLE dbo.Users (
    UserID int IDENTITY(1,1) PRIMARY KEY,
    Username nvarchar(50) NOT NULL,
    Email nvarchar(255) NOT NULL,
    CreatedDate datetime2 DEFAULT GETDATE()
);

CREATE TABLE dbo.UserProfiles (
    ProfileID int IDENTITY(1,1) PRIMARY KEY,
    UserID int NOT NULL,
    FirstName nvarchar(50),
    LastName nvarchar(50),
    FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID)
);

PRINT 'Tables created successfully';
"@
        },
        @{
            Name = "002_AddIndexes.sql"
            Content = @"
-- Script 002: Add Indexes
-- This script adds indexes for better performance

CREATE NONCLUSTERED INDEX IX_Users_Username 
ON dbo.Users (Username);

CREATE NONCLUSTERED INDEX IX_Users_Email 
ON dbo.Users (Email);

CREATE NONCLUSTERED INDEX IX_UserProfiles_UserID 
ON dbo.UserProfiles (UserID);

PRINT 'Indexes created successfully';
"@
        },
        @{
            Name = "003_InsertData.sql"
            Content = @"
-- Script 003: Insert Initial Data
-- This script inserts sample data

INSERT INTO dbo.Users (Username, Email) VALUES 
('john.doe', 'john.doe@example.com'),
('jane.smith', 'jane.smith@example.com'),
('admin', 'admin@example.com');

INSERT INTO dbo.UserProfiles (UserID, FirstName, LastName)
SELECT UserID, 
       CASE 
           WHEN Username = 'john.doe' THEN 'John'
           WHEN Username = 'jane.smith' THEN 'Jane'
           WHEN Username = 'admin' THEN 'Administrator'
       END,
       CASE 
           WHEN Username = 'john.doe' THEN 'Doe'
           WHEN Username = 'jane.smith' THEN 'Smith'
           WHEN Username = 'admin' THEN 'User'
       END
FROM dbo.Users;

PRINT 'Initial data inserted successfully';
"@
        },
        @{
            Name = "004_UpdateSchema.sql"
            Content = @"
-- Script 004: Schema Updates
-- This script adds new columns and constraints

ALTER TABLE dbo.Users 
ADD IsActive bit DEFAULT 1,
    LastLoginDate datetime2 NULL;

ALTER TABLE dbo.UserProfiles 
ADD PhoneNumber nvarchar(20) NULL,
    DateOfBirth date NULL;

-- Update existing users to be active
UPDATE dbo.Users SET IsActive = 1;

PRINT 'Schema updates completed successfully';
"@
        }
    )
    
    # Create the SQL files
    foreach ($script in $Scripts) {
        $FilePath = Join-Path $ScriptsDir $script.Name
        Set-Content -Path $FilePath -Value $script.Content -Encoding UTF8
        Write-Host "  Created: $($script.Name)" -ForegroundColor Cyan
    }
    
    # Create a zip file containing the scripts
    $ZipPath = Join-Path $TestDir "TestDeployment.zip"
    if (Test-Path $ZipPath) {
        Remove-Item $ZipPath -Force
    }
    
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($ScriptsDir, $ZipPath)
    
    Write-Host "✓ Test deployment package created: $ZipPath" -ForegroundColor Green
    Write-Host "✓ Test backup directory ready: $BackupsDir" -ForegroundColor Green
    
    Write-Host "`nTest data created successfully!" -ForegroundColor Green
    Write-Host "You can now test the deployment function with:" -ForegroundColor Yellow
    Write-Host "  ZipFilePath: $ZipPath" -ForegroundColor White
    Write-Host "  BackupPath: $BackupsDir" -ForegroundColor White
    
    return
}

# Test the function help
Write-Host "`nTesting function help..." -ForegroundColor Yellow
try {
    Get-Help Invoke-DatabaseDeployment -Detailed | Out-Null
    Write-Host "✓ Function help is available" -ForegroundColor Green
}
catch {
    Write-Host "✗ Function help test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test parameter validation
Write-Host "`nTesting parameter validation..." -ForegroundColor Yellow

try {
    # Test with non-existent zip file (should fail validation)
    Invoke-DatabaseDeployment -ZipFilePath "NonExistent.zip" -ServerInstance "test" -DatabaseName "test" -BackupPath "." -WhatIf -ErrorAction Stop
    Write-Host "✗ Parameter validation failed - should have caught non-existent zip file" -ForegroundColor Red
}
catch {
    Write-Host "✓ Parameter validation working - caught invalid zip file path" -ForegroundColor Green
}

# Test if SqlServer module check works
Write-Host "`nTesting SqlServer module requirement..." -ForegroundColor Yellow
$SqlServerModule = Get-Module -Name SqlServer -ListAvailable
if ($SqlServerModule) {
    Write-Host "✓ SqlServer module is available: $($SqlServerModule[0].Version)" -ForegroundColor Green
}
else {
    Write-Host "⚠ SqlServer module not found - install with: Install-Module -Name SqlServer" -ForegroundColor Yellow
}

Write-Host "`nTesting Complete!" -ForegroundColor Green
Write-Host "`nTo create test data, run: .\Test-DatabaseDeployment.ps1 -CreateTestData" -ForegroundColor Cyan
Write-Host "To test with real database, ensure SqlServer module is installed and use the created test data." -ForegroundColor Cyan 