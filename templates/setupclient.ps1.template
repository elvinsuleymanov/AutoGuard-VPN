#Requires -RunAsAdministrator

$ServerPublicIp = "PLACEHOLDER_SERVER_PUBLIC_IP"
$InterfaceName  = "PLACEHOLDER_INTERFACE_NAME"
$AuthKey        = "PLACEHOLDER_AUTH_KEY"

$WgExe        = "C:\Program Files\WireGuard\wg.exe"
$WgGui        = "C:\Program Files\WireGuard\wireguard.exe"
$ConfigDir    = "C:\ProgramData\WireGuard"
$GuiConfigDir = "C:\Program Files\WireGuard\Data\Configurations"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}

function CheckWireGuard {
    if (Test-Path $WgExe) { return }
    Write-Host "WireGuard not found. Installing via winget..." -ForegroundColor Yellow
    try {
        winget install -e --id WireGuard.WireGuard --silent --accept-package-agreements --accept-source-agreements
        if (!(Test-Path $WgExe)) { throw }
    } catch {
        Write-Host "Install failed. Download from https://www.wireguard.com/install/ and re-run." -ForegroundColor Red
        exit 1
    }
}

function FindExistingTunnel {
    if (!(Test-Path $ConfigDir)) { return $null }
    foreach ($file in Get-ChildItem "$ConfigDir\*.conf" -ErrorAction SilentlyContinue) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match ("Endpoint\s*=\s*" + [regex]::Escape($ServerPublicIp) + "\s*:")) {
            return $file.BaseName
        }
    }
    return $null
}

function PickUniqueName($Preferred) {
    $name = $Preferred
    $i = 2
    while (
        (Test-Path "$ConfigDir\$name.conf") -or
        (Test-Path "$GuiConfigDir\$name.conf.dpapi") -or
        (Get-Service -Name "WireGuardTunnel`$$name" -ErrorAction SilentlyContinue)
    ) {
        $name = "${Preferred}${i}"
        $i++
    }
    return $name
}

function GenerateKeypair {
    $priv = & $WgExe genkey
    $pub  = $priv | & $WgExe pubkey
    @{ Private = $priv; Public = $pub }
}

function RegisterPeer($PublicKey) {
    $body    = @{ public_key = $PublicKey } | ConvertTo-Json -Compress
    $headers = @{ "X-Auth-Token" = $AuthKey; "Content-Type" = "application/json" }
    $uri     = "https://$ServerPublicIp/addnewpeer"

    $params = @{ Uri = $uri; Method = "POST"; Headers = $headers; Body = $body }
    if ($PSVersionTable.PSVersion.Major -ge 7) { $params["SkipCertificateCheck"] = $true }

    try { Invoke-RestMethod @params }
    catch { Write-Host "Registration failed: $_" -ForegroundColor Red; exit 1 }
}

function WriteConfig($Config, $PrivateKey, $Path) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
    $Config = $Config -replace "<PASTE_YOUR_PRIVATE_KEY_HERE>", $PrivateKey
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Config, $utf8NoBom)
    icacls $Path /inheritance:r /grant:r "SYSTEM:(F)" /grant:r "Administrators:(F)" | Out-Null
}

function StripBomIfPresent($Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        [System.IO.File]::WriteAllBytes($Path, $bytes[3..($bytes.Length - 1)])
    }
}

function VerifyHandshake($Name) {
    Write-Host "Verifying handshake (up to 15s)..." -ForegroundColor Cyan
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        $line = & $WgExe show $Name latest-handshakes 2>$null | Select-Object -First 1
        if ($line) {
            $epoch = ($line -split '\s+')[-1]
            if ($epoch -match '^\d+$' -and [int64]$epoch -gt 0) { return $true }
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "   AUTOGUARD VPN CLIENT SETUP                   " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

CheckWireGuard

$existing = FindExistingTunnel
if ($existing) {
    Write-Host "AutoGuard tunnel '$existing' already configured for $ServerPublicIp." -ForegroundColor Yellow
    $confPath = "$ConfigDir\$existing.conf"
    StripBomIfPresent $confPath

    $svcName = "WireGuardTunnel`$$existing"
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $svc) {
        & $WgGui /installtunnelservice $confPath
        Start-Sleep -Seconds 2
    } elseif ($svc.Status -ne "Running") {
        try { Start-Service -Name $svcName -ErrorAction Stop }
        catch { Write-Host "Could not start service: $_" -ForegroundColor Yellow }
    }

    if (-not (VerifyHandshake $existing)) {
        Write-Host "Handshake never completed for '$existing'." -ForegroundColor Red
        Write-Host "Stopping the tunnel so it doesn't blackhole your internet." -ForegroundColor Yellow
        Stop-Service $svcName -ErrorAction SilentlyContinue
        Write-Host "Check server-side: docker exec wireguard wg show wg0" -ForegroundColor Yellow
        exit 1
    }

    Start-Process $WgGui
    Write-Host "Tunnel '$existing' is active. Toggle it from the WireGuard GUI." -ForegroundColor Green
    exit 0
}

$InterfaceName = PickUniqueName $InterfaceName

Write-Host "Generating keypair..." -ForegroundColor Cyan
$Keys = GenerateKeypair

Write-Host "Registering with $ServerPublicIp..." -ForegroundColor Cyan
$Response = RegisterPeer -PublicKey $Keys.Public
if ($Response.status -ne "ok") {
    Write-Host "Server rejected: $($Response | ConvertTo-Json)" -ForegroundColor Red
    exit 1
}
Write-Host "Assigned IP: $($Response.ip)" -ForegroundColor Green

$ConfigPath = "$ConfigDir\$InterfaceName.conf"
WriteConfig -Config $Response.config -PrivateKey $Keys.Private -Path $ConfigPath
Write-Host "Config written to $ConfigPath" -ForegroundColor Green

Write-Host "Adding tunnel '$InterfaceName' to WireGuard..." -ForegroundColor Cyan
& $WgGui /installtunnelservice $ConfigPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "Install failed (exit $LASTEXITCODE)." -ForegroundColor Red
    exit 1
}

Start-Sleep -Seconds 2

if (-not (VerifyHandshake $InterfaceName)) {
    Write-Host "Tunnel installed but handshake never completed." -ForegroundColor Red
    Write-Host "Stopping the tunnel so it doesn't blackhole your internet." -ForegroundColor Yellow
    Stop-Service "WireGuardTunnel`$$InterfaceName" -ErrorAction SilentlyContinue
    Write-Host "On the server run: docker exec wireguard wg show wg0" -ForegroundColor Yellow
    Write-Host "Your peer pubkey: $($Keys.Public)" -ForegroundColor Yellow
    Write-Host "If it's missing from that output, the server-side peer-watcher didn't load your peer." -ForegroundColor Yellow
    exit 1
}

Start-Process $WgGui
Write-Host "VPN '$InterfaceName' is configured, handshake completed, traffic flowing." -ForegroundColor Green
Write-Host "From now on, toggle on/off from the WireGuard GUI." -ForegroundColor Green
