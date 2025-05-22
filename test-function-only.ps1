#!/usr/bin/env pwsh

Write-Host "Testing function syntax..." -ForegroundColor Yellow

try {
    # Source the function directly
    . ./Functions/Invoke-DatabaseDeployment.ps1
    Write-Host "✓ Function sourced successfully" -ForegroundColor Green
    
    # Check if function is available
    $func = Get-Command Invoke-DatabaseDeployment -ErrorAction SilentlyContinue
    if ($func) {
        Write-Host "✓ Function is available: $($func.Name)" -ForegroundColor Green
        Write-Host "  Parameters: $($func.Parameters.Count)" -ForegroundColor Cyan
        Write-Host "  Source: $($func.Source)" -ForegroundColor Cyan
    } else {
        Write-Host "✗ Function not found after sourcing" -ForegroundColor Red
    }
    
    # Test help
    $help = Get-Help Invoke-DatabaseDeployment -ErrorAction SilentlyContinue
    if ($help -and $help.Synopsis) {
        Write-Host "✓ Help available: $($help.Synopsis)" -ForegroundColor Green
    } else {
        Write-Host "⚠ Help not available or incomplete" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "✗ Error sourcing function: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
} 