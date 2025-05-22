# Test script for SysAdminTools PowerShell Module
[CmdletBinding()]
param(
    [switch]$Detailed
)

Write-Host "Testing SysAdminTools PowerShell Module..." -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Green

$TestResults = @{
    ModuleLoad = $false
    FunctionsAvailable = $false
    DependencyCheck = $false
    HelpAvailable = $false
    ParameterValidation = $false
}

try {
    # Test 1: Module Loading
    Write-Host "`n1. Testing module loading..." -ForegroundColor Cyan
    $ModulePath = Join-Path $PSScriptRoot "SysAdminTools.psd1"
    
    if (Test-Path $ModulePath) {
        Import-Module $ModulePath -Force
        $TestResults.ModuleLoad = $true
        Write-Host "   ✓ Module loaded successfully" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Module manifest not found" -ForegroundColor Red
    }
    
    # Test 2: Functions Available
    Write-Host "`n2. Testing exported functions..." -ForegroundColor Cyan
    $ExpectedFunctions = @(
        'Copy-DbaUserTables',
        'Test-TableDataIntegrity', 
        'Get-CopyProgress',
        'Test-AllTablesIntegrity'
    )
    
    $AvailableFunctions = Get-Command -Module SysAdminTools -ErrorAction SilentlyContinue
    
    if ($AvailableFunctions.Count -eq $ExpectedFunctions.Count) {
        $TestResults.FunctionsAvailable = $true
        Write-Host "   ✓ All $($ExpectedFunctions.Count) functions exported correctly" -ForegroundColor Green
        
        if ($Detailed) {
            foreach ($func in $AvailableFunctions) {
                Write-Host "     - $($func.Name)" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "   ✗ Function count mismatch. Expected: $($ExpectedFunctions.Count), Found: $($AvailableFunctions.Count)" -ForegroundColor Red
        
        $MissingFunctions = $ExpectedFunctions | Where-Object { $_ -notin $AvailableFunctions.Name }
        if ($MissingFunctions) {
            Write-Host "     Missing functions: $($MissingFunctions -join ', ')" -ForegroundColor Red
        }
    }
    
    # Test 3: Dependency Check
    Write-Host "`n3. Testing dependencies..." -ForegroundColor Cyan
    $DbaToolsAvailable = Get-Module -ListAvailable -Name dbatools -ErrorAction SilentlyContinue
    
    if ($DbaToolsAvailable) {
        $TestResults.DependencyCheck = $true
        Write-Host "   ✓ dbatools module is available" -ForegroundColor Green
        if ($Detailed) {
            Write-Host "     Version: $($DbaToolsAvailable.Version)" -ForegroundColor Gray
        }
    } else {
        Write-Host "   ⚠ dbatools module not found (required for functionality)" -ForegroundColor Yellow
        Write-Host "     Install with: Install-Module -Name dbatools" -ForegroundColor Gray
    }
    
    # Test 4: Help Available
    Write-Host "`n4. Testing help content..." -ForegroundColor Cyan
    $HelpTestsPassed = 0
    
    foreach ($func in $ExpectedFunctions) {
        $help = Get-Help $func -ErrorAction SilentlyContinue
        if ($help -and $help.Synopsis) {
            $HelpTestsPassed++
        }
    }
    
    if ($HelpTestsPassed -eq $ExpectedFunctions.Count) {
        $TestResults.HelpAvailable = $true
        Write-Host "   ✓ Help content available for all functions" -ForegroundColor Green
    } else {
        Write-Host "   ⚠ Help content missing for some functions ($HelpTestsPassed/$($ExpectedFunctions.Count))" -ForegroundColor Yellow
    }
    
    # Test 5: Parameter Validation
    Write-Host "`n5. Testing parameter validation..." -ForegroundColor Cyan
    try {
        # Test Copy-DbaUserTables parameter validation
        $params = (Get-Command Copy-DbaUserTables).Parameters
        $requiredParams = @('SourceInstance', 'DestinationInstance', 'SourceDatabase', 'DestinationDatabase')
        
        $allRequiredPresent = $true
        foreach ($reqParam in $requiredParams) {
            if (-not $params.ContainsKey($reqParam)) {
                $allRequiredPresent = $false
                Write-Host "   ✗ Missing required parameter: $reqParam" -ForegroundColor Red
            }
        }
        
        if ($allRequiredPresent) {
            $TestResults.ParameterValidation = $true
            Write-Host "   ✓ All required parameters present" -ForegroundColor Green
        }
        
        # Test parameter sets
        if ($params.ContainsKey('Method') -and $params.ContainsKey('ForceOverwrite')) {
            Write-Host "   ✓ Advanced parameters available" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "   ✗ Error testing parameters: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Summary
    Write-Host "`n" + "="*50 -ForegroundColor Green
    Write-Host "TEST SUMMARY" -ForegroundColor Green
    Write-Host "="*50 -ForegroundColor Green
    
    $PassedTests = ($TestResults.Values | Where-Object { $_ }).Count
    $TotalTests = $TestResults.Count
    
    foreach ($test in $TestResults.GetEnumerator()) {
        $status = if ($test.Value) { "PASS" } else { "FAIL" }
        $color = if ($test.Value) { "Green" } else { "Red" }
        Write-Host "  $($test.Key): $status" -ForegroundColor $color
    }
    
    Write-Host "`nOverall: $PassedTests/$TotalTests tests passed" -ForegroundColor $(if ($PassedTests -eq $TotalTests) { "Green" } else { "Yellow" })
    
    if ($PassedTests -eq $TotalTests) {
        Write-Host "`n🎉 All tests passed! SysAdminTools module is ready to use." -ForegroundColor Green
        Write-Host "`nQuick start:" -ForegroundColor Cyan
        Write-Host "  Get-Command -Module SysAdminTools" -ForegroundColor Gray
        Write-Host "  Get-Help Copy-DbaUserTables -Full" -ForegroundColor Gray
    } else {
        Write-Host "`n⚠ Some tests failed. Please review the issues above." -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Test execution failed: $($_.Exception.Message)"
}
finally {
    # Clean up
    if (Get-Module SysAdminTools) {
        Remove-Module SysAdminTools
    }
}
