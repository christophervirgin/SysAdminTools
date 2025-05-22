function Get-CopyProgress {
<#
.SYNOPSIS
    Get the progress of a database table copy operation
    
.DESCRIPTION
    Compares the number of tables between source and destination databases to determine copy progress and identify missing tables.
    
.PARAMETER SourceInstance
    Source SQL Server instance name
    
.PARAMETER DestinationInstance
    Destination SQL Server instance name
    
.PARAMETER SourceDatabase
    Source database name
    
.PARAMETER DestinationDatabase
    Destination database name
    
.EXAMPLE
    Get-CopyProgress -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB"
    
.EXAMPLE
    $progress = Get-CopyProgress -SourceInstance "SQL01" -DestinationInstance "SQL02" -SourceDatabase "DB1" -DestinationDatabase "DB2"
    Write-Host "Copy Progress: $($progress.PercentComplete)% ($($progress.DestinationTableCount)/$($progress.SourceTableCount) tables)"
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
        [string]$DestinationDatabase
    )
    
    try {
        # Import dbatools if not already loaded
        if (-not (Get-Module -Name dbatools)) {
            Import-Module dbatools
        }
        
        $sourceTables = Get-DbaDbTable -SqlInstance $SourceInstance -Database $SourceDatabase | 
                       Where-Object { $_.Schema -ne 'sys' -and $_.IsSystemObject -eq $false }
        
        $destTables = Get-DbaDbTable -SqlInstance $DestinationInstance -Database $DestinationDatabase -ErrorAction SilentlyContinue | 
                     Where-Object { $_.Schema -ne 'sys' -and $_.IsSystemObject -eq $false }
        
        $progress = @{
            SourceTableCount = $sourceTables.Count
            DestinationTableCount = if ($destTables) { $destTables.Count } else { 0 }
            PercentComplete = 0
            MissingTables = @()
            ExtraTables = @()
            MatchingTables = @()
        }
        
        # Calculate percentage
        if ($sourceTables.Count -gt 0) {
            $progress.PercentComplete = [math]::Round(($progress.DestinationTableCount / $sourceTables.Count) * 100, 2)
        }
        
        # Find missing tables (in source but not in destination)
        foreach ($sourceTable in $sourceTables) {
            $found = $destTables | Where-Object { $_.Schema -eq $sourceTable.Schema -and $_.Name -eq $sourceTable.Name }
            if (-not $found) {
                $progress.MissingTables += "[$($sourceTable.Schema)].[$($sourceTable.Name)]"
            } else {
                $progress.MatchingTables += "[$($sourceTable.Schema)].[$($sourceTable.Name)]"
            }
        }
        
        # Find extra tables (in destination but not in source)
        if ($destTables) {
            foreach ($destTable in $destTables) {
                $found = $sourceTables | Where-Object { $_.Schema -eq $destTable.Schema -and $_.Name -eq $destTable.Name }
                if (-not $found) {
                    $progress.ExtraTables += "[$($destTable.Schema)].[$($destTable.Name)]"
                }
            }
        }
        
        return $progress
    }
    catch {
        Write-Error "Failed to get copy progress: $($_.Exception.Message)"
        return @{
            SourceTableCount = 0
            DestinationTableCount = 0
            PercentComplete = 0
            MissingTables = @()
            ExtraTables = @()
            MatchingTables = @()
            Error = $_.Exception.Message
        }
    }
}
