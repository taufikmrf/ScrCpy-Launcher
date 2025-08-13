# scrcpy.ps1

# Lokasi config file di folder script
$configFile = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "scrcpy_config.ini"

# Load or default config
if (Test-Path $configFile) {
    $config = Get-Content $configFile | ForEach-Object {
        if ($_ -match "^(?<key>[^=]+)=(?<val>.+)$") {
            @{ $_.Matches[0].Groups['key'].Value = $_.Matches[0].Groups['val'].Value }
        }
    } | ForEach-Object { $_ } | Select-Object -ExpandProperty PSObject -ErrorAction SilentlyContinue

    $PORT = ($config | Where-Object { $_.PSObject.Properties.Name -eq 'PORT' }).PSObject.Properties.Value
    $BITRATE = ($config | Where-Object { $_.PSObject.Properties.Name -eq 'BITRATE' }).PSObject.Properties.Value
    $RESOLUTION = ($config | Where-Object { $_.PSObject.Properties.Name -eq 'RESOLUTION' }).PSObject.Properties.Value
}

if (-not $PORT) { $PORT = 5555 }
if (-not $BITRATE) { $BITRATE = "8M" }
if (-not $RESOLUTION) { $RESOLUTION = 1024 }

function Save-Config {
    $content = @(
        "PORT=$PORT"
        "BITRATE=$BITRATE"
        "RESOLUTION=$RESOLUTION"
    )
    $content | Out-File -FilePath $configFile -Encoding utf8
}

function Run-Scrcpy {
    param([string]$mode, [string]$ip="")

    if ($mode -eq "usb") {
        Write-Host "🔌 Menjalankan scrcpy via USB..."
        Start-Process -NoNewWindow scrcpy.exe -ArgumentList "--power-off-on-close -Sw -d --video-bit-rate $BITRATE --max-size $RESOLUTION"
    } elseif ($mode -eq "wifi") {
        Write-Host "📡 Menjalankan scrcpy via Wi-Fi ($ip`:$PORT)..."
        Start-Process -NoNewWindow scrcpy.exe -ArgumentList "--power-off-on-close -Sw -e --video-bit-rate $BITRATE --max-size $RESOLUTION"
    }
}

function Get-UsbDevices {
    $devices = adb devices | Select-String -Pattern "device$" | ForEach-Object {
        ($_ -split "`t")[0]
    }
    # Filter out IP addresses (Wi-Fi devices)
    $usbDevices = $devices | Where-Object { $_ -notmatch '\d+\.\d+\.\d+\.\d+:\d+' }
    return $usbDevices
}

function Auto-Connect-Usb {
    $usbDevices = Get-UsbDevices
    if ($usbDevices.Count -eq 1) {
        Write-Host "🔍 USB device terdeteksi: $($usbDevices[0])"
        Run-Scrcpy -mode "usb"
        return $true
    } elseif ($usbDevices.Count -gt 1) {
        Write-Host "🔍 Ditemukan beberapa USB device:"
        for ($i=0; $i -lt $usbDevices.Count; $i++) {
            Write-Host "[$($i+1)] $($usbDevices[$i])"
        }
        $selection = Read-Host "Pilih device (nomor)"
        if ($selection -ge 1 -and $selection -le $usbDevices.Count) {
            $device = $usbDevices[$selection - 1]
            Write-Host "Memilih device $device"
            Run-Scrcpy -mode "usb"
            return $true
        }
    }
    return $false
}

function Test-PortOpen {
    param([string]$ip, [int]$port)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcp.BeginConnect($ip, $port, $null, $null)
        $wait = $asyncResult.AsyncWaitHandle.WaitOne(500)
        if (-not $wait) {
            $tcp.Close()
            return $false
        }
        $tcp.EndConnect($asyncResult)
        $tcp.Close()
        return $true
    } catch {
        return $false
    }
}

function Auto-Detect-Wifi {
    # Cek adb devices wifi yang sudah connect
    $wifiDevices = adb devices | Select-String -Pattern '\d+\.\d+\.\d+\.\d+:\d+' | ForEach-Object {
        ($_ -split "`t")[0]
    }
    if ($wifiDevices.Count -gt 0) {
        $ip = $wifiDevices[0].Split(':')[0]
        Write-Host "📡 Perangkat Wi-Fi ditemukan: $ip"
        Run-Scrcpy -mode "wifi" -ip $ip
        return
    }

    # Jika belum ada device wifi, coba aktifkan tcpip lewat usb
    $usbDevices = Get-UsbDevices
    if ($usbDevices.Count -gt 0) {
        Write-Host "🔌 Mengaktifkan mode TCP/IP pada device USB $($usbDevices[0])..."
        adb tcpip $PORT
        Start-Sleep -Seconds 2
        Write-Host "📴 Lepaskan USB dan pastikan HP terhubung ke Wi-Fi yang sama."
    } else {
        Write-Warning "Tidak ada device USB terdeteksi."
        Read-Host "Tekan Enter untuk kembali ke menu"
        return
    }

    # Cari subnet lokal dari IP address utama
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Wi-Fi' | Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress
    if (-not $localIP) {
        Write-Warning "Gagal mendeteksi alamat IP Wi-Fi lokal."
        Read-Host "Tekan Enter untuk kembali ke menu"
        return
    }
    $subnet = ($localIP -split '\.')[0..2] -join '.' + '.0/24'

    Write-Host "🌐 Memindai jaringan $subnet untuk port $PORT..."

    $ipBase = ($localIP -split '\.')[0..2] -join '.'

    $openHosts = @()
    for ($i=1; $i -le 254; $i++) {
        $testIP = "$ipBase.$i"
        if (Test-PortOpen -ip $testIP -port $PORT) {
            $openHosts += $testIP
        }
    }

    if ($openHosts.Count -eq 0) {
        Write-Warning "❌ Tidak ditemukan perangkat Wi-Fi dengan port $PORT terbuka."
        Read-Host "Tekan Enter untuk kembali ke menu..."
        return
    } elseif ($openHosts.Count -eq 1) {
        $ip = $openHosts[0]
        Write-Host "📱 Menghubungkan ke $ip..."
        adb connect "$ip`:$PORT"
        Run-Scrcpy -mode "wifi" -ip $ip
    } else {
        Write-Host "📡 Ditemukan beberapa perangkat Wi-Fi:"
        for ($j=0; $j -lt $openHosts.Count; $j++) {
            Write-Host "[$($j+1)] $($openHosts[$j])"
        }
        $sel = Read-Host "Pilih device (nomor)"
        if ($sel -ge 1 -and $sel -le $openHosts.Count) {
            $ip = $openHosts[$sel - 1]
            adb connect "$ip`:$PORT"
            Run-Scrcpy -mode "wifi" -ip $ip
        }
    }
}

function Change-Port {
    $newPort = Read-Host "Masukkan port baru"
    if ($newPort -match '^\d+$') {
        $global:PORT = $newPort
        Save-Config
        Write-Host "Port disimpan menjadi $PORT"
    } else {
        Write-Warning "Input port tidak valid!"
    }
    Read-Host "Tekan Enter untuk kembali ke menu"
}

function Change-Bitrate {
    $newBitrate = Read-Host "Masukkan bitrate baru (contoh: 8M)"
    if ($newBitrate) {
        $global:BITRATE = $newBitrate
        Save-Config
        Write-Host "Bitrate disimpan menjadi $BITRATE"
    } else {
        Write-Warning "Input bitrate tidak valid!"
    }
    Read-Host "Tekan Enter untuk kembali ke menu"
}

function Change-Resolution {
    $newRes = Read-Host "Masukkan resolusi baru (contoh: 1024)"
    if ($newRes -match '^\d+$') {
        $global:RESOLUTION = $newRes
        Save-Config
        Write-Host "Resolusi disimpan menjadi $RESOLUTION"
    } else {
        Write-Warning "Input resolusi tidak valid!"
    }
    Read-Host "Tekan Enter untuk kembali ke menu"
}

function Main-Menu {
    while ($true) {
        Clear-Host
        Write-Host "===== SCRCPY MENU ====="
        Write-Host "[D] Jalankan via USB"
        Write-Host "[E] Jalankan via Wi-Fi (input IP manual)"
        Write-Host "[A] Auto Detect Wi-Fi"
        Write-Host "[P] Ubah Port (sekarang: $PORT)"
        Write-Host "[B] Ubah Video Bitrate (sekarang: $BITRATE)"
        Write-Host "[R] Ubah Resolusi (sekarang: $RESOLUTION)"
        Write-Host "[Q] Keluar"
        Write-Host "======================="
        $choice = Read-Host "Pilih menu"
        switch ($choice.ToUpper()) {
            "D" { Run-Scrcpy -mode "usb" }
            "E" {
                $ipInput = Read-Host "Masukkan IP perangkat"
                adb connect "$ipInput`:$PORT"
                Run-Scrcpy -mode "wifi" -ip $ipInput
            }
            "A" { Auto-Detect-Wifi }
            "P" { Change-Port }
            "B" { Change-Bitrate }
            "R" { Change-Resolution }
            "Q" { break }
            default {
                Write-Warning "Pilihan tidak valid!"
                Start-Sleep -Seconds 1
            }
        }
    }
    Write-Host "🚪 Keluar skrip... Tekan Enter untuk keluar..."
    Read-Host
}

if (-not (Auto-Connect-Usb)) {
    Main-Menu
}
