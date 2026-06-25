#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$BaseUrl = "https://epm18-test-a706571.epm.us2.oraclecloud.com",
    [Parameter(Mandatory)]
    [string]$JsonPath,
    [string]$Folder = "epm18-test",
    [string]$RegressionRoot = "C:\RegressionTesting",
    [string]$ProjectRoot,
    [string]$RunLabel,
    [ValidateSet("Normal", "SCU")]
    [string]$RunType = "Normal",
    [string]$RunsRoot,
    [string]$CmsSecretPath = "C:\Russ\Creds\rs.epm_credentials.cms",
    [string]$CertThumbprint = "",
    [string]$CertSubject = "CN=OracleEpmSecret",
    [string]$CertStoreLocation = "Cert:\LocalMachine\My"
)

$ErrorActionPreference = "Stop"
$script:LogFile = $null
$ProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { Join-Path $RegressionRoot $Folder } else { $ProjectRoot }

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
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Label
    )
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safeLabel = ($Label -replace '[^a-zA-Z0-9_.-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeLabel)) { $safeLabel = "rest" }
    $path = Join-Path $Root "$safeLabel`_$stamp"
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Resolve-RunsRoot {
    param(
        [string]$Root,
        [string]$Type
    )
    if (-not [string]::IsNullOrWhiteSpace($Root)) {
        return $Root
    }

    if ($Type -eq "SCU") {
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

function Get-JsonOperations {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { throw "JSON input not found: $Path" }
    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    return $json
}

function Join-Endpoint {
    param([string]$Base, [string]$Path)
    $baseClean = $Base.TrimEnd("/")
    if ($Path -match '^https?://') { return $Path }
    $pathClean = $Path.TrimStart("/")
    return "$baseClean/$pathClean"
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $Value | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $Path -Encoding UTF8
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
        ErrorAction = 'Stop'
        UseBasicParsing = $true
    }

    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        if ($Body -is [string]) {
            $params.Body = $Body
        } else {
            $params.Body = ($Body | ConvertTo-Json -Depth 80 -Compress)
        }
    }

    $response = Invoke-WebRequest @params
    $parsedBody = $null
    if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
        try {
            $parsedBody = $response.Content | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $parsedBody = $response.Content
        }
    }

    return [pscustomobject]@{
        StatusCode = [int]$response.StatusCode
        Headers = $response.Headers
        Body = $parsedBody
        RawBody = $response.Content
    }
}

$payload = Get-JsonOperations -Path $JsonPath
$labelFromJson = [string]$payload.runLabel
if ([string]::IsNullOrWhiteSpace($RunLabel)) {
    $RunLabel = if (-not [string]::IsNullOrWhiteSpace($labelFromJson)) { $labelFromJson } else { [System.IO.Path]::GetFileNameWithoutExtension($JsonPath) }
}

$runsRoot = Resolve-RunsRoot -Root $RunsRoot -Type $RunType
if (-not (Test-Path -LiteralPath $runsRoot)) {
    New-Item -ItemType Directory -Path $runsRoot -Force | Out-Null
}

$runFolder = New-RunFolder -Root $runsRoot -Label $RunLabel
$script:LogFile = Join-Path $runFolder "run.log"
$requestDir = Join-Path $runFolder "requests"
$responseDir = Join-Path $runFolder "responses"
$downloadDir = Join-Path $runFolder "downloads"
$auditDir = Join-Path $runFolder "audit"
foreach ($dir in @($requestDir, $responseDir, $downloadDir, $auditDir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

try {
    Write-Log "Run folder: $runFolder"
    Write-Log "Run type: $RunType"
    Write-Log "Base URL: $BaseUrl"
    Write-Log "JSON input: $JsonPath"

    $cert = Get-CmsDecryptionCert -Thumbprint $CertThumbprint -Subject $CertSubject -StorePath $CertStoreLocation
    Write-Log "Using CMS certificate: Subject='$($cert.Subject)' Thumbprint=$($cert.Thumbprint)" "SUCCESS"
    $secret = Get-CmsCredentialObject -Path $CmsSecretPath -Certificate $cert
    Write-Log "Authentication initialized for Oracle EPM user '$($secret.UserName)'" "SUCCESS"
    $headers = New-BasicAuthHeaders -CredentialObject $secret

    $operations = @()
    if ($payload.PSObject.Properties.Name -contains 'operations') {
        $operations = @($payload.operations)
    } elseif ($payload.PSObject.Properties.Name -contains 'items') {
        $operations = @($payload.items)
    } else {
        throw "JSON input must contain an 'operations' or 'items' array."
    }

    $results = New-Object System.Collections.ArrayList
    $index = 0
    foreach ($op in $operations) {
        $index++
        $opName = [string](if ($op.PSObject.Properties.Name -contains 'name') { $op.name } elseif ($op.PSObject.Properties.Name -contains 'operationName') { $op.operationName } else { "operation_$index" })
        $method = [string](if ($op.PSObject.Properties.Name -contains 'method') { $op.method } elseif ($op.PSObject.Properties.Name -contains 'httpMethod') { $op.httpMethod } else { 'GET' })
        $endpoint = [string](if ($op.PSObject.Properties.Name -contains 'endpoint') { $op.endpoint } elseif ($op.PSObject.Properties.Name -contains 'path') { $op.path } else { '' })
        if ([string]::IsNullOrWhiteSpace($endpoint)) { throw "Operation '$opName' is missing endpoint/path." }

        $uri = Join-Endpoint -Base $BaseUrl -Path $endpoint
        $requestPath = Join-Path $requestDir ("{0:00}_{1}.request.json" -f $index, ($opName -replace '[^a-zA-Z0-9_.-]+', '_'))
        $responsePath = Join-Path $responseDir ("{0:00}_{1}.response.json" -f $index, ($opName -replace '[^a-zA-Z0-9_.-]+', '_'))
        $auditPath = Join-Path $auditDir ("{0:00}_{1}.audit.json" -f $index, ($opName -replace '[^a-zA-Z0-9_.-]+', '_'))
        $summaryRow = [ordered]@{
            Index = $index
            Name = $opName
            Method = $method
            Uri = $uri
            Status = 'Pending'
            HttpStatus = $null
            Message = $null
            AuditVerified = $false
        }

        try {
            Write-Log "[$index/$($operations.Count)] $method $uri"
            if ($op.PSObject.Properties.Name -contains 'requestBody') {
                Write-JsonFile -Path $requestPath -Value $op.requestBody
            } elseif ($op.PSObject.Properties.Name -contains 'body') {
                Write-JsonFile -Path $requestPath -Value $op.body
            } else {
                Write-JsonFile -Path $requestPath -Value $op
            }

            $requestBody = $null
            if ($method -ne 'GET') {
                if ($op.PSObject.Properties.Name -contains 'requestBody') {
                    $requestBody = $op.requestBody
                } elseif ($op.PSObject.Properties.Name -contains 'body') {
                    $requestBody = $op.body
                }
            }

            $response = Invoke-JsonRest -Uri $uri -Method $method -Headers $headers -Body $requestBody
            Write-JsonFile -Path $responsePath -Value $response.Body
            $summaryRow.Status = 'Success'
            $summaryRow.HttpStatus = $response.StatusCode
            $summaryRow.Message = 'Completed'

            if ($op.PSObject.Properties.Name -contains 'auditEndpoint' -and -not [string]::IsNullOrWhiteSpace([string]$op.auditEndpoint)) {
                $auditUri = Join-Endpoint -Base $BaseUrl -Path [string]$op.auditEndpoint
                Write-Log "Downloading audit records from $auditUri"
                $auditResponse = Invoke-JsonRest -Uri $auditUri -Method GET -Headers $headers
                Write-JsonFile -Path $auditPath -Value $auditResponse.Body
                $summaryRow.AuditVerified = $true

                if ($RunType -eq 'SCU') {
                    $notificationConfig = $null
                    if ($payload.PSObject.Properties.Name -contains 'notification') {
                        $notificationConfig = $payload.notification
                    }

                    $notificationText = $null
                    if ($op.PSObject.Properties.Name -contains 'notificationText') {
                        $notificationText = [string]$op.notificationText
                    } elseif ($notificationConfig) {
                        foreach ($candidate in @('text', 'message', 'notificationText', 'value')) {
                            if ($notificationConfig.PSObject.Properties.Name -contains $candidate) {
                                $notificationText = [string]$notificationConfig.$candidate
                                break
                            }
                        }
                    } elseif ($payload.PSObject.Properties.Name -contains 'notificationText') {
                        $notificationText = [string]$payload.notificationText
                    }
                    if ($notificationText) {
                        Set-Content -LiteralPath (Join-Path $runFolder 'notification.txt') -Value $notificationText -Encoding UTF8
                        if ($notificationText -match '(?i)\b(fail|failed|error)\b') {
                            throw "SCU notification indicates failure: $notificationText"
                        }
                        if ($notificationText -notmatch '(?i)\b(pass|passed|success|succeeded)\b') {
                            Write-Log "Notification text did not clearly indicate pass/fail." 'WARNING'
                        }
                    }

                    $auditIgnoreOpenForm = $false
                    if ($payload.PSObject.Properties.Name -contains 'audit' -and $payload.audit) {
                        if ($payload.audit.PSObject.Properties.Name -contains 'ignoreOpenForm') {
                            $auditIgnoreOpenForm = [bool]$payload.audit.ignoreOpenForm
                        }
                    }

                    $auditText = ($auditResponse | ConvertTo-Json -Depth 80 -Compress)
                    if ($auditIgnoreOpenForm -and $auditText -match '(?i)OpenForm') {
                        Write-Log "Skipping OpenForm audit matches per rule." 'INFO'
                    }
                }
            }
        }
        catch {
            $summaryRow.Status = 'Failed'
            $summaryRow.Message = $_.Exception.Message
            Write-Log "Operation failed: $opName - $($_.Exception.Message)" 'ERROR'
        }

        [void]$results.Add([pscustomobject]$summaryRow)
    }

    $summaryPath = Join-Path $runFolder 'summary.json'
    $csvPath = Join-Path $runFolder 'summary.csv'
    $results | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    $results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -Force

    Write-Log "Summary written to $summaryPath" 'SUCCESS'
    Write-Log "Summary CSV written to $csvPath" 'SUCCESS'
    $results
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    throw
}
