param(
    [string]$BaseUrl = "https://epm-novedm.epm.us6.oraclecloud.com",
    [string]$ViewCsvPath = "C:\EDM\novedm\Views\EPM_Views_Data_20260518_170315.csv",
    [string]$OutputDirectory = "C:\EDM\novedm\Views",
    [string]$CmsSecretPath = "C:\Russ\Creds\rs.epm_credentials_novedm.cms",
    [string]$CertThumbprint = "28F7F30E9E0B6F09081744EF8D298EB1D1E38736",
    [string]$CertSubject = "CN=OracleEpmSecretnovedm",
    [string]$CertStoreLocation = "Cert:\LocalMachine\My"
)

$ErrorActionPreference = 'Stop'
$script:LogFilePath = $null

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','SUCCESS','WARNING','ERROR','DEBUG')]
        [string]$Level = 'INFO'
    )
    if ([string]::IsNullOrWhiteSpace($Message)) { $Message = ' ' }
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    Write-Host $line
    if ($script:LogFilePath) { Add-Content -LiteralPath $script:LogFilePath -Value $line -Encoding UTF8 }
}

function Write-LogSection {
    param([string]$Title)
    Write-Log ' '
    Write-Log ('=' * 80)
    Write-Log $Title
    Write-Log ('=' * 80)
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
    Write-Log 'Loading CMS certificate...' 'INFO'
    $cert = Get-CmsDecryptionCert -Thumbprint $CertThumbprint -Subject $CertSubject -StorePath $CertStoreLocation
    Write-Log "Using CMS certificate: Subject='$($cert.Subject)' Thumbprint=$($cert.Thumbprint)" 'SUCCESS'

    Write-Log 'Loading CMS secret file...' 'INFO'
    $secret = Get-CmsCredentialObject -Path $CmsSecretPath -Certificate $cert
    Write-Log "Authentication initialized for Oracle EPM user '$($secret.UserName)'" 'SUCCESS'

    $authPair = "{0}:{1}" -f $secret.UserName, $secret.Password
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($authPair))
    return @{
        Authorization = "Basic $auth"
        'Content-Type' = 'application/json'
        Accept = 'application/json'
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

function Get-NestedName {
    param([object]$Object)
    if ($null -eq $Object) { return $null }
    if ($Object -is [string]) { return $Object }
    if ($Object.PSObject.Properties.Name -contains 'name') { return $Object.name }
    if ($Object.PSObject.Properties.Name -contains 'Name') { return $Object.Name }
    return ($Object | ConvertTo-Json -Depth 5 -Compress)
}

function Convert-ViewpointToFlatObject {
    param([object]$ViewRow, [object]$Viewpoint)

    $links = Get-FirstPropertyValue -Object $Viewpoint -Names @('links','Links')
    $selfLink = $null
    if ($links) {
        $selfLink = (@($links) | Where-Object { $_.rel -eq 'self' -or $_.rel -eq 'Self' } | Select-Object -First 1).href
        if (-not $selfLink) { $selfLink = (@($links) | Select-Object -First 1).href }
    }

    [pscustomobject]@{
        View_ID = $ViewRow.View_ID
        View_Name = $ViewRow.View_Name
        View_Object_Status = $ViewRow.Object_Status
        Viewpoint_ID = Get-FirstPropertyValue -Object $Viewpoint -Names @('id','ID')
        Viewpoint_Name = Get-FirstPropertyValue -Object $Viewpoint -Names @('name','Name')
        Description = Get-FirstPropertyValue -Object $Viewpoint -Names @('description','Description')
        Object_Status = Get-FirstPropertyValue -Object $Viewpoint -Names @('objectStatus','Object_Status','status','Status')
        Time_Created = Get-FirstPropertyValue -Object $Viewpoint -Names @('timeCreated','Time_Created')
        Time_Modified = Get-FirstPropertyValue -Object $Viewpoint -Names @('timeModified','Time_Modified')
        Created_By = Get-FirstPropertyValue -Object $Viewpoint -Names @('createdBy','Created_By')
        Modified_By = Get-FirstPropertyValue -Object $Viewpoint -Names @('modifiedBy','Modified_By')
        Application = Get-NestedName (Get-FirstPropertyValue -Object $Viewpoint -Names @('application','Application'))
        Dimension = Get-NestedName (Get-FirstPropertyValue -Object $Viewpoint -Names @('dimension','Dimension'))
        Node_Set = Get-NestedName (Get-FirstPropertyValue -Object $Viewpoint -Names @('nodeSet','NodeSet','nodeSetName'))
        Hierarchy_Set = Get-NestedName (Get-FirstPropertyValue -Object $Viewpoint -Names @('hierarchySet','HierarchySet','hierarchySetName'))
        Node_Type = Get-NestedName (Get-FirstPropertyValue -Object $Viewpoint -Names @('nodeType','NodeType','nodeTypeName'))
        Permitted_Actions = (@(Get-FirstPropertyValue -Object $Viewpoint -Names @('permittedActions','Permitted_Actions')) -join ', ')
        Self_Link = $selfLink
    }
}

function Export-ToExcel {
    param([array]$Data, [string]$Path)
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Log 'ImportExcel module not found; Excel export skipped.' 'WARNING'
        return $false
    }
    Import-Module ImportExcel -ErrorAction Stop
    $Data | Export-Excel -Path $Path -WorksheetName 'EDM_Viewpoints' -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -TableName 'EDMViewpoints' -TableStyle Medium6 -ClearSheet
    return $true
}

function Main {
    $start = Get-Date
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }

    $script:LogFilePath = Join-Path $OutputDirectory "EDM_Viewpoints_Export_$timestamp.log"
    $csvOut = Join-Path $OutputDirectory "EDM_Viewpoints_Data_$timestamp.csv"
    $xlsxOut = Join-Path $OutputDirectory "EDM_Viewpoints_Data_$timestamp.xlsx"

    Write-LogSection 'SCRIPT INITIALIZATION'
    Write-Log 'EDM Viewpoints Export Script'
    Write-Log "View CSV: $ViewCsvPath"
    Write-Log "Base URL: $BaseUrl"
    Write-Log "CSV output: $csvOut"
    Write-Log "Excel output: $xlsxOut"

    if (-not (Test-Path -LiteralPath $ViewCsvPath)) { throw "Views CSV not found: $ViewCsvPath" }
    $views = @(Import-Csv -LiteralPath $ViewCsvPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_.View_ID) })
    Write-Log "Views loaded: $($views.Count)"

    Write-LogSection 'AUTHENTICATION'
    $headers = Initialize-EpmAuth

    Write-LogSection 'API REQUESTS'
    $allRows = New-Object System.Collections.ArrayList
    $viewIndex = 0
    foreach ($view in $views) {
        $viewIndex++
        $viewId = [uri]::EscapeDataString($view.View_ID)
        $url = "$BaseUrl/epm/rest/v1/views/$viewId/viewpoints"
        Write-Log ("[{0}/{1}] View '{2}' ({3})" -f $viewIndex, $views.Count, $view.View_Name, $view.View_ID) 'INFO'
        try {
            $response = Invoke-RestMethod -Uri $url -Method GET -Headers $headers -ErrorAction Stop
            $items = @($response.items)
            Write-Log "  Viewpoints found: $($items.Count)" 'SUCCESS'
            foreach ($vp in $items) { [void]$allRows.Add((Convert-ViewpointToFlatObject -ViewRow $view -Viewpoint $vp)) }
        }
        catch {
            Write-Log "  Failed: $($_.Exception.Message)" 'ERROR'
            [void]$allRows.Add([pscustomobject]@{
                View_ID = $view.View_ID; View_Name = $view.View_Name; View_Object_Status = $view.Object_Status
                Viewpoint_ID = $null; Viewpoint_Name = $null; Description = $null; Object_Status = 'ERROR'
                Time_Created = $null; Time_Modified = $null; Created_By = $null; Modified_By = $null
                Application = $null; Dimension = $null; Node_Set = $null; Hierarchy_Set = $null; Node_Type = $null
                Permitted_Actions = $null; Self_Link = $null
            })
        }
    }

    $data = @($allRows)
    Write-LogSection 'EXPORT'
    Write-Log "Total viewpoint rows: $($data.Count)"
    $data | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding UTF8 -Force
    Write-Log "CSV export complete: $csvOut" 'SUCCESS'
    $excelOk = Export-ToExcel -Data $data -Path $xlsxOut
    if ($excelOk) { Write-Log "Excel export complete: $xlsxOut" 'SUCCESS' }

    Write-LogSection 'SUMMARY'
    Write-Log "Views processed: $($views.Count)"
    Write-Log "Viewpoint rows exported: $($data.Count)"
    Write-Log ("Execution time: {0:n2} seconds" -f ((Get-Date) - $start).TotalSeconds)
    Write-Log "Log file: $script:LogFilePath"
    return $data
}

Main