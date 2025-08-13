@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM ======================================
REM Source >> https://github.com/taufikmrf/ScrCpy-Launcher/edit/main/scrcpy.bat
REM Default Config
REM ======================================
set CONFIG_FILE=scrcpy_config.json
set LANG_DIR=language

if exist %CONFIG_FILE% (
    for /f "tokens=1,2,3,4 delims=," %%A in (%CONFIG_FILE%) do (
        set port=%%A
        set bitrate=%%B
        set resolution=%%C
        set lang=%%D
    )
) else (
    set port=5555
    set bitrate=8M
    set resolution=1024
    set lang=auto
)

REM ======================================
REM Load Language
REM ======================================
:LOAD_LANG
if "%lang%"=="auto" set lang=en
set LANG_FILE=%LANG_DIR%\%lang%.lang
if not exist %LANG_FILE% (
    echo Language file not found!
    pause
    exit /b
)
for /f "usebackq tokens=1* delims==" %%A in ("%LANG_FILE%") do (
    set %%A=%%B
)

REM ======================================
REM Ctrl+Break handling
REM ======================================
set ctrlCount=0

REM ======================================
REM Save Config
REM ======================================
:SAVE_CONFIG
> %CONFIG_FILE% echo %port%,%bitrate%,%resolution%,%lang%
exit /b

REM ======================================
REM Main Menu
REM ======================================
:MENU
cls
echo %TXT_MENU_TITLE%
echo [D] %TXT_MENU_USB%
echo [E] %TXT_MENU_WIFI%
echo [F] %TXT_MENU_WIFI_AUTO%
echo [P] %TXT_MENU_CHANGE_PORT% %port%
echo [B] %TXT_MENU_CHANGE_BITRATE% %bitrate%
echo [R] %TXT_MENU_CHANGE_RESOLUTION% %resolution%
echo [L] %TXT_MENU_CHANGE_LANG%
echo [Q] %TXT_MENU_QUIT%
echo =====================

set /p choice=%TXT_CHOOSE_MENU%
set choice=!choice:~0,1!

if /i "!choice!"=="d" call :USB
if /i "!choice!"=="e" call :WIFI_MANUAL
if /i "!choice!"=="f" call :WIFI_AUTO
if /i "!choice!"=="p" call :CHANGE_PORT
if /i "!choice!"=="b" call :CHANGE_BITRATE
if /i "!choice!"=="r" call :CHANGE_RESOLUTION
if /i "!choice!"=="l" call :CHANGE_LANG
if /i "!choice!"=="q" call :EXIT
echo %TXT_INVALID_CHOICE%
pause
goto MENU

REM ======================================
REM USB Function
REM ======================================
:USB
set devices=
for /f "tokens=1" %%D in ('adb devices ^| findstr /R /C:"device$"') do (
    set devices=!devices! %%D
)
set count=0
for %%D in (!devices!) do set /a count+=1

if !count! EQU 0 (
    echo %TXT_USB_NO_DEVICE%
    pause
    goto MENU
) else if !count! EQU 1 (
    for %%D in (!devices!) do set device=%%D
    call :RUN_SCRCPY_USB !device!
    goto MENU
) else (
    echo %TXT_USB_FOUND_MULTIPLE%
    set i=0
    for %%D in (!devices!) do (
        set /a i+=1
        echo [!i!] %%D
    )
    set /p sel=%TXT_USB_CHOOSE%
    set i=0
    for %%D in (!devices!) do (
        set /a i+=1
        if !i! EQU !sel! set device=%%D
    )
    if defined device call :RUN_SCRCPY_USB !device!
    goto MENU
)

REM ======================================
REM Run scrcpy USB
REM ======================================
:RUN_SCRCPY_USB
set device=%1
set ctrlCount=0
:SCRCPY_USB_LOOP
scrcpy --power-off-on-close -Sw -d --video-bit-rate %bitrate% --max-size %resolution%
if !ctrlCount! EQU 0 (
    set /a ctrlCount+=1
    echo %TXT_CTRL_C_DETECTED%
    pause
    goto MENU
) else (
    echo %TXT_EXIT_MSG%
    pause
    exit /b
)

REM ======================================
REM Wi-Fi Manual
REM ======================================
:WIFI_MANUAL
for /f "tokens=2 delims=:" %%I in ('ipconfig ^| findstr "IPv4"') do set LOCAL_IP=%%I
set LOCAL_IP=!LOCAL_IP: =!
for /f "tokens=1-3 delims=." %%a in ("!LOCAL_IP!") do set IP_PREFIX=%%a.%%b.%%c.
set /p LAST_SEG=%TXT_ENTER_IP%!IP_PREFIX!
set FULL_IP=!IP_PREFIX!!LAST_SEG!
set ctrlCount=0
:SCRCPY_WIFI_MANUAL
echo %TXT_CONNECTING_WIFI%!FULL_IP!:%port%
adb connect !FULL_IP!:%port%
echo %TXT_RUNNING_WIFI%!FULL_IP!:%port%
scrcpy --power-off-on-close -Sw -e --video-bit-rate %bitrate% --max-size %resolution%
if !ctrlCount! EQU 0 (
    set /a ctrlCount+=1
    echo %TXT_CTRL_C_DETECTED%
    pause
    goto MENU
) else (
    echo %TXT_EXIT_MSG%
    pause
    exit /b
)

REM ======================================
REM Wi-Fi Auto
REM ======================================
:WIFI_AUTO
for /f "tokens=2 delims=:" %%I in ('ipconfig ^| findstr "IPv4"') do set LOCAL_IP=%%I
set LOCAL_IP=!LOCAL_IP: =!
for /f "tokens=1-3 delims=." %%a in ("!LOCAL_IP!") do set IP_PREFIX=%%a.%%b.%%c.
echo %TXT_WIFI_SCANNING%!IP_PREFIX!0/24 ...
set devices=
for /L %%i in (1,1,254) do (
    ping -n 1 -w 100 !IP_PREFIX!%%i >nul
    if not errorlevel 1 (
        set devices=!devices! %%IP_PREFIX!%%i
    )
)
if "!devices!"=="" (
    echo %TXT_FAILED_CONNECT_IP%
    pause
    goto MENU
)
set i=0
for %%D in (!devices!) do (
    set /a i+=1
    echo [!i!] %%D
)
set /p sel=%TXT_WIFI_CHOOSE%
set i=0
for %%D in (!devices!) do (
    set /a i+=1
    if !i! EQU !sel! set TARGET_IP=%%D
)
if defined TARGET_IP (
    set ctrlCount=0
    :SCRCPY_WIFI_AUTO_LOOP
    echo %TXT_CONNECTING_WIFI%!TARGET_IP!:%port%
    adb connect !TARGET_IP!:%port%
    echo %TXT_RUNNING_WIFI%!TARGET_IP!:%port%
    scrcpy --power-off-on-close -Sw -e --video-bit-rate %bitrate% --max-size %resolution%
    if !ctrlCount! EQU 0 (
        set /a ctrlCount+=1
        echo %TXT_CTRL_C_DETECTED%
        pause
        goto MENU
    ) else (
        echo %TXT_EXIT_MSG%
        pause
        exit /b
    )
) else (
    echo %TXT_INVALID_CHOICE%
    pause
    goto MENU
)

REM ======================================
REM Change Settings
REM ======================================
:CHANGE_PORT
set /p port=%TXT_ENTER_PORT%
call :SAVE_CONFIG
goto MENU

:CHANGE_BITRATE
set /p bitrate=%TXT_ENTER_BITRATE%
call :SAVE_CONFIG
goto MENU

:CHANGE_RESOLUTION
set /p resolution=%TXT_ENTER_RESOLUTION%
call :SAVE_CONFIG
goto MENU

:CHANGE_LANG
set /p lang=%TXT_ENTER_LANG%
call :LOAD_LANG
call :SAVE_CONFIG
goto MENU

REM ======================================
REM Exit
REM ======================================
:EXIT
echo %TXT_EXIT_MSG%
pause
exit /b
