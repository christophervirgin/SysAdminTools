# SysAdminTools PowerShell Module

A comprehensive PowerShell module containing system administration tools and utilities for database management, server operations, and infrastructure automation.

## Features

- **Database Management**: Tools for SQL Server database operations including table copying, data migration, and integrity checking
- **dbatools Integration**: Leverages the powerful dbatools module for database operations
- **Comprehensive Logging**: Detailed logging with color-coded output for easy monitoring
- **Force Overwrite**: Safely handle existing table conflicts during migrations
- **Data Integrity Validation**: Built-in tools to verify data integrity after operations

## Installation

### Prerequisites

- PowerShell 5.1 or later (PowerShell Core 6+ supported)
- [dbatools module](https://dbatools.io/)

```powershell
# Install dbatools if not already installed
Install-Module -Name dbatools -Scope CurrentUser
```

### Installing SysAdminTools

1. Clone this repository:
```bash
git clone https://github.com/username/SysAdminTools.git
cd SysAdminTools
```

2. Import the module:
```powershell
Import-Module .\SysAdminTools.psd1
```

3. Or install for current user:
```powershell
# Copy to PowerShell module path
$ModulePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\SysAdminTools"
Copy-Item -Path . -Destination $ModulePath -Recurse
Import-Module SysAdminTools
```

## Functions

### Copy-DbaUserTables

Copy schema and data for all user tables from one SQL Server database to another.

**Features:**
- Two copy methods: Comprehensive (default) and Granular
- Force overwrite existing tables
- Configurable batch sizes
- Include/exclude indexes and constraints
- Comprehensive error handling and progress logging

**Examples:**

```powershell
# Basic table copy
Copy-DbaUserTables -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB"

# Granular copy with all options
Copy-DbaUserTables -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB" -Method Granular -ForceOverwrite -IncludeIndexes -IncludeConstraints -BatchSize 25000

# Force overwrite existing tables
Copy-DbaUserTables -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB" -ForceOverwrite
```

### Test-TableDataIntegrity

Test data integrity between source and destination tables by comparing row counts.

```powershell
# Test a specific table
$result = Test-TableDataIntegrity -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB" -TableSchema "dbo" -TableName "Users"

if ($result.Match) {
    Write-Host "Data integrity verified for $($result.TableName)"
} else {
    Write-Warning "Data mismatch: Source=$($result.SourceRows), Dest=$($result.DestinationRows)"
}
```

### Get-CopyProgress

Monitor the progress of a database table copy operation.

```powershell
$progress = Get-CopyProgress -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB"

Write-Host "Copy Progress: $($progress.PercentComplete)% ($($progress.DestinationTableCount)/$($progress.SourceTableCount) tables)"

if ($progress.MissingTables.Count -gt 0) {
    Write-Host "Missing tables:"
    $progress.MissingTables | ForEach-Object { Write-Host "  - $_" }
}
```

### Test-AllTablesIntegrity

Perform comprehensive data integrity checking for all tables.

```powershell
# Run integrity check with progress display
$results = Test-AllTablesIntegrity -SourceInstance "SQLPROD01" -DestinationInstance "SQLDEV01" -SourceDatabase "ProductionDB" -DestinationDatabase "DevDB" -ShowProgress

# Check for failed tables
$failedTables = $results | Where-Object { -not $_.Match }
if ($failedTables.Count -gt 0) {
    Write-Warning "Found $($failedTables.Count) tables with integrity issues"
}
```

## Module Architecture

The module follows PowerShell best practices with a clean structure:

```
SysAdminTools/
├── SysAdminTools.psd1          # Module manifest
├── SysAdminTools.psm1          # Main module file
├── Functions/                  # Individual function files
│   ├── Copy-DbaUserTables.ps1
│   ├── Test-TableDataIntegrity.ps1
│   ├── Get-CopyProgress.ps1
│   └── Test-AllTablesIntegrity.ps1
├── README.md
└── LICENSE
```

## Domain-Driven Design Approach

This module is designed using domain modeling principles:

1. **Core Domain**: Database management and migration operations
2. **Supporting Domains**: Logging, validation, and progress monitoring
3. **Abstraction Layers**: 
   - Presentation Layer (PowerShell cmdlets)
   - Application Layer (coordination and orchestration)
   - Domain Layer (business logic for database operations)
   - Infrastructure Layer (dbatools integration)

## Error Handling

The module includes comprehensive error handling:
- Validation of prerequisites (dbatools module)
- Connection verification before operations
- Graceful handling of individual table failures
- Detailed error messages with context
- Color-coded logging for easy issue identification

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or contributions, please:
1. Check existing issues in the GitHub repository
2. Create a new issue with detailed information
3. Include PowerShell version, dbatools version, and error messages

## Acknowledgments

- [dbatools community](https://dbatools.io/) for the excellent PowerShell module
- PowerShell community for best practices and standards
- System administrators worldwide who inspire better automation tools
