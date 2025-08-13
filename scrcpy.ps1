# scrcpy.ps1

# ========================================
# source >> https://github.com/taufikmrf/ScrCpy-Launcher/edit/main/scrcpy.ps1
# ========================================

# --- Config ---
$configFile = ".\scrcpy_config.json"
if (Test-Path $configFile) {
    $config = Get-Content $configFile | ConvertFrom-Json
    $port = $config.port
    $bitrate = $config.bitrate
    $resolution = $config.resolution
    $lang = $config.lang
} else {
    $port = 5555
    $bitrate = "8M"
    $resolution = 1024
    $lang = "auto"
}
$langDir = ".\language"

# --- Load Language ---
function Load-Lang {
    param([string]$lang)
    if ($lang -eq "auto") { $lang = "en" }
    $langFile = Join-Path $langDir "$lang.lang"
    if (-not (Test-Path $langFile)) { Write-Host "Language file not found!"; exit }
    Get-Content $langFile | ForEach-Object {
        if ($_ -match '^\s*#') { return }
        if ($_ -match '^(.*?)=(.*)$') {
            Set-Variable -Name $matches[1] -Value $matches[2] -Scope Global
        }
    }
}
Load-Lang $lang

# --- Ctrl+C Handling ---
$global:ctrlCcount = 0
$onCancel = {
    $global:ctrlCcount++
    if ($global:ctrlCcount -eq 1) {
        Write-Host $TXT_CTRL_C_DETECTED
        Stop-Process -Name scrcpy -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
    } else {
        Write-Host $TXT_EXIT_MSG
        Read-Host $TXT_PRESS_ENTER
        exit
    }
}
$null = Register-EngineEvent PowerShell.Exiting -Action $onCancel

# --- Save Config ---
function Save-Config {
    $cfg = @{
        port = $port
        bitrate = $bitrate
        resolution = $resolution
        lang = $lang
    } | ConvertTo-Json
    $cfg | Out-File $configFile -Encoding UTF8
}

# --- Menu ---
function Show-Menu {
    Clear-Host
    Write-Host $TXT_MENU_TITLE
    Write-Host $TXT_MENU_USB
    Write-Host $TXT_MENU_WIFI
    Write-Host "[F] $TXT_MENU_WIFI_AUTO"
    Write-Host ($TXT_MENU_CHANGE_PORT -replace "{PORT}",$port)
    Write-Host ($TXT_MENU_CHANGE_BITRATE -replace "{BITRATE}",$bitrate)
    Write-Host ($TXT_MENU_CHANGE_RESOLUTION -replace "{RESOLUTION}",$resolution)
    Write-Host $TXT_MENU_CHANGE_LANG
    Write-Host $TXT_MENU_QUIT
    Write-Host "======================="
}

# --- USB ---
function Run-USB {
    $devices = adb devices | Select-String "device$" | ForEach-Object { ($_ -split "`t")[0] }
    if ($devices.Count -eq 0) {
        Write-Host $TXT_USB_NO_DEVICE
        Read-Host $TXT_PRESS_ENTER
        return
    } elseif ($devices.Count -eq 1) {
        Write-Host "$TXT_RUNNING_USB$($devices[0])"
        Start-Process -NoNewWindow scrcpy -ArgumentList "--power-off-on-close -Sw -d --video-bit-rate $bitrate --max-size $resolution" -Wait
    } else {
        Write-Host $TXT_USB_FOUND_MULTIPLE
        for ($i=0; $i -lt $devices.Count; $i++) {
            Write-Host "[$($i+1)] $($devices[$i])"
        }
        $sel = Read-Host $TXT_USB_CHOOSE
        if ([int]$sel -ge 1 -and [int]$sel -le $devices.Count) {
            $device = $devices[[int]$sel-1]
            Write-Host "$TXT_RUNNING_USB$device"
            Start-Process -NoNewWindow scrcpy -ArgumentList "--power-off-on-close -Sw -d --video-bit-rate $bitrate --max-size $resolution" -Wait
        } else {
            Write-Host $TXT_INVALID_CHOICE
            Start-Sleep -Seconds 1
        }
    }
}

# --- Wi-Fi Manual ---
function Run-WiFi-Manual {
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -like "192.168.*"} | Select-Object -First 1).IPAddress
    if (-not $localIP) { Write-Host $TXT_IP_LOCAL_FAILED; Read-Host $TXT_PRESS_ENTER; return }
    $ipPrefix = ($localIP -split "\.")[0..2] -join "."
    $lastSeg = Read-Host "$TXT_ENTER_IP$ipPrefix"
    if ($lastSeg -notmatch '^\d+$' -or [int]$lastSeg -lt 1 -or [int]$lastSeg -gt 254) {
        Write-Host $TXT_SEGMENT_IP_INVALID
        Read-Host $TXT_PRESS_ENTER
        return
    }
    $fullIP = "$ipPrefix.$lastSeg"
    Write-Host "$TXT_CONNECTING_WIFI$fullIP`:$port"
    adb connect "$fullIP`:$port"
    Write-Host "$TXT_RUNNING_WIFI$fullIP`:$port"
    Start-Process -NoNewWindow scrcpy -ArgumentList "--power-off-on-close -Sw -e --video-bit-rate $bitrate --max-size $resolution" -Wait
}

# --- Wi-Fi Auto ---
function Run-WiFi-Auto {
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -like "192.168.*"} | Select-Object -First 1).IPAddress
    if (-not $localIP) { Write-Host $TXT_IP_LOCAL_FAILED; Read-Host $TXT_PRESS_ENTER; return }
    $ipPrefix = ($localIP -split "\.")[0..2] -join "."
    Write-Host "$TXT_WIFI_SCANNING$ipPrefix.0/24 ..."

    $devices = @()
    1..254 | ForEach-Object {
        if (Test-Connection -Quiet -Count 1 -ComputerName "$ipPrefix.$_" -TimeoutSeconds 0.2) {
            $devices += "$ipPrefix.$_"
        }
    }

    if ($devices.Count -eq 0) {
        Write-Host $TXT_FAILED_CONNECT_IP
        Read-Host $TXT_PRESS_ENTER
        return
    }

    for ($i=0; $i -lt $devices.Count; $i++) {
        Write-Host "[$($i+1)] $($devices[$i])"
    }
    $sel = Read-Host $TXT_WIFI_CHOOSE
    if ([int]$sel -ge 1 -and [int]$sel -le $devices.Count) {
        $targetIP = $devices[[int]$sel-1]
        Write-Host "$TXT_CONNECTING_WIFI$targetIP`:$port"
        adb connect "$targetIP`:$port"
        Write-Host "$TXT_RUNNING_WIFI$targetIP`:$port"
        Start-Process -NoNewWindow scrcpy -ArgumentList "--power-off-on-close -Sw -e --video-bit-rate $bitrate --max-size $resolution" -Wait
    } else {
        Write-Host $TXT_INVALID_CHOICE
        Start-Sleep -Seconds 1
    }
}

# --- Change Settings ---
function Change-Port { $global:port = Read-Host $TXT_ENTER_PORT }
function Change-Bitrate { $global:bitrate = Read-Host $TXT_ENTER_BITRATE }
function Change-Resolution { $global:resolution = Read-Host $TXT_ENTER_RESOLUTION }
function Change-Lang {
    $newLang = Read-Host $TXT_ENTER_LANG
    if ($newLang -in @("id","en","auto")) { $global:lang = $newLang }
    Load-Lang $global:lang
}

# --- Exit ---
function Exit-Script {
    Write-Host $TXT_EXIT_MSG
    Read-Host $TXT_PRESS_ENTER
    exit
}

# --- Main Loop ---
while ($true) {
    Show-Menu
    $choice = Read-Host $TXT_CHOOSE_MENU
    $c = $choice.Substring(0,1).ToLower()

    switch ($c) {
        "d" { Run-USB }
        "e" { Run-WiFi-Manual }
        "f" { Run-WiFi-Auto }
        "p" { Change-Port; Save-Config }
        "b" { Change-Bitrate; Save-Config }
        "r" { Change-Resolution; Save-Config }
        "l" { Change-Lang; Save-Config }
        "q" { Exit-Script }
        default { Write-Host $TXT_INVALID_CHOICE; Start-Sleep -Seconds 1 }
    }
}
