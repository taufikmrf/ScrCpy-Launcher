# scrcpy.ps1
# source >> https://github.com/taufikmrf/ScrCpy-Launcher/edit/main/scrcpy.ps1


$configFile = ".\scrcpy_config.ps1"
$langDir = ".\language"
$port = 5555
$bitrate = "8M"
$resolution = 1024
$langSetting = "auto"

function Load-Config {
    if (Test-Path $configFile) {
        . $configFile
    } else {
        Save-Config
    }
}

function Save-Config {
    $content = @"
`$port = $port
`$bitrate = '$bitrate'
`$resolution = $resolution
`$langSetting = '$langSetting'
"@
    $content | Out-File -Encoding UTF8 $configFile
}

function Detect-Lang {
    $envLang = $env:LANG
    if (-not $envLang) { return "en" }
    return $envLang.Substring(0,2)
}

function Load-LanguageFile {
    param([string]$lang)
    $langFile = Join-Path $langDir "$lang.lang"
    if (Test-Path $langFile) {
        . $langFile
    } else {
        Write-Host "Language file $langFile not found!"
        Exit 1
    }
}

function Set-Language {
    param([string]$lang)
    if ($lang -eq "auto") { $lang = Detect-Lang }
    if ($lang -in @("id","en")) { $langSetting = $lang } else { $langSetting = "en" }
    Save-Config
    Load-LanguageFile $langSetting
}

function Get-UsbDevices {
    $devices = adb devices | Select-String "device$" | ForEach-Object { ($_ -split "`t")[0] }
    return $devices
}

function Run-ScrcpyUsb { param($device)
    Write-Host "$TXT_RUNNING_USB$device ..."
    Start-Process -NoNewWindow -Wait scrcpy -ArgumentList "--power-off-on-close", "-Sw", "-d", "--video-bit-rate", $bitrate, "--max-size", $resolution
}

function Run-ScrcpyWiFi { param($ip)
    Write-Host "$TXT_CONNECTING_WIFI$ip`:$port ..."
    $connectOutput = adb connect "$ip`:$port"
    if ($connectOutput -match "connected to") {
        Write-Host "$TXT_RUNNING_WIFI$ip`:$port ..."
        Start-Process -NoNewWindow -Wait scrcpy -ArgumentList "--power-off-on-close", "-Sw", "-e", "--video-bit-rate", $bitrate, "--max-size", $resolution
    } else {
        Write-Host "$TXT_FAILED_CONNECT_IP$ip`:$port"
        Read-Host $TXT_PRESS_ENTER
    }
}

function Manual-WiFiConnect {
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
    if (-not $localIP) { Write-Host $TXT_IP_LOCAL_FAILED; Read-Host $TXT_PRESS_ENTER; return }
    $ipParts = $localIP -split '\.'
    $ipPrefix = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2])."
    $lastSegment = Read-Host "$TXT_ENTER_IP$ipPrefix"
    if ($lastSegment -match '^\d{1,3}$' -and [int]$lastSegment -ge 0 -and [int]$lastSegment -le 255) {
        $fullIP = "$ipPrefix$lastSegment"
        Run-ScrcpyWiFi $fullIP
    } else {
        Write-Host $TXT_SEGMENT_IP_INVALID
        Read-Host $TXT_PRESS_ENTER
    }
}

function Change-Port {
    $newPort = Read-Host $TXT_ENTER_PORT
    if ($newPort -match "^\d+$") { $port = [int]$newPort; Save-Config } else { Write-Host $TXT_INVALID_CHOICE; Start-Sleep -Seconds 1 }
}

function Change-Bitrate {
    $newBitrate = Read-Host $TXT_ENTER_BITRATE
    if ($newBitrate) { $bitrate = $newBitrate; Save-Config } else { Write-Host $TXT_INVALID_CHOICE; Start-Sleep -Seconds 1 }
}

function Change-Resolution {
    $newRes = Read-Host $TXT_ENTER_RESOLUTION
    if ($newRes -match "^\d+$") { $resolution = [int]$newRes; Save-Config } else { Write-Host $TXT_INVALID_CHOICE; Start-Sleep -Seconds 1 }
}

function Show-Menu {
    Clear-Host
    Write-Host $TXT_MENU_TITLE
    Write-Host $TXT_MENU_USB
    Write-Host $TXT_MENU_WIFI
    Write-Host ($TXT_MENU_CHANGE_PORT -replace "{PORT}", $port)
    Write-Host ($TXT_MENU_CHANGE_BITRATE -replace "{BITRATE}", $bitrate)
    Write-Host ($TXT_MENU_CHANGE_RESOLUTION -replace "{RESOLUTION}", $resolution)
    Write-Host $TXT_MENU_CHANGE_LANG
    Write-Host $TXT_MENU_QUIT
    Write-Host "======================="
}

# --- MAIN ---
Load-Config
if ($langSetting -eq "auto") { Set-Language "auto" } else { Set-Language $langSetting }

while ($true) {
    Show-Menu
    $choice = Read-Host $TXT_CHOOSE_MENU
    $choice = $choice.ToLower()
    switch ($choice) {
        'd' {
            $usbDevices = Get-UsbDevices
            if ($usbDevices.Count -eq 0) { Write-Host $TXT_USB_NO_DEVICE; Read-Host $TXT_PRESS_ENTER }
            elseif ($usbDevices.Count -eq 1) { Run-ScrcpyUsb $usbDevices[0] }
            else {
                Write-Host $TXT_USB_FOUND_MULTIPLE
                for ($i=0; $i -lt $usbDevices.Count; $i++) { Write-Host "[$($i+1)] $($usbDevices[$i])" }
                $sel = Read-Host $TXT_USB_CHOOSE
                if ($sel -match "^\d+$" -and $sel -ge 1 -and $sel -le $usbDevices.Count) { Run-ScrcpyUsb $usbDevices[$sel - 1] }
                else { Write-Host $TXT_INVALID_CHOICE; Start-Sleep -Seconds 1 }
            }
        }
        'e' { Manual-WiFiConnect }
        'p' { Change-Port }
        'b' { Change-Bitrate }
        'r' { Change-Resolution }
        'l' {
            $newLang = Read-Host $TXT_ENTER_LANG
            if ($newLang -in @("id","en","auto")) { Set-Language $newLang; Write-Host "$TXT_LANG_CHANGED$newLang"; Start-Sleep -Seconds 1 }
            else { Write-Host $TXT_INVALID_CHOICE; Start-Sleep -Seconds 1 }
        }
        'q' { Write-Host $TXT_EXIT_MSG; Read-Host; break }
        default { Write-Host $TXT_INVALID_CHOICE; Start-Sleep -Seconds 1 }
    }
}
