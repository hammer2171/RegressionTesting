<#, 
.SYNOPSIS
    Runs an Oracle EDM compare profile, writes the result to staging, and downloads the Excel file.

.DESCRIPTION
    Uses CMS certificate authentication, matching the pattern used by C:\EDM\Validate_Viewpoints.ps1.
    Creates a timestamped run folder under C:\EDM\CompareRuns for logs and downloaded files.

    The compare profile can be provided directly on the command line or through a profile file.

.PARAMETER ViewName
    Name of the EDM view that contains the compare profile.

.PARAMETER CompareProfileName
    Name of the compare profile to run.

.PARAMETER CompareProfileFile
    Optional file containing compare run settings. Supported formats:
      JSON: { "viewName":"A_Entry_Entity", "compareProfileName":"ACT_Entity_to_GSP_Entity", "fileName":"Compare.xlsx", "requestNumber":123 }
      Text: ViewName=A_Entry_Entity
            CompareProfileName=ACT_Entity_to_GSP_Entity
            FileName=Compare.xlsx
            RequestNumber=123
      Plain text: first non-empty line is treated as CompareProfileName.

.PARAMETER FileName
    Name of the staging/download file. A runtime timestamp is appended before the extension.

.EXAMPLE
    .\Download-EPMCompareFile.ps1 -ViewName "A_Entry_Entity" -CompareProfileName "ACT_Entity_to_GSP_Entity" -FileName "ACT_Entity_to_GSP_Entity.xlsx"

.EXAMPLE
    .\Download-EPMCompareFile.ps1 -CompareProfileFile "C:\EDM\CompareProfiles\ACT_Entity_to_GSP_Entity.json"
#>

[CmdletBinding()]
param(
    [string]$ViewName,
    [string]$CompareProfileName,
    [string]$CompareProfileFile,
    [string]$FileName,
    [int]$RequestNumber,
    [string]$BaseUrl = "https://epm20-test-a706571.epm.us2.oraclecloud.com",
    [string]$RootDirectory = "C:\EDM",
    [string]$RunsDirectory = "C:\EDM\CompareRuns",
    [string]$CmsSecretPath = "C:\Russ\Creds\rs.epm_credentials.cms",
    [string]$CertThumbprint = "94621577083C8E4F49C68C81D0B9FCB3FFA704EB",
    [string]$CertSubject = "CN=OracleEpmSecret",
    [string]$CertStoreLocation = "Cert:\LocalMachine\My",
    [int]$InitialWaitSeconds = 5,
    [int]$PollSeconds = 10,
    [int]$MaxPollAttempts = 60
)

$ErrorActionPreference = 'Stop'
$script:Headers = $null
$script:DownloadHeaders = $null
$script:EpmUserName = $null
$script:LogFile = $null

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','SUCCESS','WARNING','ERROR','DEBUG')]
        [string]$Level = 'INFO'
    )
    if ([string]::IsNullOrWhiteSpace($Message)) { $Message = ' ' }
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    Write-Host $line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
}

function Write-LogSection {
    param([string]$Title)
    Write-Log ' '
    Write-Log ('=' * 80)
    Write-Log $Title
    Write-Log ('=' * 80)
}

function Get-ErrorBodyText {
    param([object]$ErrorRecord)
    try {
        $response = $ErrorRecord.Exception.Response
        if ($response -and $response.GetResponseStream()) {
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            try { return $reader.ReadToEnd() }
            finally { $reader.Dispose() }
        }
    } catch { }
    return ''
}

function Get-SafeFileName {
    param([Parameter(Mandatory)][string]$Value)
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $chars = $Value.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { '_' } else { $_ } }
    return (-join $chars).Trim()
}

function Add-TimestampToFileName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Timestamp
    )
    $safeName = Get-SafeFileName -Value $Name
    $extension = [System.IO.Path]::GetExtension($safeName)
    if ([string]::IsNullOrWhiteSpace($extension)) { $extension = '.xlsx' }
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($safeName)
    if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = 'CompareProfile' }
    return "{0}_{1}{2}" -f $baseName, $Timestamp, $extension
}

function Read-CompareProfileFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { throw "Compare profile file not found: $Path" }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "Compare profile file is empty: $Path" }

    $settings = @{}
    if ([System.IO.Path]::GetExtension($Path) -ieq '.json') {
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
        foreach ($prop in $json.PSObject.Properties) { $settings[$prop.Name] = [string]$prop.Value }
        return $settings
    }

    $lines = @($raw -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    foreach ($line in $lines) {
        if ($line -match '^([^=:#]+)\s*[=:]\s*(.+)$') {
            $settings[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }

    if ($settings.Count -eq 0 -and $lines.Count -gt 0) { $settings['CompareProfileName'] = $lines[0] }
    return $settings
}

function Resolve-RunSettings {
    $settings = @{}
    if (-not [string]::IsNullOrWhiteSpace($CompareProfileFile)) {
        $settings = Read-CompareProfileFile -Path $CompareProfileFile
        Write-Log "Loaded compare profile settings from: $CompareProfileFile"
    }

    if ([string]::IsNullOrWhiteSpace($ViewName)) {
        foreach ($key in @('ViewName','viewName','view')) { if ($settings.ContainsKey($key)) { $script:ViewName = $settings[$key]; break } }
    }
    if ([string]::IsNullOrWhiteSpace($CompareProfileName)) {
        foreach ($key in @('CompareProfileName','compareProfileName','profile','profileName')) { if ($settings.ContainsKey($key)) { $script:CompareProfileName = $settings[$key]; break } }
    }
    if ([string]::IsNullOrWhiteSpace($FileName)) {
        foreach ($key in @('FileName','fileName','downloadFileName','outputFileName')) { if ($settings.ContainsKey($key)) { $script:FileName = $settings[$key]; break } }
    }
    if (-not $PSBoundParameters.ContainsKey('RequestNumber')) {
        foreach ($key in @('RequestNumber','requestNumber')) {
            if ($settings.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace($settings[$key])) { $script:RequestNumber = [int]$settings[$key]; break }
        }
    }

    if ([string]::IsNullOrWhiteSpace($script:ViewName)) { throw 'ViewName is required. Provide -ViewName or include ViewName/viewName in -CompareProfileFile.' }
    if ([string]::IsNullOrWhiteSpace($script:CompareProfileName)) { throw 'CompareProfileName is required. Provide -CompareProfileName or include CompareProfileName/compareProfileName in -CompareProfileFile.' }
    if ([string]::IsNullOrWhiteSpace($script:FileName)) { $script:FileName = "$($script:CompareProfileName).xlsx" }
}

function Get-CmsDecryptionCert {
    param(
        [string]$Thumbprint,
        [string]$Subject,
        [Parameter(Mandatory)][string]$StorePath
    )

    if (-not (Test-Path $StorePath)) { throw "Certificate store not found: $StorePath" }
    $cert = $null

    if (-not [string]::IsNullOrWhiteSpace($Thumbprint)) {
        $tp = ($Thumbprint -replace '\s', '').ToUpperInvariant()
        try { $cert = Get-ChildItem -Path (Join-Path $StorePath $tp) -ErrorAction Stop }
        catch {
            $cert = Get-ChildItem -Path $StorePath -ErrorAction Stop | Where-Object { $_.Thumbprint -eq $tp } | Select-Object -First 1
        }
        if (-not $cert) { throw "No certificate with thumbprint '$tp' found in $StorePath" }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Subject)) {
        $matches = @(Get-ChildItem -Path $StorePath -ErrorAction Stop | Where-Object { ($_.Subject -eq $Subject) -or ($_.Subject -like "*$Subject*") -or ($_.FriendlyName -eq $Subject) } | Sort-Object NotAfter -Descending)
        if ($matches.Count -eq 0) { throw "No certificate matching Subject/FriendlyName '$Subject' found in $StorePath" }
        if ($matches.Count -gt 1) { Write-Log "Multiple certificates matched '$Subject'. Using Thumbprint=$($matches[0].Thumbprint)" 'WARNING' }
        $cert = $matches[0]
    }
    else { throw 'Specify -CertThumbprint or -CertSubject' }

    if (-not $cert.HasPrivateKey) { throw "Certificate '$($cert.Subject)' Thumbprint=$($cert.Thumbprint) does not have an accessible private key" }
    return $cert
}

function Get-CmsCredentialObject {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    if (-not (Test-Path $Path)) { throw "No CMS secret file at $Path" }
    $raw = Unprotect-CmsMessage -LiteralPath $Path -To $Certificate -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "CMS secret file '$Path' decrypted to empty content" }

    try { $obj = $raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'CMS secret file ''{0}'' is not valid JSON. Expected JSON like {"UserName":"identitydomain.username","Password":"secret"}' -f $Path }

    if ([string]::IsNullOrWhiteSpace([string]$obj.UserName)) { throw 'CMS secret JSON missing UserName' }
    if ([string]::IsNullOrWhiteSpace([string]$obj.Password)) { throw 'CMS secret JSON missing Password' }
    return [pscustomobject]@{ UserName = [string]$obj.UserName; Password = [string]$obj.Password }
}

function Initialize-EpmAuth {
    $cert = Get-CmsDecryptionCert -Thumbprint $CertThumbprint -Subject $CertSubject -StorePath $CertStoreLocation
    Write-Log "Using CMS certificate: Subject='$($cert.Subject)' Thumbprint=$($cert.Thumbprint) Store='$CertStoreLocation'"

    $secret = Get-CmsCredentialObject -Path $CmsSecretPath -Certificate $cert
    $script:EpmUserName = $secret.UserName

    $authPair = "{0}:{1}" -f $secret.UserName, $secret.Password
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($authPair))

    $script:Headers = @{
        'Authorization' = "Basic $auth"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }
    $script:DownloadHeaders = @{
        'Authorization' = "Basic $auth"
        'Accept'        = '*/*'
    }
    Write-Log "Authentication initialized for Oracle EPM user '$($script:EpmUserName)'"
}

function Invoke-EpmJson {
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST')][string]$Method,
        [Parameter(Mandatory)][string]$Url,
        [object]$Body = $null
    )
    $params = @{ Method = $Method; Uri = $Url; Headers = $script:Headers; ContentType = 'application/json'; ErrorAction = 'Stop' }
    if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10) }
    return Invoke-RestMethod @params
}

function Get-LinkHref {
    param([object]$Response,[string[]]$RelNames)
    if ($Response -and $Response.PSObject.Properties.Name -contains 'links') {
        foreach ($rel in $RelNames) {
            $link = @($Response.links) | Where-Object { $_.rel -eq $rel } | Select-Object -First 1
            if ($link -and $link.href) { return [string]$link.href }
        }
        $first = @($Response.links) | Select-Object -First 1
        if ($first -and $first.href) { return [string]$first.href }
    }
    return $null
}

function Wait-CompareJob {
    param([string]$JobUrl)
    if ([string]::IsNullOrWhiteSpace($JobUrl)) { return $null }
    if ($InitialWaitSeconds -gt 0) { Start-Sleep -Seconds $InitialWaitSeconds }

    for ($attempt = 1; $attempt -le $MaxPollAttempts; $attempt++) {
        $job = Invoke-EpmJson -Method GET -Url $JobUrl
        $status = [string]$job.status
        Write-Log "Job poll ${attempt}/${MaxPollAttempts}: $status" 'DEBUG'
        if ($status -and $status -notin @('RUNNING','PENDING','IN_PROGRESS','PROCESSING')) { return $job }
        Start-Sleep -Seconds $PollSeconds
    }
    throw "Compare job did not finish after $MaxPollAttempts polling attempts: $JobUrl"
}

function Download-StagingFile {
    param(
        [Parameter(Mandatory)][string]$StagingFileName,
        [Parameter(Mandatory)][string]$OutFile
    )
    $urlFileName = [System.Uri]::EscapeDataString($StagingFileName)
    $downloadUrl = "$($BaseUrl.TrimEnd('/'))/epm/rest/v1/files/staging/$urlFileName"
    Write-Log "Downloading staging file: $downloadUrl"
    Invoke-WebRequest -Uri $downloadUrl -Method GET -Headers $script:DownloadHeaders -OutFile $OutFile -ErrorAction Stop | Out-Null
}

function Main {
    $runTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    if (-not (Test-Path -LiteralPath $RootDirectory)) { New-Item -ItemType Directory -Path $RootDirectory -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $RunsDirectory)) { New-Item -ItemType Directory -Path $RunsDirectory -Force | Out-Null }

    Resolve-RunSettings

    $runName = Get-SafeFileName -Value ($script:CompareProfileName -replace '\s+', '_')
    $runFolder = Join-Path $RunsDirectory ("{0}_{1}" -f $runTimestamp, $runName)
    New-Item -ItemType Directory -Path $runFolder -Force | Out-Null
    $script:LogFile = Join-Path $runFolder ("Download_EPMCompareFile_{0}.log" -f $runTimestamp)

    $stagingFileName = Add-TimestampToFileName -Name $script:FileName -Timestamp $runTimestamp
    $downloadPath = Join-Path $runFolder $stagingFileName
    $baseUrlTrimmed = $BaseUrl.TrimEnd('/')
    $compareEndpoint = "$baseUrlTrimmed/epm/rest/v1/views/compare/writeToFile"

    Write-LogSection 'SCRIPT INITIALIZATION'
    Write-Log 'Oracle EPM Cloud - Compare File Downloader'
    Write-Log "BaseUrl: $baseUrlTrimmed"
    Write-Log "RootDirectory: $RootDirectory"
    Write-Log "RunsDirectory: $RunsDirectory"
    Write-Log "RunFolder: $runFolder"
    Write-Log "ViewName: $script:ViewName"
    Write-Log "CompareProfileName: $script:CompareProfileName"
    Write-Log "Staging/Download FileName: $stagingFileName"
    Write-Log "Download Path: $downloadPath"
    if ($PSBoundParameters.ContainsKey('RequestNumber') -or $script:RequestNumber) { Write-Log "RequestNumber: $script:RequestNumber" }

    Write-LogSection 'AUTHENTICATION'
    Initialize-EpmAuth

    $payload = [ordered]@{
        viewName = $script:ViewName
        compareProfileName = $script:CompareProfileName
        fileName = $stagingFileName
    }
    if ($script:RequestNumber) { $payload.requestNumber = [int]$script:RequestNumber }

    Write-LogSection 'COMPARE PROFILE EXPORT'
    Write-Log "POST $compareEndpoint"
    Write-Log "Payload: $(($payload | ConvertTo-Json -Depth 10 -Compress))" 'DEBUG'

    try {
        $compareResponse = Invoke-EpmJson -Method POST -Url $compareEndpoint -Body $payload
        Write-Log 'Compare API request accepted.' 'SUCCESS'
        Write-Log "Response: $(($compareResponse | ConvertTo-Json -Depth 10 -Compress))" 'DEBUG'
    }
    catch {
        $body = Get-ErrorBodyText -ErrorRecord $_
        Write-Log "Compare API call failed: $($_.Exception.Message)" 'ERROR'
        if ($body) { Write-Log "Response Body: $body" 'ERROR' }
        throw
    }

    $jobUrl = Get-LinkHref -Response $compareResponse -RelNames @('results','result','Job Status','job-status','self')
    $jobResult = $null
    if ($jobUrl) {
        Write-Log "Job URL: $jobUrl"
        $jobResult = Wait-CompareJob -JobUrl $jobUrl
        Write-Log "Job completed with status: $($jobResult.status)"
        Write-Log "Job result: $(($jobResult | ConvertTo-Json -Depth 10 -Compress))" 'DEBUG'
        if ($jobResult.status -eq 'ERROR') { Write-Log "Compare job returned ERROR. Download will still be attempted only if the staging file exists." 'WARNING' }
    }
    else {
        Write-Log 'No job URL returned. Proceeding directly to staging download.' 'WARNING'
    }

    Write-LogSection 'DOWNLOAD'
    try {
        Download-StagingFile -StagingFileName $stagingFileName -OutFile $downloadPath
        Write-Log "Downloaded file: $downloadPath" 'SUCCESS'
    }
    catch {
        $body = Get-ErrorBodyText -ErrorRecord $_
        Write-Log "Download failed: $($_.Exception.Message)" 'ERROR'
        if ($body) { Write-Log "Response Body: $body" 'ERROR' }
        throw
    }

    if (-not (Test-Path -LiteralPath $downloadPath)) { throw "Downloaded file was not created: $downloadPath" }
    $fileInfo = Get-Item -LiteralPath $downloadPath
    Write-Log "Downloaded file size: $($fileInfo.Length) bytes"

    if ($fileInfo.Length -ge 2) {
        $bytes = [System.IO.File]::ReadAllBytes($downloadPath)
        if ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B) { Write-Log 'File signature verified as Excel/ZIP.' 'SUCCESS' }
        else { Write-Log 'Downloaded file does not have an Excel/ZIP signature.' 'WARNING' }
    }

    $summaryPath = Join-Path $runFolder ("CompareRunSummary_{0}.csv" -f $runTimestamp)
    [pscustomobject]@{
        RunTimestamp = $runTimestamp
        BaseUrl = $baseUrlTrimmed
        ViewName = $script:ViewName
        CompareProfileName = $script:CompareProfileName
        StagingFileName = $stagingFileName
        DownloadPath = $downloadPath
        JobUrl = $jobUrl
        JobStatus = if ($jobResult) { $jobResult.status } else { $null }
        LogFile = $script:LogFile
    } | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8 -Force
    Write-Log "Summary: $summaryPath" 'SUCCESS'

    Write-LogSection 'DONE'
    Write-Log "Run folder: $runFolder"
    Write-Log "Downloaded file: $downloadPath"
}

try { Main }
catch {
    Write-LogSection 'EXECUTION FAILED'
    Write-Log "Script failed: $($_.Exception.Message)" 'ERROR'
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" 'DEBUG'
    throw
}
