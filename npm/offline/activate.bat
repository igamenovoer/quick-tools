@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM Usage:
REM   call activate.bat --kit-root C:\path\to\kit
REM   call activate.bat --kit-root C:\path\to\kit --platform win32_x64
REM   call activate.bat --kit-root C:\path\to\kit --persist
REM Notes:
REM   --persist delegates to activate.ps1 to update user environment vars.

set "KIT_ROOT="
set "PLATFORM_ID="
set "PERSIST=0"
set "QUIET=0"

:parse
if "%~1"=="" goto parsed
if /I "%~1"=="--kit-root" (
    set "KIT_ROOT=%~2"
    shift
    shift
    goto parse
)
if /I "%~1"=="--platform" (
    set "PLATFORM_ID=%~2"
    shift
    shift
    goto parse
)
if /I "%~1"=="--persist" (
    set "PERSIST=1"
    shift
    goto parse
)
if /I "%~1"=="--quiet" (
    set "QUIET=1"
    shift
    goto parse
)
if /I "%~1"=="--help" goto help
if /I "%~1"=="-h" goto help
echo activate.bat: unknown argument: %~1 1>&2
exit /b 1

:help
echo Usage:
echo   call activate.bat [--kit-root PATH] [--platform ID] [--quiet]
echo   call activate.bat --kit-root PATH --persist [--platform ID] [--quiet]
exit /b 0

:parsed
set "SCRIPT_DIR=%~dp0"

if not defined KIT_ROOT (
    set "CAND=%SCRIPT_DIR%"
    :findroot
    if exist "!CAND!config.toml" (set "KIT_ROOT=!CAND!" & goto foundroot)
    if exist "!CAND!config.yaml" (set "KIT_ROOT=!CAND!" & goto foundroot)
    if exist "!CAND!payloads\" (set "KIT_ROOT=!CAND!" & goto foundroot)
    if exist "!CAND!installed\" (set "KIT_ROOT=!CAND!" & goto foundroot)

    for %%I in ("!CAND!..") do set "PARENT=%%~fI\"
    if /I "!PARENT!"=="!CAND!" goto noroot
    set "CAND=!PARENT!"
    goto findroot

    :noroot
    echo activate.bat: could not infer --kit-root; pass --kit-root 1>&2
    exit /b 1

    :foundroot
)

for %%I in ("%KIT_ROOT%") do set "KIT_ROOT=%%~fI"

if not defined PLATFORM_ID (
    set "DIR_NO_TRAIL=%SCRIPT_DIR:~0,-1%"
    for %%I in ("%DIR_NO_TRAIL%") do set "DIR_PLATFORM=%%~nxI"
    if /I "!DIR_PLATFORM!"=="win32_x64" (
        set "PLATFORM_ID=win32_x64"
    ) else (
        set "ARCH=%PROCESSOR_ARCHITECTURE%"
        if defined PROCESSOR_ARCHITEW6432 set "ARCH=%PROCESSOR_ARCHITEW6432%"
        if /I "%ARCH%"=="ARM64" (
            echo activate.bat: Windows ARM64 is not supported for v1 1>&2
            exit /b 1
        )
        set "PLATFORM_ID=win32_x64"
    )
)

set "PREFIX=%KIT_ROOT%\installed\%PLATFORM_ID%"
set "NODE_BIN=%PREFIX%\node"
set "NPM_PREFIX=%PREFIX%\npm-prefix"
set "PNPM_HOME=%PREFIX%\pnpm-bin"
set "TOOLS_BIN=%PREFIX%\tools\node_modules\.bin"
set "TOOL_BIN=%PREFIX%\bin"

if not exist "%NODE_BIN%\node.exe" (
    if "%PERSIST%"=="0" (
        echo activate.bat: Node not found: "%NODE_BIN%\node.exe" 1>&2
        exit /b 1
    )
)

set "NPM_OFFLINE_KIT_ROOT=%KIT_ROOT%"
set "NPM_OFFLINE_PLATFORM=%PLATFORM_ID%"
set "NPM_CONFIG_PREFIX=%NPM_PREFIX%"

set "PATH=%NODE_BIN%;%PNPM_HOME%;%NPM_PREFIX%\bin;%TOOLS_BIN%;%TOOL_BIN%;%PATH%"

if "%PERSIST%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%activate.ps1" -KitRoot "%KIT_ROOT%" -Platform "%PLATFORM_ID%" -Persist -NoSession -Quiet
    if errorlevel 1 exit /b 1
)

if "%QUIET%"=="0" (
    echo Activated kit: %KIT_ROOT% 1>&2
    echo Platform: %PLATFORM_ID% 1>&2
    if "%PERSIST%"=="1" echo Persisted user env vars. Restart shells to pick up PATH changes. 1>&2
)

endlocal & (
    set "NPM_OFFLINE_KIT_ROOT=%NPM_OFFLINE_KIT_ROOT%"
    set "NPM_OFFLINE_PLATFORM=%NPM_OFFLINE_PLATFORM%"
    set "NPM_CONFIG_PREFIX=%NPM_CONFIG_PREFIX%"
    set "PNPM_HOME=%PNPM_HOME%"
    set "PATH=%PATH%"
)
exit /b 0
