#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/scrcpy.conf"
LANG_DIR="$SCRIPT_DIR/language"

LANG_SETTING="auto"
PORT=5555
BITRATE="8M"
RESOLUTION=1024

USB_DEVICES=()
SELECTED_USB_DEVICE=""
EXIT_REQUESTED=0
SCRCPY_PID=()

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
  else
    save_config
  fi
}

save_config() {
  cat > "$CONFIG_FILE" << EOF
LANG_SETTING=$LANG_SETTING
PORT=$PORT
BITRATE=$BITRATE
RESOLUTION=$RESOLUTION
EOF
}

detect_lang() {
  if [[ -n "$LANG" ]]; then
    echo "${LANG:0:2}"
  else
    echo "en"
  fi
}

load_language_file() {
  local lang_file="$LANG_DIR/$1.lang"
  if [[ -f "$lang_file" ]]; then
    # shellcheck source=/dev/null
    source "$lang_file"
  else
    echo "Language file $lang_file not found!"
    exit 1
  fi
}

set_language() {
  local lang="$1"
  if [[ "$lang" == "auto" ]]; then
    lang=$(detect_lang)
  fi

  case "$lang" in
    id|en)
      LANG_SETTING="$lang"
      save_config
      load_language_file "$lang"
      ;;
    *)
      LANG_SETTING="en"
      save_config
      load_language_file "en"
      ;;
  esac
}

handle_ctrl_c() {
  if (( ${#SCRCPY_PID[@]} > 0 )); then
    echo
    echo "$TXT_CTRL_C_DETECTED"
    for i in "${!SCRCPY_PID[@]}"; do
      echo "$TXT_CTRL_C_KILLING ${SCRCPY_PID[i]}..."
      kill "${SCRCPY_PID[i]}" 2>/dev/null
      wait "${SCRCPY_PID[i]}" 2>/dev/null
    done
    SCRCPY_PID=()
    EXIT_REQUESTED=0
    read -rp "$TXT_PRESS_ENTER"
    clear
  else
    if (( EXIT_REQUESTED == 0 )); then
      EXIT_REQUESTED=1
      echo
      echo "$TXT_CTRL_C_DETECTED"
      echo "$TXT_CTRL_C_EXIT_NOTICE"
    else
      echo
      echo "$TXT_EXIT_MSG"
      read -r
      clear
      exit 0
    fi
  fi
}

trap 'handle_ctrl_c' SIGINT

check_usb_devices() {
  USB_DEVICES=()
  while IFS= read -r line; do
    # Filter hanya device USB, bukan IP Wi-Fi
    if [[ ! "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?$ ]]; then
      USB_DEVICES+=("$line")
    fi
  done < <(adb devices | grep -v "List of devices" | grep -w "device" | cut -f1)
}

run_scrcpy_usb() {
  if [[ "$SELECTED_USB_DEVICE" == "$TXT_USB_CHOOSE_ALL" ]]; then
    echo "${TXT_RUNNING_USB} ${TXT_USB_CHOOSE_ALL}..."
    for dev in "${USB_DEVICES[@]}"; do
      echo "Menjalankan scrcpy pada $dev ..."
      scrcpy --power-off-on-close -Sw -s "$dev" --video-bit-rate "$BITRATE" --max-size "$RESOLUTION" &
      SCRCPY_PID+=($!)
    done
    # Tunggu semua proses scrcpy selesai
    for pid in "${SCRCPY_PID[@]}"; do
      wait "$pid"
    done
    SCRCPY_PID=()
  else
    echo "${TXT_RUNNING_USB}${SELECTED_USB_DEVICE}..."
    scrcpy --power-off-on-close -Sw -s "$SELECTED_USB_DEVICE" --video-bit-rate "$BITRATE" --max-size "$RESOLUTION" &
    SCRCPY_PID=($!)
    wait "${SCRCPY_PID[0]}"
    SCRCPY_PID=()
  fi
}

run_scrcpy_wifi() {
  local ip="$1"
  echo "${TXT_CONNECTING_WIFI}${ip}:${PORT}..."
  if adb connect "$ip:$PORT" | grep -iq "connected to"; then
    echo "${TXT_RUNNING_WIFI}${ip}:${PORT}..."
    scrcpy --power-off-on-close -Sw -e --video-bit-rate "$BITRATE" --max-size "$RESOLUTION" &
    SCRCPY_PID=($!)
    wait "${SCRCPY_PID[0]}"
    SCRCPY_PID=()
  else
    echo "${TXT_FAILED_CONNECT_IP}${ip}:$PORT"
    read -rp "$TXT_PRESS_ENTER"
  fi
}

run_manual_wifi() {
  local local_ip
  local_ip=$(ipconfig getifaddr en0)
  if [[ -z "$local_ip" ]]; then
    echo "$TXT_IP_LOCAL_FAILED"
    read -rp "$TXT_PRESS_ENTER"
    return
  fi

  local ip_prefix
  ip_prefix=$(echo "$local_ip" | awk -F. '{print $1"."$2"."$3"."}')

  read -rp "${TXT_ENTER_IP}${ip_prefix}" last_segment

  if [[ ! "$last_segment" =~ ^([0-9]{1,3})$ ]] || (( last_segment < 0 || last_segment > 255 )); then
    echo "$TXT_SEGMENT_IP_INVALID"
    read -rp "$TXT_PRESS_ENTER"
    return
  fi

  local full_ip="${ip_prefix}${last_segment}"
  run_scrcpy_wifi "$full_ip"
}

auto_detect_wifi() {
  echo "$TXT_AUTO_WIFI_START"

  wifi_devices=()
  while IFS= read -r line; do
    ipdev=$(echo "$line" | cut -f1)
    if [[ "$ipdev" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?$ ]]; then
      wifi_devices+=("$ipdev")
    fi
  done < <(adb devices | grep -w "device" | tail -n +2)

  if [ ${#wifi_devices[@]} -gt 0 ]; then
    run_scrcpy_wifi "${wifi_devices[0]%%:*}"
    return
  fi

  check_usb_devices
  if [ ${#USB_DEVICES[@]} -gt 0 ]; then
    echo "${TXT_USB_ACTIVATE_TCPIP}${USB_DEVICES[0]}..."
    adb tcpip "$PORT"
    sleep 2
    echo "$TXT_USB_RELEASE_USB"
  fi

  local_ip=$(ipconfig getifaddr en0)
  if [[ -z "$local_ip" ]]; then
    echo "$TXT_IP_LOCAL_FAILED"
    read -rp "$TXT_PRESS_ENTER"
    return
  fi

  subnet=$(echo "$local_ip" | awk -F. '{print $1"."$2"."$3".0/24"}')

  echo "${TXT_SCAN_NETWORK}${subnet}..."
  echo

  if ! command -v nmap &> /dev/null; then
    echo "$TXT_NMAP_NOT_FOUND"
    read -rp "$TXT_PRESS_ENTER"
    return
  fi

  open_ips=()
  if command -v timeout &> /dev/null; then
    while IFS= read -r ip; do
      open_ips+=("$ip")
    done < <(timeout 60 nmap -p "$PORT" --open -T4 "$subnet" -oG - | grep "Ports: $PORT/open" | awk '{print $2}')
  elif command -v gtimeout &> /dev/null; then
    while IFS= read -r ip; do
      open_ips+=("$ip")
    done < <(gtimeout 60 nmap -p "$PORT" --open -T4 "$subnet" -oG - | grep "Ports: $PORT/open" | awk '{print $2}')
  else
    # Jalankan nmap di background ke tmpfile
    tmpfile=$(mktemp)
    nmap -p "$PORT" --open -T4 "$subnet" -oG - > "$tmpfile" 2>/dev/null &
    nmap_pid=$!

    # Tunggu nmap selesai jika belum selesai
    wait "$nmap_pid" 2>/dev/null

    # Ambil IP dari tmpfile
    open_ips=()
    while IFS= read -r ip; do
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            open_ips+=("$ip")
        fi
    done < <(grep "Ports: $PORT/open" "$tmpfile" | awk '{print $2}')
    rm -f "$tmpfile"
  fi

  if [ ${#open_ips[@]} -eq 0 ]; then
    echo "${TXT_NOT_FOUND_WIFI}${PORT}."
    read -rp "$TXT_PRESS_ENTER"
    return
  fi

  if [ ${#open_ips[@]} -eq 1 ]; then
    run_scrcpy_wifi "${open_ips[0]}"
    return
  fi

  echo "$TXT_CHOOSE_WIFI"
  for i in "${!open_ips[@]}"; do
    echo "[$((i+1))] ${open_ips[i]}"
  done

  read -rp "$TXT_CHOOSE_WIFI_SELECT" sel
  if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#open_ips[@]} )); then
    run_scrcpy_wifi "${open_ips[$((sel-1))]}"
  else
    echo "$TXT_INVALID_CHOICE"
    sleep 1
  fi
}

change_port() {
  read -rp "$TXT_ENTER_PORT" newPort
  if [[ "$newPort" =~ ^[0-9]+$ ]]; then
    PORT="$newPort"
    save_config
  else
    echo "$TXT_INVALID_CHOICE"
    sleep 1
  fi
}

change_bitrate() {
  read -rp "$TXT_ENTER_BITRATE" newBitrate
  if [[ -n "$newBitrate" ]]; then
    BITRATE="$newBitrate"
    save_config
  else
    echo "$TXT_INVALID_CHOICE"
    sleep 1
  fi
}

change_resolution() {
  read -rp "$TXT_ENTER_RESOLUTION" newRes
  if [[ "$newRes" =~ ^[0-9]+$ ]]; then
    RESOLUTION="$newRes"
    save_config
  else
    echo "$TXT_INVALID_CHOICE"
    sleep 1
  fi
}

main_menu() {
  while true; do
    clear
    # Tampilkan menu dengan variabel dinamis untuk PORT, BITRATE, RESOLUTION
    set_language "$LANG_SETTING"
    # Replace placeholders di menu teks:
    menu_port=${PORT}
    menu_bitrate=${BITRATE}
    menu_resolution=${RESOLUTION}

    # Tampilkan menu dengan ganti placeholder {PORT}, {BITRATE}, {RESOLUTION}
    echo "${TXT_MENU_TITLE}"
    echo "${TXT_MENU_USB}"
    echo "${TXT_MENU_WIFI}"
    echo "${TXT_MENU_AUTO_WIFI}"
    echo "${TXT_MENU_CHANGE_PORT//\{PORT\}/$menu_port}"
    echo "${TXT_MENU_CHANGE_BITRATE//\{BITRATE\}/$menu_bitrate}"
    echo "${TXT_MENU_CHANGE_RESOLUTION//\{RESOLUTION\}/$menu_resolution}"
    echo "${TXT_MENU_CHANGE_LANG}"
    echo "${TXT_MENU_QUIT}"
    echo "======================="
    read -rp "$TXT_CHOOSE_MENU" choice
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

    case "$choice" in
      d)
        check_usb_devices
        if [ ${#USB_DEVICES[@]} -eq 0 ]; then
          echo "$TXT_USB_NO_DEVICE"
          read -rp "$TXT_PRESS_ENTER"
        else
          if [ ${#USB_DEVICES[@]} -eq 1 ]; then
            SELECTED_USB_DEVICE="${USB_DEVICES[0]}"
          else
            count_plus_one=$(( ${#USB_DEVICES[@]} + 1 ))
            echo "$TXT_USB_FOUND_MULTIPLE"
            for i in "${!USB_DEVICES[@]}"; do
              echo "[$((i+1))] ${USB_DEVICES[i]}"
            done
            echo "[$count_plus_one] $TXT_USB_CHOOSE_ALL"
            read -rp "$TXT_USB_CHOOSE" sel
            if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#USB_DEVICES[@]} )); then
              SELECTED_USB_DEVICE="${USB_DEVICES[$((sel-1))]}"
            elif [[ "$sel" -eq $count_plus_one ]]; then
              SELECTED_USB_DEVICE=$TXT_USB_CHOOSE_ALL
            else
              echo "$TXT_INVALID_CHOICE"
              sleep 1
              continue
            fi
          fi
          run_scrcpy_usb
        fi
        ;;
      e)
        run_manual_wifi
        ;;
      a)
        auto_detect_wifi
        ;;
      p)
        change_port
        ;;
      b)
        change_bitrate
        ;;
      r)
        change_resolution
        ;;
      l)
        read -rp "$TXT_ENTER_LANG" newLang
        case "$newLang" in
          id|en|auto) set_language "$newLang" ;;
          *) echo "$TXT_INVALID_CHOICE"; sleep 1 ;;
        esac
        ;;
      q)
        echo "$TXT_EXIT_MSG"
        read -r
        clear
        exit 0
        ;;
      *)
        echo "$TXT_INVALID_CHOICE"
        sleep 1
        ;;
    esac
  done
}

# Program utama mulai di sini
load_config

if [[ "$LANG_SETTING" == "auto" ]]; then
  set_language "auto"
else
  set_language "$LANG_SETTING"
fi

check_usb_devices

if [ ${#USB_DEVICES[@]} -eq 1 ]; then
  SELECTED_USB_DEVICE="${USB_DEVICES[0]}"
  run_scrcpy_usb
  main_menu
elif [ ${#USB_DEVICES[@]} -gt 1 ]; then
  count_plus_one=$(( ${#USB_DEVICES[@]} + 1 ))
  echo "$TXT_USB_FOUND_MULTIPLE"
  for i in "${!USB_DEVICES[@]}"; do
    echo "[$((i+1))] ${USB_DEVICES[i]}"
  done
  echo "[$count_plus_one] $TXT_USB_CHOOSE_ALL"
  read -rp "$TXT_USB_CHOOSE" sel
  if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#USB_DEVICES[@]} )); then
    SELECTED_USB_DEVICE="${USB_DEVICES[$((sel-1))]}"
    run_scrcpy_usb
    main_menu
  elif [[ "$sel" -eq $count_plus_one ]]; then
    SELECTED_USB_DEVICE=$TXT_USB_CHOOSE_ALL
    run_scrcpy_usb
    main_menu
  else
    echo "$TXT_INVALID_CHOICE"
    sleep 1
    main_menu
  fi
else
  main_menu
fi
