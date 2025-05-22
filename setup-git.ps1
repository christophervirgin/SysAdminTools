# Initialize Git Repository for SysAdminTools PowerShell Module
[CmdletBinding()]
param()

Write-Host "Initializing Git repository for SysAdminTools..." -ForegroundColor Green

# Get the script directory
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $ScriptPath

try {
    # Check if git is available
    $gitVersion = git --version 2>$null
    if (-not $gitVersion) {
        Write-Warning "Git is not installed or not in PATH. Please install Git first."
        Write-Host "Download Git from: https://git-scm.com/downloads"
        return
    }
    
    Write-Host "Found Git: $gitVersion" -ForegroundColor Cyan
    
    # Check if already a git repository
    if (Test-Path ".git\HEAD") {
        Write-Host "Git repository already initialized." -ForegroundColor Yellow
    }
    else {
        Write-Host "Initializing git repository..." -ForegroundColor Cyan
        
        # Initialize git repository
        git init
        
        # Set initial branch to main
        try {
            git checkout -b main 2>$null
        }
        catch {
            git branch -M main 2>$null
        }
        
        # Configure git if needed (optional - user can set globally)
        $userName = git config user.name 2>$null
        $userEmail = git config user.email 2>$null
        
        if (-not $userName) {
            Write-Host "Git user.name not configured. You may want to set it:" -ForegroundColor Yellow
            Write-Host "  git config --global user.name `"Your Name`"" -ForegroundColor Gray
        }
        
        if (-not $userEmail) {
            Write-Host "Git user.email not configured. You may want to set it:" -ForegroundColor Yellow
            Write-Host "  git config --global user.email `"your.email@domain.com`"" -ForegroundColor Gray
        }
        
        # Add all files
        Write-Host "Adding files to git..." -ForegroundColor Cyan
        git add .
        
        # Initial commit
        Write-Host "Creating initial commit..." -ForegroundColor Cyan
        $commitMessage = @"
Initial commit: SysAdminTools PowerShell module

Features:
- Copy-DbaUserTables: Copy schema and data for all user tables between SQL Server databases
- Test-TableDataIntegrity: Verify data integrity by comparing row counts
- Get-CopyProgress: Monitor table copy operation progress
- Test-AllTablesIntegrity: Comprehensive integrity checking for all tables

Module structure follows PowerShell best practices with proper manifest, module file, and individual function files.
"@
        
        git commit -m $commitMessage
        
        Write-Host "`nGit repository initialized successfully!" -ForegroundColor Green
    }
    
    Write-Host "`nTo add a remote repository:" -ForegroundColor Cyan
    Write-Host "  git remote add origin https://github.com/username/SysAdminTools.git" -ForegroundColor Gray
    Write-Host "  git push -u origin main" -ForegroundColor Gray
    
    Write-Host "`nRepository status:" -ForegroundColor Cyan
    git status
    
    Write-Host "`nRepository structure:" -ForegroundColor Cyan
    tree /f 2>$null || dir /s /b
}
catch {
    Write-Error "Failed to initialize git repository: $($_.Exception.Message)"
}

Write-Host "`nSysAdminTools module is ready!" -ForegroundColor Green
Write-Host "To use the module:" -ForegroundColor Cyan
Write-Host "  Import-Module .\SysAdminTools.psd1" -ForegroundColor Gray
Write-Host "  Get-Command -Module SysAdminTools" -ForegroundColor Gray
