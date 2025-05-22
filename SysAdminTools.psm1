#
# SysAdminTools PowerShell Module
# Main module file that loads all functions
#

# Get the path to this module
$ModulePath = $PSScriptRoot

# Import all function files from the Functions directory
$FunctionPath = Join-Path -Path $ModulePath -ChildPath 'Functions'

if (Test-Path -Path $FunctionPath) {
    $FunctionFiles = Get-ChildItem -Path $FunctionPath -Filter '*.ps1' -Recurse
    
    foreach ($FunctionFile in $FunctionFiles) {
        try {
            Write-Verbose "Importing function: $($FunctionFile.BaseName)"
            . $FunctionFile.FullName
        }
        catch {
            Write-Error "Failed to import function $($FunctionFile.BaseName): $($_.Exception.Message)"
        }
    }
    
    Write-Verbose "Imported $($FunctionFiles.Count) function(s) from SysAdminTools module"
}
else {
    Write-Warning "Functions directory not found at: $FunctionPath"
}

# Module initialization
Write-Verbose "SysAdminTools module loaded successfully"

# Export module members (functions will be auto-detected from the Functions directory)
# Additional module-level exports can be defined here if needed
