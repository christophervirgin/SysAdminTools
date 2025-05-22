function Test-AllTablesIntegrity {
<#
.SYNOPSIS
    Test data integrity for all tables between source and destination databases
    
.DESCRIPTION
    Performs comprehensive data integrity checking by comparing row counts for all user tables between source and destination databases.
    
.PARAMETER SourceInstance
    Source SQL Server instance name
    
.PARAMETER DestinationInstance
    Destination SQL Server instance name
    
.PARAMETER SourceDatabase
    Source database name
    
.PARAMETER DestinationDatabase
    Destination database name
    
.PARAMETER ShowProgress
    Display progress information during the integrity check
    
.EXAMPLE
    Test-AllTablesIntegrity -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB"
    
.EXAMPLE
    $results = Test-AllTablesIntegrity -SourceInstance "SQL01" -DestinationInstance "SQL02" -SourceDatabase "DB1" -DestinationDatabase "DB2" -ShowProgress
    $failedTables = $results | Where-Object { -not $_.Match }
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
        [switch]$ShowProgress
    )
    
    function Write-LogMessage {
        param([string]$Message, [string]$Level = 'INFO')
        if ($ShowProgress) {
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(
                switch ($Level) {
                    'ERROR' { 'Red' }
                    'WARNING' { 'Yellow' }
                    'SUCCESS' { 'Green' }
                    default { 'White' }
                }
            )
        }
    }
    
    try {
        # Import dbatools if not already loaded
        if (-not (Get-Module -Name dbatools)) {
            Import-Module dbatools
        }
        
        Write-LogMessage "Starting comprehensive data integrity check..."
        
        $sourceTables = Get-DbaDbTable -SqlInstance $SourceInstance -Database $SourceDatabase | 
                       Where-Object { $_.Schema -ne 'sys' -and $_.IsSystemObject -eq $false }
        
        if ($sourceTables.Count -eq 0) {
            Write-LogMessage "No user tables found in source database" -Level 'WARNING'
            return @()
        }
        
        Write-LogMessage "Found $($sourceTables.Count) tables to check"
        
        $results = @()
        $currentTable = 0
        
        foreach ($table in $sourceTables) {
            $currentTable++
            
            try {
                if ($ShowProgress) {
                    $percentComplete = [math]::Round(($currentTable / $sourceTables.Count) * 100, 1)
                    Write-Progress -Activity "Checking table integrity" -Status "Processing table $currentTable of $($sourceTables.Count)" -PercentComplete $percentComplete
                }
                
                $integrity = Test-TableDataIntegrity -SourceInstance $SourceInstance -DestinationInstance $DestinationInstance -SourceDatabase $SourceDatabase -DestinationDatabase $DestinationDatabase -TableSchema $table.Schema -TableName $table.Name
                $results += $integrity
                
                $status = if ($integrity.Match) { "✓" } else { "✗" }
                Write-LogMessage "$status $($integrity.TableName): Source=$($integrity.SourceRows), Dest=$($integrity.DestinationRows)"
            }
            catch {
                Write-LogMessage "✗ [$($table.Schema)].[$($table.Name)]: Error checking integrity - $($_.Exception.Message)" -Level 'WARNING'
                $results += @{
                    TableName = "[$($table.Schema)].[$($table.Name)]"
                    SourceRows = $null
                    DestinationRows = $null
                    Match = $false
                    Error = $_.Exception.Message
                }
            }
        }
        
        if ($ShowProgress) {
            Write-Progress -Activity "Checking table integrity" -Completed
        }
        
        $matchingTables = ($results | Where-Object { $_.Match }).Count
        $totalTables = $results.Count
        $failedTables = $results | Where-Object { -not $_.Match }
        
        Write-LogMessage "Integrity check complete: $matchingTables/$totalTables tables match" -Level $(if ($matchingTables -eq $totalTables) { 'SUCCESS' } else { 'WARNING' })
        
        if ($failedTables.Count -gt 0) {
            Write-LogMessage "Tables with integrity issues:" -Level 'WARNING'
            foreach ($failedTable in $failedTables) {
                if ($failedTable.Error) {
                    Write-LogMessage "  $($failedTable.TableName): Error - $($failedTable.Error)" -Level 'WARNING'
                } else {
                    Write-LogMessage "  $($failedTable.TableName): Source=$($failedTable.SourceRows), Dest=$($failedTable.DestinationRows)" -Level 'WARNING'
                }
            }
        }
        
        return $results
    }
    catch {
        Write-LogMessage "Failed to perform integrity check: $($_.Exception.Message)" -Level 'ERROR'
        throw
    }
}
