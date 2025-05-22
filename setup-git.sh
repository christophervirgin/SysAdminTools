#!/bin/bash

# Initialize Git Repository for SysAdminTools
echo "Initializing Git repository for SysAdminTools..."

# Navigate to the project directory
cd "$(dirname "$0")"

# Initialize git repository if not already initialized
if [ ! -d ".git" ] || [ ! -f ".git/HEAD" ]; then
    echo "Initializing git repository..."
    git init
    
    # Set initial branch to main
    git checkout -b main 2>/dev/null || git branch -M main
    
    # Add all files
    git add .
    
    # Initial commit
    git commit -m "Initial commit: SysAdminTools PowerShell module

Features:
- Copy-DbaUserTables: Copy schema and data for all user tables between SQL Server databases
- Test-TableDataIntegrity: Verify data integrity by comparing row counts
- Get-CopyProgress: Monitor table copy operation progress
- Test-AllTablesIntegrity: Comprehensive integrity checking for all tables

Module structure follows PowerShell best practices with proper manifest, module file, and individual function files."
    
    echo "Git repository initialized successfully!"
    echo ""
    echo "To add a remote repository:"
    echo "  git remote add origin https://github.com/username/SysAdminTools.git"
    echo "  git push -u origin main"
else
    echo "Git repository already initialized."
fi

echo ""
echo "Repository status:"
git status
