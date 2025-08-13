@echo off
setlocal EnableDelayedExpansion

REM --- Lokasi file config di folder script ---
set SCRIPT_DIR=%~dp0
set CONFIG_FILE=%SCRIPT_DIR%scrcpy_config.ini

REM --- Baca config atau set default ---
if exist "%CONFIG_FILE%" (
    for /f "usebackq tokens=1,2 delims==" %%A in ("%CONFIG_FILE%") do (
        if /i "%%A"=="PORT" set PORT=%%B
        if /i "%%A"=="BITRATE" set BITRATE=%%B
        if /i "%%A"=="RESOLUTION" set RESOLUTION=%%B
    )
) else (
    set PORT=5555
    set BITRATE=8M
    set RESOLUTION=1024
    echo PORT=%PORT%>"%CONFIG_FILE%"
    echo BITRATE=%BITRATE%>>"%CONFIG_FILE%"
    echo RESOLUTION=%RESOLUTION%>>"%CONFIG_FILE%"
)

:MAIN_MENU
cls
echo ===== SCRCPY MENU =====
echo [D] Jalankan via USB
echo [E] Jalankan via Wi-Fi (input IP manual)
echo [A] Auto Detect Wi-Fi
echo [P] Ubah Port (sekarang: %PORT%)
echo [B] Ubah Video Bitrate (sekarang: %BITRATE%)
echo [R] Ubah Resolusi (sekarang: %RESOLUTION%)
echo [Q] Keluar
echo =======================
set /p choice= Pilih menu: 
set choice=%choice:~0,1%
set choice=%choice:a=A%
set choice=%choice:b=B%
set choice=%choice:c=C%
set choice=%choice:d=D%
set choice=%choice:e=E%
set choice=%choice:f=F%
set choice=%choice:g=G%
set choice=%choice:h=H%
set choice=%choice:i=I%
set choice=%choice:j=J%
set choice=%choice:k=K%
set choice=%choice:l=L%
set choice=%choice:m=M%
set choice=%choice:n=N%
set choice=%choice:o=O%
set choice=%choice:p=P%
set choice=%choice:q=Q%
set choice=%choice:r=R%
set choice=%choice:s=S%
set choice=%choice:t=T%
set choice=%choice:u=U%
set choice=%choice:v=V%
set choice=%choice:w=W%
set choice=%choice:x=X%
set choice=%choice:y=Y%
set choice=%choice:z=Z%

if "%choice%"=="D" goto RUN_USB
if "%choice%"=="E" goto RUN_WIFI_MANUAL
if "%choice%"=="A" goto AUTO_DETECT_WIFI
if "%choice%"=="P" goto CHANGE_PORT
if "%choice%"=="B" goto CHANGE_BITRATE
if "%choice%"=="R" goto CHANGE_RESOLUTION
if "%choice%"=="Q" goto EXIT_SCRIPT

echo Pilihan tidak valid!
timeout /t 1 /nobreak >nul
goto MAIN_MENU

:RUN_USB
call :CHECK_USB
if "%USB_DEVICE%"=="" (
    echo Tidak ada device USB terdeteksi!
    pause
    goto MAIN_MENU
)
echo Menjalankan scrcpy via USB pada device %USB_DEVICE%...
start "" scrcpy.exe --power-off-on-close -Sw -d --video-bit-rate %BITRATE% --max-size %RESOLUTION%
goto MAIN_MENU

:RUN_WIFI_MANUAL
set /p IP="Masukkan IP perangkat: "
adb connect %IP%:%PORT%
echo Menjalankan scrcpy via Wi-Fi %IP%:%PORT%...
start "" scrcpy.exe --power-off-on-close -Sw -e --video-bit-rate %BITRATE% --max-size %RESOLUTION%
goto MAIN_MENU

:AUTO_DETECT_WIFI
REM Cek apakah adb devices ada device wifi
for /f "skip=1 tokens=1,2" %%A in ('adb devices') do (
    echo %%A | findstr /r /c:"[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*:" >nul
    if !errorlevel! == 0 (
        set IP=%%A
        goto WIFI_FOUND
    )
)

REM Jika tidak ada wifi device, cek USB device
call :CHECK_USB
if not "%USB_DEVICE%"=="" (
    echo Mengaktifkan mode TCP/IP pada device USB %USB_DEVICE%...
    adb tcpip %PORT%
    timeout /t 2 /nobreak >nul
    echo Lepaskan USB dan pastikan HP terhubung ke Wi-Fi yang sama.
) else (
    echo Tidak ada device USB terdeteksi.
    pause
    goto MAIN_MENU
)

REM Cari subnet lokal
for /f "tokens=2 delims=:" %%I in ('ipconfig ^| findstr /i "IPv4"') do (
    set LOCAL_IP=%%I
    goto BREAK_LOOP
)
:BREAK_LOOP
set LOCAL_IP=%LOCAL_IP: =%
for /f "tokens=1-3 delims=." %%a in ("%LOCAL_IP%") do (
    set SUBNET=%%a.%%b.%%c.0/24
)

echo Memindai jaringan %SUBNET% untuk port %PORT%...
nmap -p %PORT% --open -T4 %SUBNET% -oG scan.txt >nul
set FOUND_IP=
for /f "tokens=2" %%i in ('findstr /r /c:"Ports: %PORT% open" scan.txt') do (
    set FOUND_IP=%%i
)

if "%FOUND_IP%"=="" (
    echo Tidak ditemukan perangkat Wi-Fi dengan port %PORT% terbuka.
    pause
    goto MAIN_MENU
)

echo Menghubungkan ke %FOUND_IP%...
adb connect %FOUND_IP%:%PORT%
echo Menjalankan scrcpy via Wi-Fi %FOUND_IP%:%PORT%...
start "" scrcpy.exe --power-off-on-close -Sw -e --video-bit-rate %BITRATE% --max-size %RESOLUTION%
goto MAIN_MENU

:CHANGE_PORT
set /p PORT=Masukkan port baru: 
echo PORT=%PORT%>"%CONFIG_FILE%"
echo BITRATE=%BITRATE%>>"%CONFIG_FILE%"
echo RESOLUTION=%RESOLUTION%>>"%CONFIG_FILE%"
goto MAIN_MENU

:CHANGE_BITRATE
set /p BITRATE=Masukkan bitrate baru (contoh: 8M): 
echo PORT=%PORT%>"%CONFIG_FILE%"
echo BITRATE=%BITRATE%>>"%CONFIG_FILE%"
echo RESOLUTION=%RESOLUTION%>>"%CONFIG_FILE%"
goto MAIN_MENU

:CHANGE_RESOLUTION
set /p RESOLUTION=Masukkan resolusi baru (contoh: 1024): 
echo PORT=%PORT%>"%CONFIG_FILE%"
echo BITRATE=%BITRATE%>>"%CONFIG_FILE%"
echo RESOLUTION=%RESOLUTION%>>"%CONFIG_FILE%"
goto MAIN_MENU

:CHECK_USB
set USB_DEVICE=
for /f "skip=1 tokens=1,2" %%A in ('adb devices') do (
    if "%%B"=="device" (
        echo %%A | findstr /v ":" >nul
        if !errorlevel! == 0 (
            set USB_DEVICE=%%A
            goto :eof
        )
    )
)
goto :eof

:EXIT_SCRIPT
echo Tekan Enter untuk keluar...
pause >nul
exit /b
