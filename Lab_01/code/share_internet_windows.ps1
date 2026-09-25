# =============================================================================
# RPi4 Lab 01 - Share your laptop's internet with the Pi over Ethernet  (WINDOWS)
# =============================================================================
#   [ Pi 4 ] --ethernet--> [ your laptop ] --wifi--> [ internet ]
#
# USAGE  - open PowerShell AS ADMINISTRATOR (right-click > Run as administrator)
#
#   powershell -ExecutionPolicy Bypass -File share_internet_windows.ps1
#   powershell -ExecutionPolicy Bypass -File share_internet_windows.ps1 -List
#   powershell -ExecutionPolicy Bypass -File share_internet_windows.ps1 -Undo
#
# TWO METHODS
#   ICS (default) - the built-in "Internet Connection Sharing". Works on every
#                   edition of Windows, but ALWAYS forces the gateway address
#                   to 192.168.137.1, so the Pi must use a 192.168.137.x
#                   static IP. You cannot change this - it is a Windows limit.
#   NAT           - uses New-NetNat. Lets you pick any subnet, but needs the
#                   Windows NAT driver (present when Hyper-V / WSL2 / Containers
#                   are enabled). Use this if you need a specific subnet.
# =============================================================================

param(
    [switch]$Undo,
    [switch]$List
)

# ----------------------------- SETTINGS --------------------------------------
# Run with -List to see the exact adapter names on your laptop.
$WanAdapter = "Wi-Fi"            # adapter WITH internet
$LanAdapter = "Ethernet"         # adapter TO THE Pi
$Method     = "ICS"              # "ICS" or "NAT"

# The standard for Windows laptops in this guide is the 192.168.137.x range, because ICS
# forces it and cannot be changed. The NAT method below uses the same range so
# both methods agree and the Pi's static IP never has to change.
$HostIP       = "192.168.137.1"      # this laptop's address = the Pi's GATEWAY
$LanSubnet    = "192.168.137.0/24"   # must match the Pi's static IP range
$PrefixLength = 24
$NatName      = "RobotShare"
# -----------------------------------------------------------------------------

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function OK   ($m) { Write-Host "    OK  $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "    !!  $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "`nERROR: $m`n" -ForegroundColor Red; exit 1 }

# ----------------------------- LIST ------------------------------------------
if ($List) {
    Say "Network adapters on this laptop"
    Get-NetAdapter | Select-Object Name, InterfaceDescription, Status |
        Format-Table -AutoSize
    Say "Which one has the internet"
    Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        ForEach-Object { "    " + (Get-NetAdapter -InterfaceIndex $_.ifIndex).Name }
    Write-Host "`nCopy the names above into the SETTINGS block of this script.`n"
    exit 0
}

# ----------------------------- ADMIN CHECK -----------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Die "This script must run as Administrator.
       Close this window, right-click PowerShell, choose 'Run as administrator',
       then run the command again."
}

foreach ($n in @($WanAdapter, $LanAdapter)) {
    if (-not (Get-NetAdapter -Name $n -ErrorAction SilentlyContinue)) {
        Die "No adapter named '$n'. Run this script with -List to see the real names,
       then edit the SETTINGS block at the top."
    }
}

Say "Configuration"
Write-Host "    internet via : $WanAdapter"
Write-Host "    pi on        : $LanAdapter"
Write-Host "    method       : $Method"

# ----------------------------- ICS HELPERS -----------------------------------
function Get-IcsConfig($adapterName) {
    $share = New-Object -ComObject HNetCfg.HNetShare
    foreach ($conn in $share.EnumEveryConnection) {
        $props = $share.NetConnectionProps.Invoke($conn)
        if ($props.Name -eq $adapterName) {
            return $share.INetSharingConfigurationForINetConnection.Invoke($conn)
        }
    }
    return $null
}

# ----------------------------- UNDO ------------------------------------------
if ($Undo) {
    Say "Removing sharing"
    if ($Method -eq "ICS") {
        foreach ($n in @($WanAdapter, $LanAdapter)) {
            $cfg = Get-IcsConfig $n
            if ($cfg -and $cfg.SharingEnabled) { $cfg.DisableSharing(); OK "ICS disabled on $n" }
        }
    } else {
        Remove-NetNat -Name $NatName -Confirm:$false -ErrorAction SilentlyContinue
        Set-NetIPInterface -InterfaceAlias $LanAdapter -Forwarding Disabled -ErrorAction SilentlyContinue
        OK "NAT removed"
    }
    Write-Host ""
    exit 0
}

# ----------------------------- ENABLE: ICS -----------------------------------
if ($Method -eq "ICS") {
    Say "Enabling Internet Connection Sharing"

    $wanCfg = Get-IcsConfig $WanAdapter
    $lanCfg = Get-IcsConfig $LanAdapter
    if (-not $wanCfg) { Die "Could not get ICS config for '$WanAdapter'." }
    if (-not $lanCfg) { Die "Could not get ICS config for '$LanAdapter'." }

    # Clear any previous sharing first - Windows allows only one ICS pair.
    foreach ($c in @($wanCfg, $lanCfg)) { if ($c.SharingEnabled) { $c.DisableSharing() } }
    Start-Sleep -Seconds 2

    $wanCfg.EnableSharing(0)   # 0 = PUBLIC  (the side with the internet)
    $lanCfg.EnableSharing(1)   # 1 = PRIVATE (the side with the Pi)
    Start-Sleep -Seconds 3

    if ((Get-IcsConfig $WanAdapter).SharingEnabled) { OK "Sharing enabled" }
    else { Die "Windows did not enable sharing. Check that the 'Internet Connection Sharing (ICS)' service is not disabled (services.msc)." }

    $gateway = "192.168.137.1"
    $piNet   = "192.168.137"
}
# ----------------------------- ENABLE: NAT -----------------------------------
else {
    Say "Enabling routing and NAT"

    if (-not (Get-Command New-NetNat -ErrorAction SilentlyContinue)) {
        Die "New-NetNat is not available on this Windows edition.
       Set `$Method = `"ICS`" at the top of this script instead."
    }

    Set-NetIPInterface -InterfaceAlias $LanAdapter -Forwarding Enabled
    OK "forwarding enabled on $LanAdapter"

    $existing = Get-NetIPAddress -InterfaceAlias $LanAdapter -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -eq $HostIP }
    if (-not $existing) {
        New-NetIPAddress -InterfaceAlias $LanAdapter -IPAddress $HostIP `
                         -PrefixLength $PrefixLength -ErrorAction SilentlyContinue | Out-Null
    }
    OK "$LanAdapter address is $HostIP"

    Get-NetNat -Name $NatName -ErrorAction SilentlyContinue | Remove-NetNat -Confirm:$false
    New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $LanSubnet | Out-Null
    OK "NAT active for $LanSubnet"

    $gateway = $HostIP
    $piNet   = ($HostIP -replace '\.\d+$', '')
}

# ----------------------------- SUMMARY ---------------------------------------
Write-Host @"

-----------------------------------------------------------------------
 Internet sharing is ON.

 On the Pi, give eth0 a static IP that matches this laptop.
 Edit the SETTINGS block of setup_network.sh:

     ETH_ADDRESS="$piNet.11/24"    # robot01 = .11, robot02 = .12, robot03 = .13
     ETH_GATEWAY="$gateway"

 then run:   sudo bash setup_network.sh
 and test:   ping -c3 8.8.8.8

 Turn sharing off again with:   ... -Undo
-----------------------------------------------------------------------

"@ -ForegroundColor White
