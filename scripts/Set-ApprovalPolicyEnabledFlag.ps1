#Requires -Version 5.1
<#
.SYNOPSIS
    Enables or disables Oracle EDM approval policies in a configured EPM folder.

.DESCRIPTION
    Fetches all policies from /epm/rest/v1/policies, writes a full inventory,
    filters policies by all/list/view, then calls
    /epm/rest/v1/policies/{policyId}/updateEnabledFlag for each selected policy.

    The default request body is {"enabled": true|false}. If Oracle requires a
    different field name for the enabled flag, use -EnabledPropertyName.

.EXAMPLE
    .\Set-Epm18ApprovalPolicyEnabledFlag.ps1 -Action Disable -All -WhatIf

.EXAMPLE
    .\Set-Epm18ApprovalPolicyEnabledFlag.ps1 -Action Enable -PolicyIds "123","456"

.EXAMPLE
    .\Set-Epm18ApprovalPolicyEnabledFlag.ps1 -Action Disable -PolicyIdFile .\policy-ids.txt

.EXAMPLE
    .\Set-Epm18ApprovalPolicyEnabledFlag.ps1 -Action Enable -ViewName "Finance Planning"
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
param(
    [Parameter(Mandatory)]
    [ValidateSet("Enable", "Disable")]
    [string]$Action,

    [switch]$All,
    [string[]]$PolicyIds,
    [string]$PolicyIdFile,
    [string]$ViewId,
    [string]$ViewName,

    [string]$Folder = "epm18-test",
    [string]$RegressionRoot = "C:\RegressionTesting",
    [string]$ProjectRoot,
    [string]$BaseUrl = "https://epm18-test-a706571.epm.us2.oraclecloud.com",
    [string]$RunsDirectory,
    [string]$RunLabel = "approval_policy_enabled_flag",
    [string]$CmsSecretPath = "C:\Russ\Creds\rs.epm_credentials.cms",
    [string]$CertThumbprint = "",
    [string]$CertSubject = "CN=OracleEpmSecret",
    [string]$CertStoreLocation = "Cert:\LocalMachine\My",

    [ValidateSet("POST", "PUT", "PATCH")]
    [string]$UpdateMethod = "POST",
    [string]$EnabledPropertyName = "enabled",
    [int]$DelayMilliseconds = 0
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
    if ([string]::IsNullOrWhiteSpace($safeLabel)) { $safeLabel = "approval_policy_enabled_flag" }
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
    $policyId = Get-FirstPropertyValue -Object $Policy -Names @("id", "ID", "policyId", "PolicyId")
    $policyName = Get-FirstPropertyValue -Object $Policy -Names @("name", "Name", "policyName", "PolicyName")
    $policyViewId = if ($view) { Get-FirstPropertyValue -Object $view -Names @("id", "ID", "viewId", "ViewId") } else { Get-FirstPropertyValue -Object $Policy -Names @("viewId", "ViewId") }
    $policyViewName = if ($view) { Get-FirstPropertyValue -Object $view -Names @("name", "Name", "viewName", "ViewName") } else { Get-FirstPropertyValue -Object $Policy -Names @("viewName", "ViewName") }

    [pscustomobject]@{
        PolicyId = $policyId
        PolicyName = $policyName
        Description = Get-FirstPropertyValue -Object $Policy -Names @("description", "Description")
        Enabled = Get-FirstPropertyValue -Object $Policy -Names @("enabled", "Enabled", "enabledFlag", "EnabledFlag", "isEnabled", "IsEnabled")
        ViewId = $policyViewId
        ViewName = $policyViewName
        Raw = $Policy
    }
}

function Read-PolicyIdsFromFile {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return @() }
    if (-not (Test-Path -LiteralPath $Path)) { throw "PolicyIdFile not found: $Path" }

    if ([System.IO.Path]::GetExtension($Path) -ieq ".csv") {
        $rows = @(Import-Csv -LiteralPath $Path)
        return @($rows | ForEach-Object {
            $id = Get-FirstPropertyValue -Object $_ -Names @("PolicyId", "policyId", "Id", "id")
            if (-not [string]::IsNullOrWhiteSpace([string]$id)) { [string]$id }
        })
    }

    return @(Get-Content -LiteralPath $Path | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") })
}

function Test-PolicyMatchesTarget {
    param([object]$PolicyRow, [string[]]$TargetIds)

    if ($All) { return $true }
    if ($TargetIds.Count -gt 0 -and ($TargetIds -contains [string]$PolicyRow.PolicyId)) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($ViewId) -and [string]$PolicyRow.ViewId -eq $ViewId) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($ViewName) -and [string]$PolicyRow.ViewName -eq $ViewName) { return $true }
    return $false
}

function New-EnabledFlagBody {
    param([bool]$Enabled, [string]$PropertyName)
    $body = @{}
    $body[$PropertyName] = $Enabled
    return ($body | ConvertTo-Json -Depth 5 -Compress)
}

$targetModes = 0
if ($All) { $targetModes++ }
if ($PolicyIds -and $PolicyIds.Count -gt 0) { $targetModes++ }
if (-not [string]::IsNullOrWhiteSpace($PolicyIdFile)) { $targetModes++ }
if (-not [string]::IsNullOrWhiteSpace($ViewId)) { $targetModes++ }
if (-not [string]::IsNullOrWhiteSpace($ViewName)) { $targetModes++ }
if ($targetModes -eq 0) { throw "Specify one target: -All, -PolicyIds, -PolicyIdFile, -ViewId, or -ViewName." }
if ($targetModes -gt 1 -and -not (($PolicyIds -and $PolicyIds.Count -gt 0) -and -not [string]::IsNullOrWhiteSpace($PolicyIdFile) -and $targetModes -eq 2)) {
    throw "Use one target mode at a time. You may combine -PolicyIds and -PolicyIdFile."
}

$runFolder = New-RunFolder -Root $RunsDirectory -Label $RunLabel
$script:LogFile = Join-Path $runFolder "run.log"
$inventoryCsvPath = Join-Path $runFolder "approval-policies.before.csv"
$inventoryJsonPath = Join-Path $runFolder "approval-policies.before.raw.json"
$selectedCsvPath = Join-Path $runFolder "approval-policies.selected.csv"
$resultsCsvPath = Join-Path $runFolder "approval-policy-update-results.csv"
$resultsJsonPath = Join-Path $runFolder "approval-policy-update-results.json"

try {
    Write-LogSection "APPROVAL POLICY ENABLED FLAG UPDATE"
    Write-Log "Run folder: $runFolder"
    Write-Log "Action: $Action"
    Write-Log "Base URL: $BaseUrl"

    $cert = Get-CmsDecryptionCert -Thumbprint $CertThumbprint -Subject $CertSubject -StorePath $CertStoreLocation
    Write-Log "Using CMS certificate: Subject='$($cert.Subject)' Thumbprint=$($cert.Thumbprint)" "SUCCESS"
    $secret = Get-CmsCredentialObject -Path $CmsSecretPath -Certificate $cert
    Write-Log "Authentication initialized for Oracle EPM user '$($secret.UserName)'" "SUCCESS"
    $headers = New-BasicAuthHeaders -CredentialObject $secret

    Write-LogSection "POLICY INVENTORY"
    $policyUri = "$($BaseUrl.TrimEnd('/'))/epm/rest/v1/policies"
    Write-Log "GET $policyUri"
    $response = Invoke-RestMethod -Uri $policyUri -Method GET -Headers $headers -ErrorAction Stop
    $response | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $inventoryJsonPath -Encoding UTF8

    $policyRows = @(Get-PolicyItems -Response $response | ForEach-Object { Convert-PolicyToFlatObject -Policy $_ })
    $policyRows |
        Select-Object PolicyId, PolicyName, Description, Enabled, ViewId, ViewName |
        Export-Csv -LiteralPath $inventoryCsvPath -NoTypeInformation -Encoding UTF8 -Force
    Write-Log "Policies found: $($policyRows.Count)"
    Write-Log "Inventory CSV: $inventoryCsvPath"

    $filePolicyIds = @(Read-PolicyIdsFromFile -Path $PolicyIdFile)
    $targetPolicyIds = @($PolicyIds + $filePolicyIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } | Select-Object -Unique)

    $selectedPolicies = @($policyRows | Where-Object { Test-PolicyMatchesTarget -PolicyRow $_ -TargetIds $targetPolicyIds })
    $selectedPolicies |
        Select-Object PolicyId, PolicyName, Description, Enabled, ViewId, ViewName |
        Export-Csv -LiteralPath $selectedCsvPath -NoTypeInformation -Encoding UTF8 -Force
    Write-Log "Policies selected: $($selectedPolicies.Count)"
    Write-Log "Selected CSV: $selectedCsvPath"

    if ($selectedPolicies.Count -eq 0) {
        Write-Log "No policies matched the requested target." "WARNING"
        return @()
    }

    Write-LogSection "UPDATES"
    $enabledValue = $Action -eq "Enable"
    $body = New-EnabledFlagBody -Enabled $enabledValue -PropertyName $EnabledPropertyName
    Write-Log "Update method: $UpdateMethod"
    Write-Log "Update body: $body"

    $results = New-Object System.Collections.ArrayList
    foreach ($policy in $selectedPolicies) {
        if ([string]::IsNullOrWhiteSpace([string]$policy.PolicyId)) {
            Write-Log "Skipping policy with blank PolicyId: $($policy.PolicyName)" "WARNING"
            continue
        }

        $encodedId = [uri]::EscapeDataString([string]$policy.PolicyId)
        $updateUri = "$($BaseUrl.TrimEnd('/'))/epm/rest/v1/policies/$encodedId/updateEnabledFlag"
        $target = "$($policy.PolicyName) [$($policy.PolicyId)]"

        $result = [ordered]@{
            PolicyId = $policy.PolicyId
            PolicyName = $policy.PolicyName
            ViewId = $policy.ViewId
            ViewName = $policy.ViewName
            RequestedAction = $Action
            Uri = $updateUri
            Status = "Skipped"
            Message = ""
        }

        if ($PSCmdlet.ShouldProcess($target, "$Action approval policy")) {
            try {
                Write-Log "$Action policy: $target"
                $updateResponse = Invoke-RestMethod -Uri $updateUri -Method $UpdateMethod -Headers $headers -Body $body -ErrorAction Stop
                $result.Status = "Success"
                $result.Message = "Updated"
                $responsePath = Join-Path $runFolder ("policy_{0}_response.json" -f (($policy.PolicyId -replace '[^a-zA-Z0-9_.-]+', '_').Trim('_')))
                $updateResponse | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $responsePath -Encoding UTF8
                Write-Log "Updated: $target" "SUCCESS"
            }
            catch {
                $result.Status = "Error"
                $result.Message = $_.Exception.Message
                Write-Log "Failed: $target - $($_.Exception.Message)" "ERROR"
            }
        }
        else {
            $result.Status = "WhatIf"
            $result.Message = "No update sent because ShouldProcess declined."
            Write-Log "WhatIf: $Action policy $target"
        }

        [void]$results.Add([pscustomobject]$result)
        if ($DelayMilliseconds -gt 0) { Start-Sleep -Milliseconds $DelayMilliseconds }
    }

    $resultRows = @($results)
    $resultRows | Export-Csv -LiteralPath $resultsCsvPath -NoTypeInformation -Encoding UTF8 -Force
    $resultRows | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resultsJsonPath -Encoding UTF8

    Write-LogSection "SUMMARY"
    Write-Log "Selected policies: $($selectedPolicies.Count)"
    Write-Log "Success: $(($resultRows | Where-Object Status -eq 'Success').Count)"
    Write-Log "Errors: $(($resultRows | Where-Object Status -eq 'Error').Count)"
    Write-Log "Results CSV: $resultsCsvPath"
    Write-Log "Results JSON: $resultsJsonPath"
    $resultRows
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}
