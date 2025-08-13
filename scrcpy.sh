#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/scrcpy_config.conf"

CTRLC_COUNT=0
SCRCPY_PID=""

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    PORT=5555
    BITRATE="8M"
    RESOLUTION="1024"
    echo "PORT=$PORT" > "$CONFIG_FILE"
    echo "BITRATE=$BITRATE" >> "$CONFIG_FILE"
    echo "RESOLUTION=$RESOLUTION" >> "$CONFIG_FILE"
fi

save_config() {
    echo "PORT=$PORT" > "$CONFIG_FILE"
    echo "BITRATE=$BITRATE" >> "$CONFIG_FILE"
    echo "RESOLUTION=$RESOLUTION" >> "$CONFIG_FILE"
}

handle_interrupt() {
    ((CTRLC_COUNT++))
    if [[ $CTRLC_COUNT -eq 1 ]]; then
        echo -e "\n⚠️  Ctrl+C terdeteksi. Menutup scrcpy..."
        if [[ -n "$SCRCPY_PID" ]]; then
            kill "$SCRCPY_PID" 2>/dev/null
            sleep 0.3
            if ps -p "$SCRCPY_PID" > /dev/null 2>&1; then
                kill -9 "$SCRCPY_PID" 2>/dev/null
            fi
            SCRCPY_PID=""
        fi
        CTRLC_COUNT=0
        clear
        main_menu
    else
        echo -e "\n🚪 Keluar skrip..."
        read -p "Tekan Enter untuk keluar..."
        clear
        exit 0
    fi
}

trap handle_interrupt SIGINT

run_scrcpy() {
    mode=$1
    if [[ "$mode" == "usb" ]]; then
        echo "🔌 Menjalankan scrcpy via USB..."
        scrcpy --power-off-on-close -Sw -d --video-bit-rate "$BITRATE" --max-size "$RESOLUTION" >/dev/null 2>&1 &
    else
        echo "📡 Menjalankan scrcpy via Wi-Fi ($IP:$PORT)..."
        scrcpy --power-off-on-close -Sw -e --video-bit-rate "$BITRATE" --max-size "$RESOLUTION" >/dev/null 2>&1 &
    fi
    SCRCPY_PID=$!
    wait $SCRCPY_PID 2>/dev/null
}

check_usb_devices() {
    adb devices | grep -w "device" | grep -v "List" | awk '{print $1}'
}

auto_connect_usb() {
    devices=($(check_usb_devices))
    if [[ ${#devices[@]} -gt 0 ]]; then
        if [[ ${#devices[@]} -eq 1 ]]; then
            echo "🔍 USB device terdeteksi: ${devices[0]}"
            run_scrcpy "usb"
        else
            echo "🔍 Ditemukan beberapa USB device:"
            select dev in "${devices[@]}"; do
                adb -s "$dev" usb
                run_scrcpy "usb"
                break
            done
        fi
        return 0
    fi
    return 1
}

auto_detect_wifi() {
    wifi_devices=($(adb devices | grep -E '([0-9]{1,3}\.){3}[0-9]{1,3}:' | awk '{print $1}'))

    if [[ ${#wifi_devices[@]} -gt 0 ]]; then
        IP="${wifi_devices[0]}"
        echo "📡 Perangkat Wi-Fi ditemukan: $IP"
        run_scrcpy "wifi"
        return
    fi

    usb_devices=($(check_usb_devices))
    if [[ ${#usb_devices[@]} -gt 0 ]]; then
        echo "🔌 Mengaktifkan mode TCP/IP pada device USB ${usb_devices[0]}..."
        adb tcpip "$PORT"
        sleep 1
        echo "📴 Lepaskan USB dan pastikan HP terhubung ke Wi-Fi yang sama."
    fi

    subnet=""
    if command -v networksetup &>/dev/null; then
        iface=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
        subnet=$(ifconfig "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | sed 's/\.[0-9]*$/\.0\/24/')
    fi
    if [[ -z "$subnet" ]]; then
        iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5}')
        subnet=$(ip -o -f inet addr show "$iface" 2>/dev/null | awk '{print $4}')
    fi

    if [[ -z "$subnet" ]]; then
        echo "❌ Gagal mendeteksi subnet Wi-Fi."
        read -p "Tekan Enter untuk kembali ke menu..."
        return 1
    fi

    echo "🌐 Memindai jaringan $subnet untuk port $PORT..."
    hosts=($(nmap -p "$PORT" --open -T4 "$subnet" -oG - | grep "/open" | awk '{print $2}'))

    if [[ ${#hosts[@]} -eq 0 ]]; then
        echo "❌ Tidak ditemukan perangkat Wi-Fi dengan port $PORT terbuka."
        read -p "Tekan Enter untuk kembali ke menu..."
        return 1
    elif [[ ${#hosts[@]} -eq 1 ]]; then
        IP="${hosts[0]}"
        echo "📱 Menghubungkan ke $IP..."
        adb connect "$IP:$PORT"
        run_scrcpy "wifi"
    else
        echo "📡 Ditemukan beberapa perangkat Wi-Fi:"
        select ip in "${hosts[@]}"; do
            if [[ -n "$ip" ]]; then
                IP="$ip"
                adb connect "$IP:$PORT"
                run_scrcpy "wifi"
                break
            fi
        done
    fi
}

main_menu() {
    while true; do
        clear
        echo "===== SCRCPY MENU ====="
        echo "[D] Jalankan via USB"
        echo "[E] Jalankan via Wi-Fi (input IP manual)"
        echo "[A] Auto Detect Wi-Fi"
        echo "[P] Ubah Port (sekarang: $PORT)"
        echo "[B] Ubah Video Bitrate (sekarang: $BITRATE)"
        echo "[R] Ubah Resolusi (sekarang: $RESOLUTION)"
        echo "[Q] Keluar"
        echo "======================="
        read -p "Pilih menu: " choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
        case "$choice" in
            d)
                run_scrcpy "usb"
                ;;
            e)
                read -p "Masukkan IP perangkat: " IP
                adb connect "$IP:$PORT"
                run_scrcpy "wifi"
                ;;
            a)
                auto_detect_wifi
                ;;
            p)
                read -p "Masukkan port baru: " PORT
                save_config
                ;;
            b)
                read -p "Masukkan bitrate baru (contoh: 8M): " BITRATE
                save_config
                ;;
            r)
                read -p "Masukkan resolusi baru (contoh: 1024): " RESOLUTION
                save_config
                ;;
            q)
                echo "🚪 Keluar skrip..."
                read -p "Tekan Enter untuk keluar..."
                clear
                exit 0
                ;;
            *)
                echo "❌ Pilihan tidak valid!"
                sleep 1
                ;;
        esac
    done
}

if ! auto_connect_usb; then
    main_menu
fi
