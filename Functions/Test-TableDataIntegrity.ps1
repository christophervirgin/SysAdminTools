function Test-TableDataIntegrity {
<#
.SYNOPSIS
    Test data integrity between source and destination tables by comparing row counts
    
.DESCRIPTION
    Compares row counts between the same table in source and destination databases to verify data integrity after a copy operation.
    
.PARAMETER SourceInstance
    Source SQL Server instance name
    
.PARAMETER DestinationInstance
    Destination SQL Server instance name
    
.PARAMETER SourceDatabase
    Source database name
    
.PARAMETER DestinationDatabase
    Destination database name
    
.PARAMETER TableSchema
    Schema name of the table to test
    
.PARAMETER TableName
    Name of the table to test
    
.EXAMPLE
    Test-TableDataIntegrity -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB" -TableSchema "dbo" -TableName "Users"
    
.EXAMPLE
    $result = Test-TableDataIntegrity -SourceInstance "SQL01" -DestinationInstance "SQL02" -SourceDatabase "DB1" -DestinationDatabase "DB2" -TableSchema "Sales" -TableName "Orders"
    if ($result.Match) { Write-Host "Data integrity verified!" }
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
        
        [Parameter(Mandatory = $true)]
        [string]$TableSchema,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    try {
        # Import dbatools if not already loaded
        if (-not (Get-Module -Name dbatools)) {
            Import-Module dbatools
        }
        
        $sourceCount = (Invoke-DbaQuery -SqlInstance $SourceInstance -Database $SourceDatabase -Query "SELECT COUNT(*) as RowCount FROM [$TableSchema].[$TableName]").RowCount
        $destCount = (Invoke-DbaQuery -SqlInstance $DestinationInstance -Database $DestinationDatabase -Query "SELECT COUNT(*) as RowCount FROM [$TableSchema].[$TableName]").RowCount
        
        return @{
            TableName = "[$TableSchema].[$TableName]"
            SourceRows = $sourceCount
            DestinationRows = $destCount
            Match = ($sourceCount -eq $destCount)
        }
    }
    catch {
        Write-Error "Failed to test table data integrity for [$TableSchema].[$TableName]: $($_.Exception.Message)"
        return @{
            TableName = "[$TableSchema].[$TableName]"
            SourceRows = $null
            DestinationRows = $null
            Match = $false
            Error = $_.Exception.Message
        }
    }
}
