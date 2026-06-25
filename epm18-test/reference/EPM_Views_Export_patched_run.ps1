#Requires -Version 5.1
<#
.SYNOPSIS
    EPM Views Data Export - Fetches EPM Views and exports to CSV and Excel
    
.DESCRIPTION
    This script connects to Oracle EPM Cloud REST API, retrieves views data,
    and exports it to both CSV and Excel formats with comprehensive logging.
    
    Uses encrypted credentials from: C:\Russ\Creds\rs.epm_credentials.xml

.NOTES
    Author: Generated for EPM Cloud Integration
    Version: 3.0
    Credentials: Reads from encrypted XML file (UserName and Password keys)
    
.EXAMPLE
    .\EPM_Views_Export.ps1
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$BaseUrl = "https://epm20-test-a706571.epm.us2.oraclecloud.com",
    
    [Parameter(Mandatory=$false)]
    [string]$CredentialPath = "C:\Russ\Creds\rs.epm_credentials.xml",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = "C:\EDM",
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\EDM"
)

#region ==================== LOGGING SETUP ====================

# Create directories if they don't exist
@($OutputDirectory, $LogPath) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

# Generate log file name with timestamp
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile = Join-Path $LogPath "EPM_Views_Export_$Timestamp.log"

# Logging function - writes to both console and file
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level = 'INFO',
        
        [Parameter(Mandatory=$false)]
        [switch]$NoConsole
    )
    
    $LogTimestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $LogEntry = "[$LogTimestamp] [$Level] $Message"
    
    # Write to log file
    try {
        Add-Content -Path $LogFile -Value $LogEntry -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to write to log file: $_"
    }
    
    # Write to console with color coding
    if (-not $NoConsole) {
        $Color = switch ($Level) {
            'INFO'    { 'White' }
            'WARNING' { 'Yellow' }
            'ERROR'   { 'Red' }
            'SUCCESS' { 'Green' }
            'DEBUG'   { 'Cyan' }
            default   { 'White' }
        }
        Write-Host $LogEntry -ForegroundColor $Color
    }
}

function Write-LogSection {
    param([string]$Title)
    $Separator = "=" * 80
    Write-Log " "
    Write-Log $Separator
    Write-Log $Title
    Write-Log $Separator
}

function Write-LogError {
    param(
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )
    Write-Log $Message -Level 'ERROR'
    if ($ErrorRecord) {
        Write-Log "Exception Type: $($ErrorRecord.Exception.GetType().FullName)" -Level 'ERROR'
        Write-Log "Exception Message: $($ErrorRecord.Exception.Message)" -Level 'ERROR'
        if ($ErrorRecord.Exception.Response) {
            $StatusCode = $ErrorRecord.Exception.Response.StatusCode.value__
            Write-Log "HTTP Status Code: $StatusCode" -Level 'ERROR'
        }
        Write-Log "Stack Trace: $($ErrorRecord.ScriptStackTrace)" -Level 'DEBUG'
    }
}

#endregion

#region ==================== AUTHENTICATION ====================

function Get-EPMCredentialFromFile {
    param([string]$Path)
    
    Write-LogSection "AUTHENTICATION"
    Write-Log "Loading encrypted credentials from file..." -Level 'INFO'
    Write-Log "Credential file path: $Path" -Level 'DEBUG'
    
    if (-not (Test-Path $Path)) {
        Write-Log "Credential file not found at: $Path" -Level 'ERROR'
        throw "Credential file not found: $Path"
    }
    
    try {
        Write-Log "Reading encrypted credential file..." -Level 'DEBUG'
        $CredentialData = Import-Clixml -Path $Path -ErrorAction Stop
        
        Write-Log "Credential file loaded successfully" -Level 'SUCCESS'
        Write-Log "Credential file type: $($CredentialData.GetType().Name)" -Level 'DEBUG'
        
        # Check for required keys
        if (-not $CredentialData.UserName) {
            Write-Log "UserName key not found in credential file" -Level 'ERROR'
            throw "Credential file is missing 'UserName' key"
        }
        
        if (-not $CredentialData.Password) {
            Write-Log "Password key not found in credential file" -Level 'ERROR'
            throw "Credential file is missing 'Password' key"
        }
        
        Write-Log "Username found: $($CredentialData.UserName)" -Level 'INFO'
        Write-Log "Password found: [ENCRYPTED - $(($CredentialData.Password).Length) characters]" -Level 'DEBUG'
        
        # Convert encrypted password to SecureString
        Write-Log "Decrypting password..." -Level 'DEBUG'
        $SecurePassword = $CredentialData.Password | ConvertTo-SecureString -ErrorAction Stop
        
        # Create PSCredential object
        $Credential = New-Object System.Management.Automation.PSCredential($CredentialData.UserName, $SecurePassword)
        
        Write-Log "Credentials decrypted and loaded successfully" -Level 'SUCCESS'
        Write-Log "Authenticated as: $($Credential.UserName)" -Level 'INFO'
        
        return $Credential
    }
    catch {
        Write-LogError "Failed to load or decrypt credentials" $_
        Write-Log " " -Level 'INFO'
        Write-Log "Possible causes:" -Level 'WARNING'
        Write-Log "  1. Credential file was created by a different user" -Level 'WARNING'
        Write-Log "  2. Credential file was created on a different machine" -Level 'WARNING'
        Write-Log "  3. Credential file is corrupted" -Level 'WARNING'
        Write-Log "  4. Credential file format is incorrect (expecting UserName and Password keys)" -Level 'WARNING'
        throw
    }
}

function Get-BasicAuthHeader {
    param([System.Management.Automation.PSCredential]$Credential)
    
    Write-Log "Creating Basic Authentication header..." -Level 'DEBUG'
    
    $Username = $Credential.UserName
    $Password = $Credential.GetNetworkCredential().Password
    
    Write-Log "Username for auth: $Username" -Level 'DEBUG'
    Write-Log "Password length: $($Password.Length) characters" -Level 'DEBUG'
    
    $AuthString = "${Username}:${Password}"
    $AuthBytes = [System.Text.Encoding]::UTF8.GetBytes($AuthString)
    $AuthBase64 = [Convert]::ToBase64String($AuthBytes)
    
    Write-Log "Basic Auth header created successfully" -Level 'SUCCESS'
    
    # Clear password from memory
    $Password = $null
    [System.GC]::Collect()
    
    return @{
        "Authorization" = "Basic $AuthBase64"
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
    }
}

#endregion

#region ==================== API FUNCTIONS ====================

function Invoke-EPMApiRequest {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Url,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Headers
    )
    
    Write-LogSection "API REQUEST"
    Write-Log "Preparing GET request..." -Level 'INFO'
    Write-Log "URL: $Url" -Level 'INFO'
    Write-Log "Method: GET" -Level 'DEBUG'
    Write-Log "Headers: Authorization=[REDACTED], Content-Type=$($Headers['Content-Type']), Accept=$($Headers['Accept'])" -Level 'DEBUG'
    
    $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        Write-Log "Sending HTTP request to EPM Cloud..." -Level 'INFO'
        
        $Response = Invoke-RestMethod -Uri $Url -Method GET -Headers $Headers -ErrorAction Stop
        
        $StopWatch.Stop()
        
        Write-Log "API request completed successfully" -Level 'SUCCESS'
        Write-Log "Response time: $($StopWatch.ElapsedMilliseconds)ms" -Level 'INFO'
        Write-Log "Response type: $($Response.GetType().Name)" -Level 'DEBUG'
        
        # Log response structure
        if ($Response) {
            $ResponseJson = $Response | ConvertTo-Json -Depth 2 -Compress
            $ResponsePreview = if ($ResponseJson.Length -gt 500) { 
                $ResponseJson.Substring(0, 500) + "... [truncated]" 
            } else { 
                $ResponseJson 
            }
            Write-Log "Response preview: $ResponsePreview" -Level 'DEBUG'
        }
        
        return $Response
    }
    catch {
        $StopWatch.Stop()
        
        Write-Log "API request failed after $($StopWatch.ElapsedMilliseconds)ms" -Level 'ERROR'
        
        if ($_.Exception.Response) {
            $StatusCode = $_.Exception.Response.StatusCode.value__
            $StatusDescription = $_.Exception.Response.StatusDescription
            Write-Log "HTTP Status: $StatusCode - $StatusDescription" -Level 'ERROR'
            
            # Try to read error response body
            try {
                $Reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $ResponseBody = $Reader.ReadToEnd()
                $Reader.Close()
                Write-Log "Error response body: $ResponseBody" -Level 'ERROR'
            }
            catch {
                Write-Log "Could not read error response body" -Level 'DEBUG'
            }
        }
        
        Write-LogError "Request failed" $_
        throw
    }
}

#endregion

#region ==================== DATA PROCESSING ====================

function Convert-ViewsToFlatObjects {
    param (
        [Parameter(Mandatory=$true)]
        [array]$ViewItems
    )
    
    Write-LogSection "DATA PROCESSING"
    Write-Log "Flattening nested JSON structure..." -Level 'INFO'
    Write-Log "Number of views to process: $($ViewItems.Count)" -Level 'INFO'
    
    $FlattenedData = @()
    $ProcessedCount = 0
    
    foreach ($View in $ViewItems) {
        $ProcessedCount++
        
        if ($ProcessedCount % 10 -eq 0) {
            Write-Log "Processed $ProcessedCount of $($ViewItems.Count) views..." -Level 'DEBUG'
        }
        
        # Create a flattened object with relevant properties
        $FlatObject = [PSCustomObject]@{
            # Core View Properties
            "View_ID"                    = $View.id
            "View_Name"                  = $View.name
            "Description"                = $View.description
            "Object_Status"              = $View.objectStatus
            "Is_Master"                  = $View.master
            
            # Timestamps
            "Time_Created"               = $View.timeCreated
            "Time_Modified"              = $View.timeModified
            
            # Creator Information
            "Created_By"                 = $View.createdBy
            "Created_By_UserName"        = if ($View.createdByUser) { $View.createdByUser.userName } else { $null }
            "Created_By_FullName"        = if ($View.createdByUser) { $View.createdByUser.fullName } else { $null }
            "Created_By_FirstName"       = if ($View.createdByUser) { $View.createdByUser.firstName } else { $null }
            "Created_By_LastName"        = if ($View.createdByUser) { $View.createdByUser.lastName } else { $null }
            "Created_By_IsAdmin"         = if ($View.createdByUser) { $View.createdByUser.userServiceAdministrator } else { $null }
            
            # Modifier Information
            "Modified_By"                = $View.modifiedBy
            "Modified_By_UserName"       = if ($View.modifiedByUser) { $View.modifiedByUser.userName } else { $null }
            "Modified_By_FullName"       = if ($View.modifiedByUser) { $View.modifiedByUser.fullName } else { $null }
            "Modified_By_FirstName"      = if ($View.modifiedByUser) { $View.modifiedByUser.firstName } else { $null }
            "Modified_By_LastName"       = if ($View.modifiedByUser) { $View.modifiedByUser.lastName } else { $null }
            "Modified_By_IsAdmin"        = if ($View.modifiedByUser) { $View.modifiedByUser.userServiceAdministrator } else { $null }
            
            # Request Settings
            "Request_Description"        = $View.requestDescription
            "Request_Placeholder"        = $View.requestPlaceholder
            "Attach_Request_File"        = $View.attachRequestFile
            
            # Filter Settings
            "Users_Browse_Filter_Type"   = if ($View.usersBrowseFilter) { $View.usersBrowseFilter.filterType } else { $null }
            
            # Permitted Actions (joined as comma-separated string)
            "Permitted_Actions"          = if ($View.permittedActions) { $View.permittedActions -join ", " } else { $null }
            
            # Self Link (for reference)
            "Self_Link"                  = ($View.links | Where-Object { $_.rel -eq "self" } | Select-Object -First 1).href
        }
        
        $FlattenedData += $FlatObject
    }
    
    Write-Log "Data flattening complete" -Level 'SUCCESS'
    Write-Log "Total records processed: $ProcessedCount" -Level 'INFO'
    
    return $FlattenedData
}

#endregion

#region ==================== EXPORT FUNCTIONS ====================

function Export-ToCsv {
    param (
        [Parameter(Mandatory=$true)]
        [array]$Data,
        
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    Write-LogSection "CSV EXPORT"
    Write-Log "Exporting data to CSV..." -Level 'INFO'
    Write-Log "Output file: $FilePath" -Level 'INFO'
    Write-Log "Records to export: $($Data.Count)" -Level 'INFO'
    
    try {
        $Data | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8 -Force -ErrorAction Stop
        
        if (Test-Path $FilePath) {
            $FileInfo = Get-Item $FilePath
            Write-Log "CSV export successful!" -Level 'SUCCESS'
            Write-Log "File size: $($FileInfo.Length) bytes ($([math]::Round($FileInfo.Length/1KB, 2)) KB)" -Level 'INFO'
            Write-Log "File location: $($FileInfo.FullName)" -Level 'INFO'
            return $true
        }
        else {
            Write-Log "CSV export completed but file not found" -Level 'ERROR'
            return $false
        }
    }
    catch {
        Write-LogError "CSV export failed" $_
        return $false
    }
}

function Export-ToExcel {
    param (
        [Parameter(Mandatory=$true)]
        [array]$Data,
        
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    Write-LogSection "EXCEL EXPORT"
    Write-Log "Preparing Excel export..." -Level 'INFO'
    Write-Log "Output file: $FilePath" -Level 'INFO'
    Write-Log "Records to export: $($Data.Count)" -Level 'INFO'
    
    # Check if ImportExcel module is installed
    Write-Log "Checking for ImportExcel module..." -Level 'DEBUG'
    
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Log "ImportExcel module not found" -Level 'WARNING'
        Write-Log "Attempting to install ImportExcel module..." -Level 'INFO'
        
        try {
            Install-Module -Name ImportExcel -Force -Scope CurrentUser -ErrorAction Stop
            Write-Log "ImportExcel module installed successfully" -Level 'SUCCESS'
        }
        catch {
            Write-LogError "Failed to install ImportExcel module" $_
            Write-Log "Excel export will be skipped" -Level 'WARNING'
            Write-Log "To install manually, run: Install-Module -Name ImportExcel -Scope CurrentUser" -Level 'INFO'
            return $false
        }
    }
    else {
        Write-Log "ImportExcel module is already installed" -Level 'DEBUG'
    }
    
    try {
        Write-Log "Importing ImportExcel module..." -Level 'DEBUG'
        Import-Module ImportExcel -ErrorAction Stop
        
        Write-Log "Exporting to Excel with formatting..." -Level 'INFO'
        
        $Data | Export-Excel -Path $FilePath `
            -WorksheetName "EPM_Views" `
            -AutoSize `
            -AutoFilter `
            -FreezeTopRow `
            -BoldTopRow `
            -TableStyle Medium2 `
            -Force `
            -ErrorAction Stop
        
        if (Test-Path $FilePath) {
            $FileInfo = Get-Item $FilePath
            Write-Log "Excel export successful!" -Level 'SUCCESS'
            Write-Log "File size: $($FileInfo.Length) bytes ($([math]::Round($FileInfo.Length/1KB, 2)) KB)" -Level 'INFO'
            Write-Log "File location: $($FileInfo.FullName)" -Level 'INFO'
            Write-Log "Worksheet name: EPM_Views" -Level 'INFO'
            Write-Log "Formatting applied: AutoSize, AutoFilter, FreezeTopRow, BoldTopRow, TableStyle" -Level 'DEBUG'
            return $true
        }
        else {
            Write-Log "Excel export completed but file not found" -Level 'ERROR'
            return $false
        }
    }
    catch {
        Write-LogError "Excel export failed" $_
        return $false
    }
}

#endregion

#region ==================== MAIN EXECUTION ====================

function Main {
    $ScriptStartTime = Get-Date
    
    Write-LogSection "SCRIPT INITIALIZATION"
    Write-Log "EPM Views Data Export Script" -Level 'INFO'
    Write-Log "Script started at: $($ScriptStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level 'INFO'
    Write-Log "Log file: $LogFile" -Level 'INFO'
    Write-Log " " -Level 'INFO'
    Write-Log "Environment Information:" -Level 'INFO'
    Write-Log "  PowerShell Version: $($PSVersionTable.PSVersion)" -Level 'INFO'
    Write-Log "  OS: $([System.Environment]::OSVersion.VersionString)" -Level 'INFO'
    Write-Log "  User: $env:USERNAME" -Level 'INFO'
    Write-Log "  Machine: $env:COMPUTERNAME" -Level 'INFO'
    Write-Log "  Current Directory: $(Get-Location)" -Level 'INFO'
    
    try {
        # Validate parameters
        Write-LogSection "PARAMETER VALIDATION"
        Write-Log "Base URL: $BaseUrl" -Level 'INFO'
        Write-Log "Credential Path: $CredentialPath" -Level 'INFO'
        Write-Log "Output Directory: $OutputDirectory" -Level 'INFO'
        Write-Log "Log Path: $LogPath" -Level 'INFO'
        
        # Define output file paths
        $CsvFileName = "EPM_Views_Data_$Timestamp.csv"
        $ExcelFileName = "EPM_Views_Data_$Timestamp.xlsx"
        $CsvFilePath = Join-Path $OutputDirectory $CsvFileName
        $ExcelFilePath = Join-Path $OutputDirectory $ExcelFileName
        
        Write-Log "CSV output: $CsvFilePath" -Level 'INFO'
        Write-Log "Excel output: $ExcelFilePath" -Level 'INFO'
        
        # Load credentials
        $Credential = Get-EPMCredentialFromFile -Path $CredentialPath
        
        # Create auth headers
        $Headers = Get-BasicAuthHeader -Credential $Credential
        
        # Make API request
        $ApiUrl = "$BaseUrl/epm/rest/v1/views"
        $ApiResponse = Invoke-EPMApiRequest -Url $ApiUrl -Headers $Headers
        
        # Validate response
        Write-LogSection "RESPONSE VALIDATION"
        Write-Log "Validating API response structure..." -Level 'INFO'
        
        if (-not $ApiResponse) {
            Write-Log "API response is null or empty" -Level 'ERROR'
            throw "API returned no data"
        }
        
        Write-Log "Response object type: $($ApiResponse.GetType().Name)" -Level 'DEBUG'
        
        if ($ApiResponse.PSObject.Properties.Name -contains 'items') {
            Write-Log "Response contains 'items' property" -Level 'SUCCESS'
            $ViewCount = $ApiResponse.items.Count
            Write-Log "Number of views found: $ViewCount" -Level 'INFO'
            
            if ($ViewCount -eq 0) {
                Write-Log "No views found in the response" -Level 'WARNING'
                Write-Log "The API returned successfully but with zero views" -Level 'WARNING'
                throw "No views data to export"
            }
        }
        else {
            Write-Log "Response does NOT contain 'items' property" -Level 'ERROR'
            Write-Log "Available properties: $($ApiResponse.PSObject.Properties.Name -join ', ')" -Level 'ERROR'
            throw "API response structure is unexpected - missing 'items' array"
        }
        
        # Process data
        $FlattenedData = Convert-ViewsToFlatObjects -ViewItems $ApiResponse.items
        
        # Export to CSV
        $CsvSuccess = Export-ToCsv -Data $FlattenedData -FilePath $CsvFilePath
        
        # Export to Excel
        $ExcelSuccess = Export-ToExcel -Data $FlattenedData -FilePath $ExcelFilePath
        
        # Final summary
        Write-LogSection "EXECUTION SUMMARY"
        $ScriptEndTime = Get-Date
        $Duration = $ScriptEndTime - $ScriptStartTime
        
        Write-Log "Script execution completed successfully!" -Level 'SUCCESS'
        Write-Log " " -Level 'INFO'
        Write-Log "Summary:" -Level 'INFO'
        Write-Log "  Total Views Exported: $ViewCount" -Level 'INFO'
        Write-Log "  Execution Time: $($Duration.TotalSeconds.ToString('F2')) seconds" -Level 'INFO'
        Write-Log " " -Level 'INFO'
        Write-Log "Output Files:" -Level 'INFO'
        
        if ($CsvSuccess) {
            Write-Log "  âœ“ CSV: $CsvFilePath" -Level 'SUCCESS'
        }
        else {
            Write-Log "  âœ— CSV: Export failed" -Level 'ERROR'
        }
        
        if ($ExcelSuccess) {
            Write-Log "  âœ“ Excel: $ExcelFilePath" -Level 'SUCCESS'
        }
        else {
            Write-Log "  âœ— Excel: Export failed or skipped" -Level 'WARNING'
        }
        
        Write-Log " " -Level 'INFO'
        Write-Log "Log File: $LogFile" -Level 'INFO'
        
        # Display sample data
        Write-Log " " -Level 'INFO'
        Write-Log "Sample Data (first 5 records):" -Level 'INFO'
        $FlattenedData | Select-Object View_Name, Object_Status, Created_By, Time_Created -First 5 | 
            Format-Table -AutoSize | 
            Out-String | 
            ForEach-Object { Write-Log $_.Trim() -Level 'INFO' }
        
        Write-Log " " -Level 'INFO'
        Write-Log "Script completed successfully!" -Level 'SUCCESS'
        
        return $FlattenedData
    }
    catch {
        Write-LogSection "EXECUTION FAILED"
        Write-LogError "Script execution failed" $_
        
        $ScriptEndTime = Get-Date
        $Duration = $ScriptEndTime - $ScriptStartTime
        
        Write-Log " " -Level 'ERROR'
        Write-Log "Script failed after: $($Duration.TotalSeconds.ToString('F2')) seconds" -Level 'ERROR'
        Write-Log "Check log file for details: $LogFile" -Level 'ERROR'
        Write-Log " " -Level 'ERROR'
        Write-Log "Troubleshooting Tips:" -Level 'WARNING'
        Write-Log "  1. Verify credentials file exists and is accessible" -Level 'WARNING'
        Write-Log "  2. Ensure credentials were created by the same user on this machine" -Level 'WARNING'
        Write-Log "  3. Check network connectivity to EPM Cloud" -Level 'WARNING'
        Write-Log "  4. Verify the Base URL is correct" -Level 'WARNING'
        Write-Log "  5. Confirm you have permissions to access the Views API" -Level 'WARNING'
        
        exit 1
    }
}

# Execute main function
Main

#endregion
