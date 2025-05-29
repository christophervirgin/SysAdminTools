# SQL Server File Processing Script
# Processes files from network location and updates database with MIME type and binary data
function Upload-FilesToSql {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SqlServer,
    
        [Parameter(Mandatory = $true)]
        [string]$Database,
    
        [Parameter(Mandatory = $true)]
        [string]$TableName,
    
        [Parameter(Mandatory = $true)]
        [string]$FilenameColumn,
    
        [Parameter(Mandatory = $true)]
        [string]$MimeTypeColumn,
    
        [Parameter(Mandatory = $true)]
        [string]$ByteDataColumn,
    
        [Parameter(Mandatory = $true)]
        [string]$NetworkPath,
    
        [string]$KeyColumn = "Id",
        [string]$ConnectionTimeout = 30,
        [string]$CommandTimeout = 300
    )

    # Add required assemblies
    Add-Type -AssemblyName System.Data
    Add-Type -AssemblyName System.Web

    # Function to get MIME type
    function Get-MimeType {
        param([string]$FilePath)
    
        try {
            # Try using System.Web.MimeMapping first
            $mimeType = [System.Web.MimeMapping]::GetMimeMapping($FilePath)
            if ($mimeType -and $mimeType -ne "application/octet-stream") {
                return $mimeType
            }
        
            # Fallback to common file extensions
            $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
            switch ($extension) {
                ".pdf" { return "application/pdf" }
                ".doc" { return "application/msword" }
                ".docx" { return "application/vnd.openxmlformats-officedocument.wordprocessingml.document" }
                ".xls" { return "application/vnd.ms-excel" }
                ".xlsx" { return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }
                ".ppt" { return "application/vnd.ms-powerpoint" }
                ".pptx" { return "application/vnd.openxmlformats-officedocument.presentationml.presentation" }
                ".txt" { return "text/plain" }
                ".jpg" { return "image/jpeg" }
                ".jpeg" { return "image/jpeg" }
                ".png" { return "image/png" }
                ".gif" { return "image/gif" }
                ".zip" { return "application/zip" }
                ".xml" { return "application/xml" }
                ".json" { return "application/json" }
                default { return "application/octet-stream" }
            }
        }
        catch {
            Write-Warning "Could not determine MIME type for $FilePath. Using default."
            return "application/octet-stream"
        }
    }

    # Function to create SQL connection
    function New-SqlConnection {
        param([string]$Server, [string]$Database, [int]$Timeout)
    
        $connectionString = "Server=$Server;Database=$Database;Integrated Security=true;Connection Timeout=$Timeout"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    
        try {
            $connection.Open()
            return $connection
        }
        catch {
            Write-Error "Failed to connect to SQL Server: $_"
            throw
        }
    }

    # Function to execute SQL query
    function Invoke-SqlQuery {
        param(
            [System.Data.SqlClient.SqlConnection]$Connection,
            [string]$Query,
            [int]$Timeout,
            [hashtable]$Parameters = @{}
        )
    
        $command = New-Object System.Data.SqlClient.SqlCommand($Query, $Connection)
        $command.CommandTimeout = $Timeout
    
        # Add parameters
        foreach ($param in $Parameters.GetEnumerator()) {
            $sqlParam = $command.Parameters.AddWithValue($param.Key, $param.Value)
            if ($param.Value -is [byte[]]) {
                $sqlParam.SqlDbType = [System.Data.SqlDbType]::VarBinary
            }
        }
    
        return $command.ExecuteNonQuery()
    }

    # Function to get data table from SQL query
    function Get-SqlDataTable {
        param(
            [System.Data.SqlClient.SqlConnection]$Connection,
            [string]$Query,
            [int]$Timeout
        )
    
        $command = New-Object System.Data.SqlClient.SqlCommand($Query, $Connection)
        $command.CommandTimeout = $Timeout
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
        $dataTable = New-Object System.Data.DataTable
        $adapter.Fill($dataTable) | Out-Null
    
        return $dataTable
    }

    # Main script execution
    try {
        Write-Host "Starting file processing script..." -ForegroundColor Green
        Write-Host "SQL Server: $SqlServer" -ForegroundColor Gray
        Write-Host "Database: $Database" -ForegroundColor Gray
        Write-Host "Network Path: $NetworkPath" -ForegroundColor Gray
        Write-Host ""

        # Step 1: Connect to SQL Server and get filenames
        Write-Host "Step 1: Connecting to SQL Server and retrieving filenames..." -ForegroundColor Cyan
        $sqlConnection = New-SqlConnection -Server $SqlServer -Database $Database -Timeout $ConnectionTimeout
    
        $query = "SELECT [$KeyColumn], [$FilenameColumn] FROM [$TableName] WHERE [$FilenameColumn] IS NOT NULL AND [$FilenameColumn] != ''"
        $dbFiles = Get-SqlDataTable -Connection $sqlConnection -Query $query -Timeout $CommandTimeout
    
        Write-Host "Found $($dbFiles.Rows.Count) records in database" -ForegroundColor Yellow

        # Step 2: Get files from network location
        Write-Host "Step 2: Scanning network location for files..." -ForegroundColor Cyan
    
        if (-not (Test-Path $NetworkPath)) {
            throw "Network path '$NetworkPath' is not accessible"
        }
    
        $networkFiles = Get-ChildItem -Path $NetworkPath -File -Recurse | Select-Object Name, FullName
        Write-Host "Found $($networkFiles.Count) files in network location" -ForegroundColor Yellow

        # Step 3: Find matches and identify duplicates
        Write-Host "Step 3: Finding matches and checking for duplicates..." -ForegroundColor Cyan
    
        $matches = @()
        $duplicates = @()
        $processedFiles = @{}
    
        foreach ($dbRow in $dbFiles.Rows) {
            $filename = $dbRow[$FilenameColumn]
            $keyValue = $dbRow[$KeyColumn]
        
            # Find matching files (case-insensitive)
            $matchingFiles = $networkFiles | Where-Object { $_.Name -ieq $filename }
        
            if ($matchingFiles.Count -eq 0) {
                Write-Host "  No match found for: $filename" -ForegroundColor DarkYellow
            }
            elseif ($matchingFiles.Count -eq 1) {
                # Check if we've already processed this file
                $fullPath = $matchingFiles[0].FullName
                if ($processedFiles.ContainsKey($fullPath.ToLower())) {
                    Write-Host "  Duplicate database reference for file: $filename" -ForegroundColor Red
                    $duplicates += @{
                        Filename = $filename
                        KeyValue = $keyValue
                        FilePath = $fullPath
                        Reason   = "Multiple database records reference the same file"
                    }
                }
                else {
                    $matches += @{
                        Filename = $filename
                        KeyValue = $keyValue
                        FilePath = $fullPath
                    }
                    $processedFiles[$fullPath.ToLower()] = $true
                }
            }
            else {
                Write-Host "  Multiple files found for: $filename" -ForegroundColor Red
                $duplicates += @{
                    Filename  = $filename
                    KeyValue  = $keyValue
                    FilePaths = $matchingFiles.FullName
                    Reason    = "Multiple files found with same name"
                }
            }
        }
    
        Write-Host "Found $($matches.Count) unique matches to process" -ForegroundColor Yellow
    
        # Step 4: Report duplicates
        if ($duplicates.Count -gt 0) {
            Write-Host ""
            Write-Host "DUPLICATE FILES DETECTED - These will NOT be processed:" -ForegroundColor Red
            foreach ($duplicate in $duplicates) {
                Write-Host "  - Filename: $($duplicate.Filename)" -ForegroundColor Red
                Write-Host "    Key: $($duplicate.KeyValue)" -ForegroundColor Red
                Write-Host "    Reason: $($duplicate.Reason)" -ForegroundColor Red
                if ($duplicate.FilePaths) {
                    Write-Host "    Paths:" -ForegroundColor Red
                    foreach ($path in $duplicate.FilePaths) {
                        Write-Host "      $path" -ForegroundColor Red
                    }
                }
                Write-Host ""
            }
        }
    
        if ($matches.Count -eq 0) {
            Write-Host "No files to process. Exiting." -ForegroundColor Yellow
            return
        }

        # Step 5 & 6: Process matches - Get MIME type, convert to bytes, and update database
        Write-Host "Step 4: Processing matched files and updating database..." -ForegroundColor Cyan
    
        $processed = 0
        $errors = 0
    
        foreach ($match in $matches) {
            $processed++
            $percentComplete = [math]::Round(($processed / $matches.Count) * 100, 1)
        
            try {
                Write-Host "  [$processed/$($matches.Count)] ($percentComplete%) Processing: $($match.Filename)" -ForegroundColor Gray
            
                # Get MIME type
                $mimeType = Get-MimeType -FilePath $match.FilePath
            
                # Read file as byte array
                $fileBytes = [System.IO.File]::ReadAllBytes($match.FilePath)
                $fileSizeKB = [math]::Round($fileBytes.Length / 1024, 2)
            
                Write-Host "    MIME Type: $mimeType, Size: $fileSizeKB KB" -ForegroundColor DarkGray
            
                # Update database
                $updateQuery = @"
UPDATE [$TableName] 
SET [$MimeTypeColumn] = @MimeType, 
    [$ByteDataColumn] = @ByteData 
WHERE [$KeyColumn] = @KeyValue
"@
            
                $parameters = @{
                    '@MimeType' = $mimeType
                    '@ByteData' = $fileBytes
                    '@KeyValue' = $match.KeyValue
                }
            
                $rowsAffected = Invoke-SqlQuery -Connection $sqlConnection -Query $updateQuery -Timeout $CommandTimeout -Parameters $parameters
            
                if ($rowsAffected -eq 1) {
                    Write-Host "    ✓ Database updated successfully" -ForegroundColor DarkGreen
                }
                else {
                    Write-Host "    ⚠ Warning: $rowsAffected rows affected (expected 1)" -ForegroundColor DarkYellow
                }
            }
            catch {
                $errors++
                Write-Host "    ✗ Error processing $($match.Filename): $_" -ForegroundColor Red
            }
        
            # Small delay to prevent overwhelming the system
            Start-Sleep -Milliseconds 100
        }
    
        # Final summary
        Write-Host ""
        Write-Host "Processing completed!" -ForegroundColor Green
        Write-Host "Successfully processed: $($processed - $errors) files" -ForegroundColor Green
        Write-Host "Errors encountered: $errors files" -ForegroundColor $(if ($errors -gt 0) { "Red" } else { "Green" })
        Write-Host "Duplicates skipped: $($duplicates.Count) files" -ForegroundColor Yellow
        Write-Host "Total database records: $($dbFiles.Rows.Count)" -ForegroundColor Gray
    }
    catch {
        Write-Host ""
        Write-Host "Script failed with error: $_" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    }
    finally {
        # Clean up SQL connection
        if ($sqlConnection -and $sqlConnection.State -eq 'Open') {
            $sqlConnection.Close()
            Write-Host "Database connection closed." -ForegroundColor Gray
        }
    }
}
# Example usage:
<#
.\ProcessFiles.ps1 -SqlServer "SERVER01" -Database "MyDatabase" -TableName "Documents" -FilenameColumn "FileName" -MimeTypeColumn "MimeType" -ByteDataColumn "FileData" -NetworkPath "\\fileserver\share\documents" -KeyColumn "DocumentId"
#>