# ============================================================================
# EPM Request Lineage API Export
# Server-friendly CMS-authenticated export script.
# ============================================================================

[CmdletBinding()]
param(
    [string]$BaseUrl = "https://epm20-test-a706571.epm.us2.oraclecloud.com",
    [string]$RequestId = "5d4547db-17f3-40d9-93c8-37fd3154b66a",
    [string]$OutputRoot = "C:\EDM\LineageRuns",
    [ValidateSet("CSV","Excel","Both")]
    [string]$ExportFormat = "Both",
    [string]$CmsSecretPath = "C:\Russ\Creds\rs.epm_credentials.cms",
    [string]$CertThumbprint = "94621577083C8E4F49C68C81D0B9FCB3FFA704EB",
    [string]$CertSubject = "CN=OracleEpmSecret",
    [string]$CertStoreLocation = "Cert:\LocalMachine\My"
)

$ErrorActionPreference = 'Stop'
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

function Write-Section {
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
        catch { $cert = Get-ChildItem -Path $StorePath -ErrorAction Stop | Where-Object { $_.Thumbprint -eq $tp } | Select-Object -First 1 }
        if (-not $cert) { throw "No certificate with thumbprint '$tp' found in $StorePath" }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Subject)) {
        $cert = Get-ChildItem -Path $StorePath -ErrorAction Stop |
            Where-Object { ($_.Subject -eq $Subject) -or ($_.Subject -like "*$Subject*") -or ($_.FriendlyName -eq $Subject) } |
            Sort-Object NotAfter -Descending |
            Select-Object -First 1
        if (-not $cert) { throw "No certificate matching '$Subject' found in $StorePath" }
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
    $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string]$obj.UserName)) { throw 'CMS secret JSON missing UserName' }
    if ([string]::IsNullOrWhiteSpace([string]$obj.Password)) { throw 'CMS secret JSON missing Password' }
    return [pscustomobject]@{ UserName = [string]$obj.UserName; Password = [string]$obj.Password }
}

function Initialize-EpmAuth {
    Write-Log 'Loading CMS certificate...'
    $cert = Get-CmsDecryptionCert -Thumbprint $CertThumbprint -Subject $CertSubject -StorePath $CertStoreLocation
    Write-Log "Using CMS certificate: Subject='$($cert.Subject)' Thumbprint=$($cert.Thumbprint) Store='$CertStoreLocation'" 'SUCCESS'
    Write-Log 'Decrypting CMS secret...'
    $secret = Get-CmsCredentialObject -Path $CmsSecretPath -Certificate $cert
    $authPair = "{0}:{1}" -f $secret.UserName, $secret.Password
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($authPair))
    Write-Log "Authentication initialized for Oracle EPM user '$($secret.UserName)'" 'SUCCESS'
    return @{
        'Authorization' = "Basic $auth"
        'Content-Type' = 'application/json'
        'Accept' = 'application/json'
    }
}

function Format-LineageNodesForExport {
    param([array]$Nodes)
    foreach ($node in $Nodes) {
        $viewpointNames = if ($node.viewpoints) { ($node.viewpoints | ForEach-Object { $_.name }) -join '; ' } else { '' }
        $viewpointCount = if ($node.viewpoints) { @($node.viewpoints).Count } else { 0 }
        $incompleteCount = if ($node.incompleteSubscriptions) { @($node.incompleteSubscriptions).Count } else { 0 }
        $sourceRequestName = if ($node.sourceRequest) { $node.sourceRequest.name } else { 'N/A (Origin)' }
        [pscustomobject]@{
            'Request ID' = $node.id
            'Title' = $node.title
            'Origin' = $node.origin
            'Status' = $node.status
            'Auto Submitted' = $node.autoSubmitted
            'Time Created' = $node.timeCreated
            'Source Request' = $sourceRequestName
            'Viewpoint Count' = $viewpointCount
            'Viewpoints' = $viewpointNames
            'Incomplete Subscriptions' = $incompleteCount
        }
    }
}

function Format-SubscriptionsForExport {
    param([array]$Nodes)
    foreach ($node in $Nodes) {
        if ($node.incompleteSubscriptions) {
            foreach ($sub in $node.incompleteSubscriptions) {
                [pscustomobject]@{
                    'Parent Request ID' = $node.id
                    'Parent Request Title' = $node.title
                    'Subscription ID' = $sub.id
                    'Subscription Name' = $sub.name
                    'Description' = $sub.description
                    'Source Viewpoint' = if ($sub.sourceViewpoint) { $sub.sourceViewpoint.name } else { '' }
                    'Target Viewpoint' = if ($sub.targetViewpoint) { $sub.targetViewpoint.name } else { '' }
                    'Status' = $sub.subscriptionStatus
                    'Message' = $sub.message
                    'Errors' = if ($sub.errors) { $sub.errors -join '; ' } else { '' }
                }
            }
        }
    }
}

function Export-LineageCsv {
    param([array]$LineageNodes,[string]$RunFolder,[string]$Timestamp)
    $lineagePath = Join-Path $RunFolder "EPM_Lineage_Export_$Timestamp.csv"
    $subscriptionPath = Join-Path $RunFolder "EPM_Lineage_Export_${Timestamp}_Subscriptions.csv"
    $lineageData = @(Format-LineageNodesForExport -Nodes $LineageNodes)
    $subscriptionData = @(Format-SubscriptionsForExport -Nodes $LineageNodes)
    $lineageData | Export-Csv -LiteralPath $lineagePath -NoTypeInformation -Encoding UTF8 -Force
    Write-Log "CSV lineage export: $lineagePath" 'SUCCESS'
    if ($subscriptionData.Count -gt 0) {
        $subscriptionData | Export-Csv -LiteralPath $subscriptionPath -NoTypeInformation -Encoding UTF8 -Force
        Write-Log "CSV subscriptions export: $subscriptionPath" 'SUCCESS'
    }
    return [pscustomobject]@{ LineageCsv = $lineagePath; SubscriptionCsv = if ($subscriptionData.Count -gt 0) { $subscriptionPath } else { $null } }
}

function Export-LineageExcel {
    param([array]$LineageNodes,[string]$RunFolder,[string]$Timestamp)
    $excelPath = Join-Path $RunFolder "EPM_Lineage_Export_$Timestamp.xlsx"
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Log 'ImportExcel module not found; Excel export skipped.' 'WARNING'
        return $null
    }
    Import-Module ImportExcel -ErrorAction Stop
    $lineageData = @(Format-LineageNodesForExport -Nodes $LineageNodes)
    $subscriptionData = @(Format-SubscriptionsForExport -Nodes $LineageNodes)
    $lineageData | Export-Excel -Path $excelPath -WorksheetName 'Lineage Nodes' -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -TableStyle Medium2 -ClearSheet
    if ($subscriptionData.Count -gt 0) {
        $subscriptionData | Export-Excel -Path $excelPath -WorksheetName 'Incomplete Subscriptions' -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -TableStyle Medium6 -Append
    }
    Write-Log "Excel lineage export: $excelPath" 'SUCCESS'
    return $excelPath
}

function Main {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    if (-not (Test-Path -LiteralPath $OutputRoot)) { New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null }
    $safeRequestId = $RequestId -replace '[^a-zA-Z0-9_-]', '_'
    $runFolder = Join-Path $OutputRoot "Lineage_${safeRequestId}_$timestamp"
    New-Item -ItemType Directory -Path $runFolder -Force | Out-Null
    $script:LogFile = Join-Path $runFolder "EPM_Lineage_Export_$timestamp.log"

    $base = $BaseUrl.TrimEnd('/')
    $apiUrl = "$base/epm/rest/v1/requests/$RequestId/lineage"

    Write-Section 'SCRIPT INITIALIZATION'
    Write-Log 'EPM Request Lineage API - Export Tool'
    Write-Log "BaseUrl: $base"
    Write-Log "RequestId: $RequestId"
    Write-Log "RunFolder: $runFolder"
    Write-Log "ExportFormat: $ExportFormat"

    Write-Section 'AUTHENTICATION'
    $headers = Initialize-EpmAuth

    Write-Section 'API REQUEST'
    Write-Log "GET $apiUrl"
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method GET -Headers $headers -ErrorAction Stop
    }
    catch {
        Write-Log "API request failed: $($_.Exception.Message)" 'ERROR'
        $body = Get-ErrorBodyText -ErrorRecord $_
        if ($body) { Write-Log "Response Body: $body" 'ERROR' }
        throw
    }

    $lineageNodes = @()
    if ($response.requestLineageNodes) { $lineageNodes = @($response.requestLineageNodes) }
    Write-Log "Lineage nodes retrieved: $($lineageNodes.Count)" 'SUCCESS'

    if ($lineageNodes.Count -eq 0) {
        Write-Log 'No lineage nodes found in response.' 'WARNING'
        return
    }

    $completedCount = @($lineageNodes | Where-Object { $_.status -eq 'COMPLETED' }).Count
    $otherCount = $lineageNodes.Count - $completedCount
    $totalViewpoints = ($lineageNodes | ForEach-Object { if ($_.viewpoints) { @($_.viewpoints).Count } else { 0 } } | Measure-Object -Sum).Sum
    $totalIncomplete = ($lineageNodes | ForEach-Object { if ($_.incompleteSubscriptions) { @($_.incompleteSubscriptions).Count } else { 0 } } | Measure-Object -Sum).Sum

    Write-Section 'RESPONSE SUMMARY'
    Write-Log "Completed nodes: $completedCount"
    Write-Log "Other status nodes: $otherCount"
    Write-Log "Total viewpoints: $totalViewpoints"
    Write-Log "Incomplete subscriptions: $totalIncomplete"

    Write-Section 'EXPORT'
    $csvResult = $null
    $excelPath = $null
    if ($ExportFormat -in @('CSV','Both')) { $csvResult = Export-LineageCsv -LineageNodes $lineageNodes -RunFolder $runFolder -Timestamp $timestamp }
    if ($ExportFormat -in @('Excel','Both')) { $excelPath = Export-LineageExcel -LineageNodes $lineageNodes -RunFolder $runFolder -Timestamp $timestamp }

    $summaryPath = Join-Path $runFolder "EPM_Lineage_Export_${timestamp}_Summary.csv"
    [pscustomobject]@{
        RunTimestamp = $timestamp
        BaseUrl = $base
        RequestId = $RequestId
        LineageNodeCount = $lineageNodes.Count
        CompletedNodeCount = $completedCount
        OtherStatusNodeCount = $otherCount
        TotalViewpoints = $totalViewpoints
        IncompleteSubscriptions = $totalIncomplete
        LineageCsv = if ($csvResult) { $csvResult.LineageCsv } else { $null }
        SubscriptionCsv = if ($csvResult) { $csvResult.SubscriptionCsv } else { $null }
        ExcelPath = $excelPath
        LogFile = $script:LogFile
    } | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8 -Force
    Write-Log "Summary export: $summaryPath" 'SUCCESS'

    Write-Section 'DONE'
    Write-Log "Run folder: $runFolder"
}

try { Main }
catch {
    Write-Section 'EXECUTION FAILED'
    Write-Log "Script failed: $($_.Exception.Message)" 'ERROR'
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" 'DEBUG'
    throw
}
