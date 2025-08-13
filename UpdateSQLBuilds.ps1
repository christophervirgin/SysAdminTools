# Function to fetch latest SQL Server builds dynamically
function Get-LatestSQLBuilds {
    [CmdletBinding()]
    param(
        [switch]$UseCache,
        [string]$CachePath = "\\FileServer\SQLInventory\Cache\SQLBuilds.json",
        [int]$CacheHours = 24
    )
    
    Write-Log "Fetching latest SQL Server build information..." "Info"
    
    # Check cache first if requested
    if ($UseCache -and (Test-Path $CachePath)) {
        $cacheFile = Get-Item $CachePath
        $cacheAge = (Get-Date) - $cacheFile.LastWriteTime
        
        if ($cacheAge.TotalHours -lt $CacheHours) {
            Write-Log "Using cached build information (Age: $([math]::Round($cacheAge.TotalHours, 2)) hours)" "Info"
            $cachedData = Get-Content $CachePath -Raw | ConvertFrom-Json
            return Convert-JsonToHashtable $cachedData
        }
    }
    
    $latestBuilds = @{}
    
    # Method 1: Fetch from sqlserverbuilds.blogspot.com RSS feed
    try {
        Write-Log "Attempting to fetch from sqlserverbuilds RSS feed..." "Info"
        $latestBuilds = Get-SQLBuildsFromRSS
        
        if ($latestBuilds.Count -gt 0) {
            Write-Log "Successfully retrieved build information from RSS feed" "Success"
            Save-BuildCache -Builds $latestBuilds -Path $CachePath
            return $latestBuilds
        }
    }
    catch {
        Write-Log "Failed to fetch from RSS: $_" "Warning"
    }
    
    # Method 2: Fetch from GitHub repository (community maintained)
    try {
        Write-Log "Attempting to fetch from GitHub repository..." "Info"
        $latestBuilds = Get-SQLBuildsFromGitHub
        
        if ($latestBuilds.Count -gt 0) {
            Write-Log "Successfully retrieved build information from GitHub" "Success"
            Save-BuildCache -Builds $latestBuilds -Path $CachePath
            return $latestBuilds
        }
    }
    catch {
        Write-Log "Failed to fetch from GitHub: $_" "Warning"
    }
    
    # Method 3: Query Microsoft Update Catalog
    try {
        Write-Log "Attempting to fetch from Microsoft Update Catalog..." "Info"
        $latestBuilds = Get-SQLBuildsFromMicrosoftCatalog
        
        if ($latestBuilds.Count -gt 0) {
            Write-Log "Successfully retrieved build information from Microsoft Catalog" "Success"
            Save-BuildCache -Builds $latestBuilds -Path $CachePath
            return $latestBuilds
        }
    }
    catch {
        Write-Log "Failed to fetch from Microsoft Catalog: $_" "Warning"
    }
    
    # Fallback to cached data even if expired
    if (Test-Path $CachePath) {
        Write-Log "Using expired cache as fallback" "Warning"
        $cachedData = Get-Content $CachePath -Raw | ConvertFrom-Json
        return Convert-JsonToHashtable $cachedData
    }
    
    # Last resort: Return hardcoded defaults
    Write-Log "Using hardcoded build information as last resort" "Warning"
    return Get-HardcodedBuilds
}

# Function to fetch from sqlserverbuilds.blogspot.com RSS
function Get-SQLBuildsFromRSS {
    $builds = @{}
    $rssUrl = "https://sqlserverbuilds.blogspot.com/feeds/posts/default?alt=rss"
    
    # Fetch RSS feed
    $response = Invoke-WebRequest -Uri $rssUrl -UseBasicParsing -TimeoutSec 10
    [xml]$rss = $response.Content
    
    # Parse latest CU information from recent posts
    foreach ($item in $rss.rss.channel.item | Select-Object -First 20) {
        if ($item.title -match "SQL Server (\d{4}).*Cumulative Update (\d+)") {
            $version = $Matches[1]
            $cuNumber = $Matches[2]
            
            # Extract build number from content
            if ($item.description -match "Build (\d+\.\d+\.\d+\.\d+)") {
                $buildNumber = $Matches[1]
                
                if (-not $builds.ContainsKey($version)) {
                    $builds[$version] = @{
                        Build = $buildNumber
                        CU = "CU$cuNumber"
                        ReleaseDate = [datetime]::Parse($item.pubDate).ToString("yyyy-MM-dd")
                    }
                }
            }
        }
    }
    
    # Add support lifecycle information
    $supportDates = Get-SQLServerSupportDates
    foreach ($version in $builds.Keys) {
        if ($supportDates.ContainsKey($version)) {
            $builds[$version]["SupportEnd"] = $supportDates[$version].MainstreamEnd
            $builds[$version]["ExtendedEnd"] = $supportDates[$version].ExtendedEnd
        }
    }
    
    return $builds
}

# Function to fetch from GitHub (community maintained repository)
function Get-SQLBuildsFromGitHub {
    $builds = @{}
    
    # Using a well-maintained GitHub repository for SQL Server builds
    $githubUrl = "https://raw.githubusercontent.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/main/SqlServerBuilds.json"
    
    try {
        $response = Invoke-RestMethod -Uri $githubUrl -TimeoutSec 10
        
        foreach ($version in $response.PSObject.Properties) {
            $versionKey = $version.Name -replace "SQL Server ", ""
            
            $latestCU = $version.Value.Updates | 
                Where-Object { $_.Type -eq "CU" -or $_.Type -eq "SP" } | 
                Sort-Object ReleaseDate -Descending | 
                Select-Object -First 1
            
            if ($latestCU) {
                $builds[$versionKey] = @{
                    Build = $latestCU.Build
                    CU = $latestCU.Name
                    ReleaseDate = $latestCU.ReleaseDate
                    SupportEnd = $version.Value.MainstreamEnd
                    ExtendedEnd = $version.Value.ExtendedEnd
                }
            }
        }
    }
    catch {
        # Alternative GitHub source
        $altUrl = "https://api.github.com/repos/sqlserverbuilds/sqlserverbuilds/contents/builds.json"
        $response = Invoke-RestMethod -Uri $altUrl -TimeoutSec 10
        $content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($response.content))
        $buildsData = $content | ConvertFrom-Json
        
        # Parse the alternative format
        foreach ($item in $buildsData) {
            if (-not $builds.ContainsKey($item.Version)) {
                $builds[$item.Version] = @{
                    Build = $item.LatestBuild
                    CU = $item.LatestCU
                    ReleaseDate = $item.ReleaseDate
                    SupportEnd = $item.MainstreamEnd
                    ExtendedEnd = $item.ExtendedEnd
                }
            }
        }
    }
    
    return $builds
}

# Function to query Microsoft Update Catalog
function Get-SQLBuildsFromMicrosoftCatalog {
    $builds = @{}
    $versions = @("2012", "2014", "2016", "2017", "2019", "2022")
    
    foreach ($version in $versions) {
        try {
            $searchUrl = "https://www.catalog.update.microsoft.com/Search.aspx?q=SQL+Server+$version+Cumulative+Update"
            
            # Create web session
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $response = Invoke-WebRequest -Uri $searchUrl -SessionVariable session -UseBasicParsing -TimeoutSec 15
            
            # Parse the HTML to find latest CU
            if ($response.Content -match "Cumulative Update (\d+).*SQL Server $version.*\(KB\d+\)") {
                $cuNumber = $Matches[1]
                
                # Extract build number from KB article or description
                if ($response.Content -match "$version.*Build (\d+\.\d+\.\d+\.\d+)") {
                    $buildNumber = $Matches[1]
                    
                    # Get release date from the page
                    $releaseDate = Get-Date -Format "yyyy-MM-dd"
                    if ($response.Content -match "(\d{1,2}/\d{1,2}/\d{4})") {
                        $releaseDate = [datetime]::Parse($Matches[1]).ToString("yyyy-MM-dd")
                    }
                    
                    $builds[$version] = @{
                        Build = $buildNumber
                        CU = "CU$cuNumber"
                        ReleaseDate = $releaseDate
                    }
                }
            }
        }
        catch {
            Write-Verbose "Failed to get info for SQL $version from Microsoft Catalog"
        }
    }
    
    # Add support dates
    $supportDates = Get-SQLServerSupportDates
    foreach ($version in $builds.Keys) {
        if ($supportDates.ContainsKey($version)) {
            $builds[$version]["SupportEnd"] = $supportDates[$version].MainstreamEnd
            $builds[$version]["ExtendedEnd"] = $supportDates[$version].ExtendedEnd
        }
    }
    
    return $builds
}

# Function to get SQL Server support lifecycle dates
function Get-SQLServerSupportDates {
    return @{
        "2012" = @{
            MainstreamEnd = "2022-07-12"
            ExtendedEnd = "2027-07-12"
        }
        "2014" = @{
            MainstreamEnd = "2024-07-09"
            ExtendedEnd = "2029-07-09"
        }
        "2016" = @{
            MainstreamEnd = "2026-07-14"
            ExtendedEnd = "2031-07-14"
        }
        "2017" = @{
            MainstreamEnd = "2027-10-12"
            ExtendedEnd = "2032-10-12"
        }
        "2019" = @{
            MainstreamEnd = "2030-01-08"
            ExtendedEnd = "2035-01-08"
        }
        "2022" = @{
            MainstreamEnd = "2033-11-11"
            ExtendedEnd = "2038-11-11"
        }
    }
}

# Function to save build cache
function Save-BuildCache {
    param($Builds, $Path)
    
    $cacheDir = Split-Path $Path -Parent
    if (!(Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    
    $Builds | ConvertTo-Json -Depth 3 | Out-File -FilePath $Path -Force
}

# Function to convert JSON to hashtable
function Convert-JsonToHashtable {
    param($JsonObject)
    
    $hashtable = @{}
    foreach ($property in $JsonObject.PSObject.Properties) {
        if ($property.Value -is [PSCustomObject]) {
            $hashtable[$property.Name] = Convert-JsonToHashtable $property.Value
        }
        else {
            $hashtable[$property.Name] = $property.Value
        }
    }
    return $hashtable
}

# Fallback hardcoded builds (used only if all dynamic methods fail)
function Get-HardcodedBuilds {
    return @{
        "2012" = @{
            Build = "11.0.7507.2"
            CU = "SP4 + Latest CU"
            ReleaseDate = "2022-10-11"
            SupportEnd = "2022-07-12"
            ExtendedEnd = "2027-07-12"
        }
        "2014" = @{
            Build = "12.0.6449.1"
            CU = "SP3 + CU4"
            ReleaseDate = "2023-11-14"
            SupportEnd = "2024-07-09"
            ExtendedEnd = "2029-07-09"
        }
        "2016" = @{
            Build = "13.0.7037.1"
            CU = "SP3 + Latest"
            ReleaseDate = "2024-11-14"
            SupportEnd = "2026-07-14"
            ExtendedEnd = "2031-07-14"
        }
        "2017" = @{
            Build = "14.0.3471.2"
            CU = "CU31 + Latest"
            ReleaseDate = "2024-11-14"
            SupportEnd = "2027-10-12"
            ExtendedEnd = "2032-10-12"
        }
        "2019" = @{
            Build = "15.0.4395.2"
            CU = "CU28"
            ReleaseDate = "2024-11-14"
            SupportEnd = "2030-01-08"
            ExtendedEnd = "2035-01-08"
        }
        "2022" = @{
            Build = "16.0.4155.4"
            CU = "CU15"
            ReleaseDate = "2024-11-14"
            SupportEnd = "2033-11-11"
            ExtendedEnd = "2038-11-11"
        }
    }
}

# Alternative: Direct API call to Microsoft (if available in your environment)
function Get-SQLBuildsFromMicrosoftAPI {
    $builds = @{}
    
    # Microsoft RSS feed for SQL Server updates
    $rssFeedUrls = @{
        "2022" = "https://techcommunity.microsoft.com/gxcuf89792/rss/board?board.id=SQLServer2022"
        "2019" = "https://techcommunity.microsoft.com/gxcuf89792/rss/board?board.id=SQLServer2019"
        "2017" = "https://techcommunity.microsoft.com/gxcuf89792/rss/board?board.id=SQLServer2017"
    }
    
    foreach ($version in $rssFeedUrls.Keys) {
        try {
            [xml]$rss = Invoke-WebRequest -Uri $rssFeedUrls[$version] -UseBasicParsing -TimeoutSec 10
            
            foreach ($item in $rss.rss.channel.item) {
                if ($item.title -match "Cumulative Update (\d+)") {
                    $cuNumber = $Matches[1]
                    
                    if ($item.description -match "(\d+\.\d+\.\d+\.\d+)") {
                        $buildNumber = $Matches[1]
                        
                        $builds[$version] = @{
                            Build = $buildNumber
                            CU = "CU$cuNumber"
                            ReleaseDate = [datetime]::Parse($item.pubDate).ToString("yyyy-MM-dd")
                        }
                        break
                    }
                }
            }
        }
        catch {
            Write-Verbose "Failed to fetch RSS for SQL $version"
        }
    }
    
    return $builds
}
