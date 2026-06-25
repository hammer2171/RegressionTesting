#Requires -Version 5.1
<#
.SYNOPSIS
    Generic Oracle EDM REST template for epm18-test.

.DESCRIPTION
    Creates a timestamped run folder, decrypts CMS credentials, builds Basic auth
    headers, calls a parameterized EDM REST endpoint, and writes logs/output into
    the run folder.
#>

[CmdletBinding()]
param(
    [string]$BaseUrl = "https://epm18-test-a706571.epm.us2.oraclecloud.com",
    [Parameter(Mandatory)]
    [string]$Endpoint,
    [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
    [string]$Method = "GET",
    [string]$BodyPath,
    [string]$RunsDirectory = "C:\RegressionTesting\epm18-test\Runs",
    [string]$RunLabel = "rest",
    [string]$CmsSecretPath = "C:\Russ\Creds\rs.epm_credentials.cms",
    [string]$CertThumbprint = "",
    [string]$CertSubject = "CN=OracleEpmSecret",
    [string]$CertStoreLocation = "Cert:\LocalMachine\My"
)

$ErrorActionPreference = "Stop"
$script:LogFile = $null

function New-RunFolder {
    param([string]$Root, [string]$Label)
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safeLabel = ($Label -replace '[^a-zA-Z0-9_.-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeLabel)) { $safeLabel = "rest" }
    $path = Join-Path $Root "$stamp`_$safeLabel"
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

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

function Write-LogSection {
    param([string]$Title)
    Write-Log " "
    Write-Log ("=" * 80)
    Write-Log $Title
    Write-Log ("=" * 80)
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

$runFolder = New-RunFolder -Root $RunsDirectory -Label $RunLabel
$script:LogFile = Join-Path $runFolder "run.log"
$outputPath = Join-Path $runFolder "response.json"

try {
    Write-LogSection "EPM18 REST REQUEST"
    Write-Log "Run folder: $runFolder"
    Write-Log "Method: $Method"

    $cert = Get-CmsDecryptionCert -Thumbprint $CertThumbprint -Subject $CertSubject -StorePath $CertStoreLocation
    Write-Log "Using CMS certificate: Subject='$($cert.Subject)' Thumbprint=$($cert.Thumbprint)"

    $secret = Get-CmsCredentialObject -Path $CmsSecretPath -Certificate $cert
    $headers = New-BasicAuthHeaders -CredentialObject $secret
    $uri = Join-Endpoint -Base $BaseUrl -Path $Endpoint
    Write-Log "URI: $uri"

    $params = @{
        Method = $Method
        Uri = $uri
        Headers = $headers
        ErrorAction = "Stop"
    }

    if (-not [string]::IsNullOrWhiteSpace($BodyPath)) {
        if (-not (Test-Path -LiteralPath $BodyPath)) { throw "BodyPath not found: $BodyPath" }
        $params.Body = Get-Content -LiteralPath $BodyPath -Raw
        Write-Log "BodyPath: $BodyPath"
    }

    $response = Invoke-RestMethod @params
    $response | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $outputPath -Encoding UTF8
    Write-Log "Response written to: $outputPath" "SUCCESS"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}
