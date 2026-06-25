#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$BaseUrl = "https://epm18-test-a706571.epm.us2.oraclecloud.com",
    [string]$RunsDirectory = "C:\RegressionTesting\epm18-test\Runs",
    [string]$CmsSecretPath = "C:\Russ\Creds\rs.epm_credentials.cms",
    [string]$CertThumbprint = "",
    [string]$CertSubject = "CN=OracleEpmSecret"
)

$scriptPath = Join-Path $PSScriptRoot "Invoke-Epm18RestTemplate.ps1"
& $scriptPath `
    -BaseUrl $BaseUrl `
    -Endpoint "epm/rest/v1/views" `
    -Method GET `
    -RunsDirectory $RunsDirectory `
    -RunLabel "views" `
    -CmsSecretPath $CmsSecretPath `
    -CertThumbprint $CertThumbprint `
    -CertSubject $CertSubject
