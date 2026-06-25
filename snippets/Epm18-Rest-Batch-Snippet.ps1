#Requires -Version 5.1
<#
.SYNOPSIS
    Parameterized REST batch snippet for epm18-test.

.DESCRIPTION
    Use this as a starting point when you want to call one or more REST endpoints
    with the same POST body, while switching between normal runs and SCU runs.

    - Normal runs write to: Runs\<Run_Label>_yyyyMMdd_HHmmss
    - SCU runs write to: scu\Runs\<Run_Label>_yyyyMMdd_HHmmss

    The snippet uses the CMS Basic-auth pattern from the project scripts.
#>

[CmdletBinding()]
param(
    [string]$BaseUrl = "https://epm18-test-a706571.epm.us2.oraclecloud.com",
    [string]$RunLabel = "rest_batch",
    [switch]$Scu,
    [string]$Folder = "epm18-test",
    [string]$RegressionRoot = "C:\RegressionTesting",

    [Parameter(Mandatory)]
    [string[]]$Endpoints,

    [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
    [string]$Method = "POST",

    [string]$PostBodyPath,
    [string]$PostBodyJson,

    [string]$AuditEndpoint,
    [string]$NotificationSource,
    [string]$NotificationSuccessPattern = "(?i)\b(pass|passed|success|succeeded)\b",
    [string]$NotificationFailurePattern = "(?i)\b(fail|failed|error)\b",
    [int]$RetryCount = 0,
    [int]$PollSeconds = 10,
    [int]$ThrottleMilliseconds = 0,

    [string]$ProjectRoot = "C:\RegressionTesting\epm18-test",
    [string]$CmsSecretPath = "C:\Russ\Creds\rs.epm_credentials.cms",
    [string]$CertThumbprint = "",
    [string]$CertSubject = "CN=OracleEpmSecret",
    [string]$CertStoreLocation = "Cert:\LocalMachine\My"
)

$ErrorActionPreference = "Stop"
$script:LogFile = $null
$ProjectRoot = if ($PSBoundParameters.ContainsKey('ProjectRoot') -and -not [string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot } else { Join-Path $RegressionRoot $Folder }

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    if ([string]::IsNullOrWhiteSpace($Message)) { $Message = " " }
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Level, $Message
    Write-Host $line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
}

function New-RunFolder {
    param(
        [string]$Root,
        [string]$Label
    )
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safeLabel = ($Label -replace '[^a-zA-Z0-9_.-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeLabel)) { $safeLabel = "rest" }
    $path = Join-Path $Root "$safeLabel`_$stamp"
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Resolve-RunsRoot {
    if ($Scu) {
        return Join-Path $ProjectRoot "scu\Runs"
    }
    return Join-Path $ProjectRoot "Runs"
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
            $cert = Get-ChildItem -Path $StorePath -ErrorAction Stop |
                Where-Object { $_.Thumbprint -eq $tp } |
                Select-Object -First 1
        }
        if (-not $cert) { throw "No certificate with thumbprint '$tp' found in $StorePath" }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Subject)) {
        $matches = @(Get-ChildItem -Path $StorePath -ErrorAction Stop |
            Where-Object { ($_.Subject -eq $Subject) -or ($_.Subject -like "*$Subject*") -or ($_.FriendlyName -eq $Subject) } |
            Sort-Object NotAfter -Descending)
        if ($matches.Count -eq 0) { throw "No certificate matching Subject/FriendlyName '$Subject' found in $StorePath" }
        if ($matches.Count -gt 1) { Write-Log "Multiple certificates matched '$Subject'. Using Thumbprint=$($matches[0].Thumbprint)" "WARNING" }
        $cert = $matches[0]
    }
    else {
        throw "Specify -CertThumbprint or -CertSubject"
    }

    if (-not $cert.HasPrivateKey) { throw "Certificate '$($cert.Subject)' Thumbprint=$($cert.Thumbprint) does not have an accessible private key" }
    return $cert
}

function Get-CmsCredentialObject {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    if (-not (Test-Path -LiteralPath $Path)) { throw "No CMS secret file at $Path" }
    $raw = Unprotect-CmsMessage -LiteralPath $Path -To $Certificate -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "CMS secret file '$Path' decrypted to empty content" }
    $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string]$obj.UserName)) { throw "CMS secret JSON missing UserName" }
    if ([string]::IsNullOrWhiteSpace([string]$obj.Password)) { throw "CMS secret JSON missing Password" }
    return [pscustomobject]@{ UserName = [string]$obj.UserName; Password = [string]$obj.Password }
}

function New-BasicAuthHeaders {
    param([Parameter(Mandatory)]$CredentialObject)
    $pair = "{0}:{1}" -f $CredentialObject.UserName, $CredentialObject.Password
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
    return @{
        Authorization = "Basic $token"
        Accept = "application/json"
        "Content-Type" = "application/json"
    }
}

function Join-Endpoint {
    param([string]$Base, [string]$Path)
    $baseClean = $Base.TrimEnd("/")
    if ($Path -match '^https?://') { return $Path }
    $pathClean = $Path.TrimStart("/")
    return "$baseClean/$pathClean"
}

function Get-BodyPayload {
    if (-not [string]::IsNullOrWhiteSpace($PostBodyJson)) {
        return ($PostBodyJson | ConvertFrom-Json -ErrorAction Stop)
    }
    if (-not [string]::IsNullOrWhiteSpace($PostBodyPath)) {
        if (-not (Test-Path -LiteralPath $PostBodyPath)) { throw "Post body path not found: $PostBodyPath" }
        return (Get-Content -LiteralPath $PostBodyPath -Raw | ConvertFrom-Json -ErrorAction Stop)
    }
    return $null
}

function Invoke-JsonRest {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][hashtable]$Headers,
        [object]$Body
    )

    $params = @{
        Uri = $Uri
        Method = $Method
        Headers = $Headers
        ErrorAction = "Stop"
    }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body -and $Method -ne "GET") {
        $params.Body = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Depth 80 -Compress) }
    }
    return Invoke-RestMethod @params
}

function Resolve-Uri {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -match '^https?://') { return $Value }
    return Join-Endpoint -Base $BaseUrl -Path $Value
}

function Get-NotificationText {
    if ([string]::IsNullOrWhiteSpace($NotificationSource)) { return $null }
    $uri = Resolve-Uri -Value $NotificationSource
    $response = Invoke-JsonRest -Uri $uri -Method "GET" -Headers $headers
    if ($null -eq $response) { return $null }
    if ($response -is [string]) { return $response }
    return ($response | ConvertTo-Json -Depth 20 -Compress)
}

function Wait-ForNotificationResult {
    if ([string]::IsNullOrWhiteSpace($NotificationSource)) { return $null }
    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $PollSeconds * [Math]::Max(1, $RetryCount + 1)))
    while ((Get-Date) -lt $deadline) {
        $text = Get-NotificationText
        if ($text) {
            Write-Log "Notification text: $text"
            if ($text -match $NotificationFailurePattern) { return [pscustomobject]@{ Status = 'Failed'; Text = $text } }
            if ($text -match $NotificationSuccessPattern) { return [pscustomobject]@{ Status = 'Passed'; Text = $text } }
        }
        Start-Sleep -Seconds [Math]::Max(1, $PollSeconds)
    }
    return [pscustomobject]@{ Status = 'TimedOut'; Text = (Get-NotificationText) }
}

$runsRoot = Resolve-RunsRoot
if (-not (Test-Path -LiteralPath $runsRoot)) {
    New-Item -ItemType Directory -Path $runsRoot -Force | Out-Null
}

$runFolder = New-RunFolder -Root $runsRoot -Label $RunLabel
$script:LogFile = Join-Path $runFolder "run.log"
$payload = Get-BodyPayload

Write-Log "Run folder: $runFolder"
Write-Log "Run mode: $(if ($Scu) { 'SCU' } else { 'Normal' })"
Write-Log "Base URL: $BaseUrl"
Write-Log "Method: $Method"

$cert = Get-CmsDecryptionCert -Thumbprint $CertThumbprint -Subject $CertSubject -StorePath $CertStoreLocation
$secret = Get-CmsCredentialObject -Path $CmsSecretPath -Certificate $cert
$headers = New-BasicAuthHeaders -CredentialObject $secret

$summary = New-Object System.Collections.ArrayList
foreach ($endpoint in $Endpoints) {
    $uri = Join-Endpoint -Base $BaseUrl -Path $endpoint
    Write-Log "Calling: $Method $uri"

    $requestFile = Join-Path $runFolder ("{0}.request.json" -f (($endpoint -replace '[^a-zA-Z0-9_.-]+', '_').Trim('_')))
    $responseFile = Join-Path $runFolder ("{0}.response.json" -f (($endpoint -replace '[^a-zA-Z0-9_.-]+', '_').Trim('_')))

    if ($null -ne $payload) {
        $payload | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $requestFile -Encoding UTF8
    }

    $invokeParams = @{
        Uri = $uri
        Method = $Method
        Headers = $headers
        ErrorAction = "Stop"
    }
    if ($Method -ne "GET" -and $null -ne $payload) {
        $invokeParams.Body = ($payload | ConvertTo-Json -Depth 80 -Compress)
    }

    $attemptCount = [Math]::Max(1, $RetryCount + 1)
    for ($attempt = 1; $attempt -le $attemptCount; $attempt++) {
        try {
            if ($attempt -gt 1) {
                Write-Log "Retry attempt $attempt of $attemptCount for $endpoint" "WARNING"
            }

            $response = Invoke-RestMethod @invokeParams
            $response | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $responseFile -Encoding UTF8
            [void]$summary.Add([pscustomobject]@{
                Endpoint = $endpoint
                Uri = $uri
                Method = $Method
                Status = "Success"
                Attempt = $attempt
            })
            Write-Log "Success: $endpoint" "SUCCESS"
            break
        }
        catch {
            if ($attempt -ge $attemptCount) {
                [void]$summary.Add([pscustomobject]@{
                    Endpoint = $endpoint
                    Uri = $uri
                    Method = $Method
                    Status = "Failed"
                    Message = $_.Exception.Message
                })
                Write-Log "Failed: $endpoint - $($_.Exception.Message)" "ERROR"
            }
            else {
                Write-Log "Retrying after failure: $($_.Exception.Message)" "WARNING"
                Start-Sleep -Seconds [Math]::Max(1, $PollSeconds)
            }
        }
    }

    if ($ThrottleMilliseconds -gt 0) {
        Start-Sleep -Milliseconds $ThrottleMilliseconds
    }
}

$notificationResult = $null
if ($Scu) {
    if ($NotificationSource) {
        $notificationResult = Wait-ForNotificationResult
        if ($notificationResult) {
            $notificationPath = Join-Path $runFolder "notification.txt"
            Set-Content -LiteralPath $notificationPath -Value $notificationResult.Text -Encoding UTF8
            Write-Log "Notification status: $($notificationResult.Status)"
        }
    }

    if ($AuditEndpoint) {
        $auditUri = Resolve-Uri -Value $AuditEndpoint
        Write-Log "Downloading audit records from $auditUri"
        $auditResponse = Invoke-JsonRest -Uri $auditUri -Method "GET" -Headers $headers
        $auditPath = Join-Path $runFolder "audit.json"
        $auditResponse | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $auditPath -Encoding UTF8
        Write-Log "Audit records written: $auditPath" "SUCCESS"
    }
}

$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $runFolder "summary.json") -Encoding UTF8
$summary | Export-Csv -LiteralPath (Join-Path $runFolder "summary.csv") -NoTypeInformation -Encoding UTF8 -Force
Write-Log "Summary written." "SUCCESS"
