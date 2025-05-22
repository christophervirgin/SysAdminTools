#!/usr/bin/env pwsh

# Simple test script to verify module loading
try {
    Write-Host "Testing SysAdminTools module..." -ForegroundColor Yellow
    
    # Import the module
    Import-Module ./SysAdminTools.psd1 -Force
    Write-Host "✓ Module imported successfully" -ForegroundColor Green
    
    # List all commands in the module
    $Commands = Get-Command -Module SysAdminTools
    Write-Host "Available commands in module: $($Commands.Count)" -ForegroundColor Cyan
    foreach ($cmd in $Commands) {
        Write-Host "  - $($cmd.Name) ($($cmd.CommandType))" -ForegroundColor White
    }
    
    # Check if the new function is available
    if (Get-Command Invoke-DatabaseDeployment -ErrorAction SilentlyContinue) {
        Write-Host "✓ Invoke-DatabaseDeployment function is available" -ForegroundColor Green
        
        # Test getting help
        $help = Get-Help Invoke-DatabaseDeployment -ErrorAction SilentlyContinue
        if ($help) {
            Write-Host "✓ Function help is available" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ Function help not available" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "✗ Invoke-DatabaseDeployment function not found" -ForegroundColor Red
    }
    
    Write-Host "`nTest completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "Test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
