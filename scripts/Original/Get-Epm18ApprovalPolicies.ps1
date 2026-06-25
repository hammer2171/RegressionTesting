#Requires -Version 5.1
<#
.SYNOPSIS
    Exports approval policies from a configured EPM folder.

.DESCRIPTION
    Calls /epm/rest/v1/policies, writes the raw JSON response and a flattened CSV
    list into a timestamped run folder.
#>

[CmdletBinding()]
param(
    [string]$Folder = "epm18-test",
    [string]$RegressionRoot = "C:\RegressionTesting",
    [string]$ProjectRoot,
    [string]$BaseUrl = "https://epm18-test-a706571.epm.us2.oraclecloud.com",
    [string]$RunsDirectory,
    [string]$RunLabel = "approval_policies",
    [string]$CmsSecretPath = "C:\Russ\Creds\rs.epm_credentials.cms",
    [string]$CertThumbprint = "",
    [string]$CertSubject = "CN=OracleEpmSecret",
    [string]$CertStoreLocation = "Cert:\LocalMachine\My"
)

$ErrorActionPreference = "Stop"
$script:LogFile = $null
$ProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { Join-Path $RegressionRoot $Folder } else { $ProjectRoot }
if ([string]::IsNullOrWhiteSpace($RunsDirectory)) {
    $RunsDirectory = Join-Path $ProjectRoot "Runs"
}

function New-RunFolder {
    param([string]$Root, [string]$Label)
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safeLabel = ($Label -replace '[^a-zA-Z0-9_.-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeLabel)) { $safeLabel = "approval_policies" }
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
    else { throw "Specify -CertThumbprint or -CertSubject" }

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

function Get-FirstPropertyValue {
    param([object]$Object, [string[]]$Names)
    if ($null -eq $Object) { return $null }
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) { return $Object.$name }
    }
    return $null
}

function Get-NestedValue {
    param([object]$Object, [string[]]$Names)
    $value = Get-FirstPropertyValue -Object $Object -Names $Names
    if ($null -eq $value) { return $null }
    if ($value -is [string] -or $value -is [int] -or $value -is [long] -or $value -is [bool]) { return $value }
    $nested = Get-FirstPropertyValue -Object $value -Names @("name", "Name", "id", "ID")
    if ($null -ne $nested) { return $nested }
    return ($value | ConvertTo-Json -Depth 6 -Compress)
}

function Get-PolicyItems {
    param([object]$Response)
    if ($null -eq $Response) { return @() }
    if ($Response.PSObject.Properties.Name -contains "items") { return @($Response.items) }
    if ($Response.PSObject.Properties.Name -contains "policies") { return @($Response.policies) }
    if ($Response -is [array]) { return @($Response) }
    return @($Response)
}

function Convert-PolicyToFlatObject {
    param([Parameter(Mandatory)][object]$Policy)
    $view = Get-FirstPropertyValue -Object $Policy -Names @("view", "View")
    [pscustomobject]@{
        PolicyId = Get-FirstPropertyValue -Object $Policy -Names @("id", "ID", "policyId", "PolicyId")
        PolicyName = Get-FirstPropertyValue -Object $Policy -Names @("name", "Name", "policyName", "PolicyName")
        Description = Get-FirstPropertyValue -Object $Policy -Names @("description", "Description")
        Enabled = Get-FirstPropertyValue -Object $Policy -Names @("enabled", "Enabled", "enabledFlag", "EnabledFlag", "isEnabled", "IsEnabled")
        ViewId = if ($view) { Get-FirstPropertyValue -Object $view -Names @("id", "ID", "viewId", "ViewId") } else { Get-FirstPropertyValue -Object $Policy -Names @("viewId", "ViewId") }
        ViewName = if ($view) { Get-FirstPropertyValue -Object $view -Names @("name", "Name", "viewName", "ViewName") } else { Get-FirstPropertyValue -Object $Policy -Names @("viewName", "ViewName") }
        Application = Get-NestedValue -Object $Policy -Names @("application", "Application")
        Dimension = Get-NestedValue -Object $Policy -Names @("dimension", "Dimension")
        ObjectStatus = Get-FirstPropertyValue -Object $Policy -Names @("objectStatus", "ObjectStatus", "status", "Status")
    }
}

$runFolder = New-RunFolder -Root $RunsDirectory -Label $RunLabel
$script:LogFile = Join-Path $runFolder "run.log"
$rawPath = Join-Path $runFolder "approval-policies.raw.json"
$csvPath = Join-Path $runFolder "approval-policies.csv"
$jsonPath = Join-Path $runFolder "approval-policies.normalized.json"

try {
    Write-LogSection "EXPORT APPROVAL POLICIES"
    Write-Log "Run folder: $runFolder"
    Write-Log "Base URL: $BaseUrl"

    $cert = Get-CmsDecryptionCert -Thumbprint $CertThumbprint -Subject $CertSubject -StorePath $CertStoreLocation
    Write-Log "Using CMS certificate: Subject='$($cert.Subject)' Thumbprint=$($cert.Thumbprint)" "SUCCESS"
    $secret = Get-CmsCredentialObject -Path $CmsSecretPath -Certificate $cert
    Write-Log "Authentication initialized for Oracle EPM user '$($secret.UserName)'" "SUCCESS"
    $headers = New-BasicAuthHeaders -CredentialObject $secret

    $uri = "$($BaseUrl.TrimEnd('/'))/epm/rest/v1/policies"
    Write-Log "GET $uri"
    $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -ErrorAction Stop
    $response | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $rawPath -Encoding UTF8

    $policies = @(Get-PolicyItems -Response $response)
    $rows = @($policies | ForEach-Object { Convert-PolicyToFlatObject -Policy $_ })
    $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -Force
    $rows | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    Write-Log "Policies exported: $($rows.Count)" "SUCCESS"
    Write-Log "CSV: $csvPath"
    Write-Log "JSON: $jsonPath"
    Write-Log "Raw response: $rawPath"
    $rows
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}
