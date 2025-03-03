<# USER CONFIG ###############################################################################>
$Hostname = "https://api.crowdstrike.com"
$ClientId = '3df02b4507b443fc8cc76538bd226fb8'
$ClientSecret = 'bho3VI0GYNp6SynuwjzBJx9P2dD1ULXMm84a75gc'
<############################################################################### USER CONFIG #>
function Invoke-Falcon ($Param) {
    try {
        $Client = [System.Net.Http.HttpClient]::New()
        $Request = [System.Net.Http.HttpRequestMessage]::New($Param.Method, "$($Hostname)$($Param.Path)")
        ($Param.Headers).GetEnumerator().foreach{
            $Request.Headers.Add($_.Key, $_.Value)
        }
        $Request.Content = [System.Net.Http.StringContent]::New($Param.Body, [System.Text.Encoding]::UTF8,
            $Param.Headers.ContentType)
        $Response = $Client.SendAsync($Request)
        if ($Response.Result.Content) {
            if ($Param.Headers.Accept -eq 'application/json') {
                ConvertFrom-Json ($Response.Result.Content).ReadAsStringAsync().Result
            } else {
                ($Response.Result.Content).ReadAsStringAsync().Result
            }
        } else {
            $Response.Result.StatusCode
        }
    } catch {
        throw $_
    } finally {
        if ($Response.Result.Headers.Key -contains 'X-Ratelimit-RetryAfter') {
            $RetryAfter = $Response.Result.Headers.GetEnumerator().Where({
                $_.Key -eq 'X-Ratelimit-RetryAfter' }).Value
            Start-Sleep -Seconds ($RetryAfter - ([int] (Get-Date -UFormat %s) + 1))
        }
        if ($Response) {
            $Response.Dispose()
        }
    }
}
if ($PSVersionTable.PSVersion.Major -lt 6) {
    Add-Type -AssemblyName System.Net.Http
}
try {
    $HostId = ([System.BitConverter]::ToString(((Get-ItemProperty ("HKLM:\SYSTEM\CrowdStrike\" +
        "{9b03c1d9-3138-44ed-9fae-d9f4c034b88d}\{16e0423f-7058-48c9-a204-725362b67639}" +
        "\Default") -Name AG).AG)).ToLower() -replace '-','')
    if (-not $HostId) {
        throw "Unable to retrieve Host identifier"
    }
    $UninstallString = (Get-ChildItem @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') | Where-Object {
        $_.GetValue('DisplayName') -eq 'CrowdStrike Windows Sensor' }).GetValue('QuietUninstallString')
    if (-not $UninstallString) {
        throw "No 'QuietUninstallString' found for 'CrowdStrike Windows Sensor'"
    }
    if (-not($ClientId -or $ClientSecret)) {
        throw "Missing API credentials"
    }
    $Param = @{
        Path = "/oauth2/token"
        Method = 'post'
        Headers = @{
            Accept = 'application/json'
            ContentType = 'application/x-www-form-urlencoded'
        }
        Body = "client_id=$ClientId&client_secret=$ClientSecret"
    }
    $Token = Invoke-Falcon $Param
    if (-not $Token.access_token) {
        throw "Authorization token request failed:rn$($Token.errors | ConvertTo-Json)"
    }
    $Param = @{
        Path = "/policy/combined/reveal-uninstall-token/v1"
        Method = 'post'
        Headers = @{
            Accept = 'application/json'
            ContentType = 'application/json'
            Authorization = "$($Token.token_type) $($Token.access_token)"
        }
        Body = @{
            audit_message = 'UninstallFalcon Real-Time Response Script'
            device_id = $HostId
        } | ConvertTo-Json
    }
    $Request = Invoke-Falcon $Param
    if ($Request.resources.uninstall_token) {
        $ArgumentList = "/c $UninstallString MAINTENANCE_TOKEN=$($Request.resources.uninstall_token)"
    } else {
        throw "Uninstall token request failed:rn$($Request.errors | ConvertTo-Json)"
    }
    (Start-Process -FilePath cmd.exe -ArgumentList $ArgumentList -PassThru).foreach{
        "[$($_.Id)] $($_.ProcessName): Started removal of 'CrowdStrike Windows Sensor'"
    }
} catch {
    Write-Error $_
}