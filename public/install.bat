@echo off
rem dbpod installer (Windows cmd) - https://dbpod.io
rem
rem CLI only (cmd, no PowerShell needed):
rem   curl -fsSL https://dbpod.io/install.bat -o "%TEMP%\dbpod-install.bat" && call "%TEMP%\dbpod-install.bat"
rem
rem CLI + database engine(s) in one shot:
rem   ... && call "%TEMP%\dbpod-install.bat" --engine mysql@8.0 --engine postgres@17
rem
rem Env vars: DBPOD_VERSION, DBPOD_ENGINES (space or comma separated), DBPOD_INSTALL_DIR,
rem DBPOD_DOWNLOAD_BASE (replace the GitHub download base with a mirror URL)
rem Requires curl.exe and tar.exe, both bundled with Windows 10 1803+.

setlocal EnableDelayedExpansion

set "REPO=dbpod-io/dbpod"
set "BIN_NAME=dbpod.exe"
set "RELEASES=https://github.com/%REPO%/releases"
set "MIRROR=https://dl.dbpod.io"

rem --- options -----------------------------------------------------------
set "VERSION=%DBPOD_VERSION%"
if not defined VERSION set "VERSION=%DBPOD_INSTALL_VERSION%"
if not defined VERSION set "VERSION=latest"
set "ENGINES=%DBPOD_ENGINES%"
if defined ENGINES set "ENGINES=!ENGINES:,= !"
set "INSTALL_DIR=%DBPOD_INSTALL_DIR%"

if /i "%~1"=="-h" goto help
if /i "%~1"=="--help" goto help

:parse
if "%~1"=="" goto parsed
if /i "%~1"=="--engine" (
  if "%~2"=="" (
    echo error: --engine needs a value, e.g. mysql@8.0 1>&2
    exit /b 1
  )
  set "ENGINES=!ENGINES! %~2"
  shift
  shift
  goto parse
)
if /i "%~1"=="--version" (
  if "%~2"=="" (
    echo error: --version needs a value 1>&2
    exit /b 1
  )
  set "VERSION=%~2"
  shift
  shift
  goto parse
)
if /i "%~1"=="--install-dir" (
  if "%~2"=="" (
    echo error: --install-dir needs a value 1>&2
    exit /b 1
  )
  set "INSTALL_DIR=%~2"
  shift
  shift
  goto parse
)
echo error: unknown argument: %~1 - try --help 1>&2
exit /b 1

:parsed
for %%e in (!ENGINES!) do (
  echo %%e| findstr /c:"@" >nul || (
    echo error: engine ref must look like engine@version, e.g. mysql@8.0, got: %%e 1>&2
    exit /b 1
  )
)

rem --- detect platform -----------------------------------------------------
set "ARCH=amd64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARCH=arm64"
set "ASSET=dbpod-windows-%ARCH%.zip"

curl.exe --version >nul 2>&1 || ( echo error: curl.exe not found - bundled with Windows 10 1803+ 1>&2 & exit /b 1 )

set "TMPDIR=%TEMP%\dbpod-install-%RANDOM%%RANDOM%"
mkdir "%TMPDIR%" || exit /b 1
set "ASSET_PATH=%TMPDIR%\%ASSET%"

rem --- download (sources tried in order; the download attempt itself is the
rem network probe - release assets come from a different CDN than the
rem github.com page, so no separate reachability check) ----------------------
rem DBPOD_DOWNLOAD_BASE pins one GitHub-layout source and disables the fallback
if defined DBPOD_DOWNLOAD_BASE ( set "SRC1=%DBPOD_DOWNLOAD_BASE%" ) else set "SRC1=%RELEASES%"
echo info: downloading %ASSET% ...
call :try_source "%SRC1%" 1 "%ASSET%" "%ASSET_PATH%"
if not errorlevel 1 goto dl_ok
if defined DBPOD_DOWNLOAD_BASE goto dl_all_failed
call :try_source "%MIRROR%" 0 "%ASSET%" "%ASSET_PATH%"
if not errorlevel 1 goto dl_ok
goto dl_all_failed

:dl_all_failed
echo error: download failed for %ASSET% from all sources 1>&2
echo hint: set HTTPS_PROXY for a proxy, or DBPOD_DOWNLOAD_BASE to pin a mirror 1>&2
goto cleanup_fail

:dl_ok
rem --- verify checksum (from the source that served the binary) -------------
call :make_url "%WIN_BASE%" "%WIN_GH%" checksums.txt
set "WANT="
set /a TRY=0
:dl_sum
set /a TRY+=1
curl -fsSL --connect-timeout 10 --max-time 30 "%URL%" -o "%TMPDIR%\checksums.txt"
if not errorlevel 1 goto dl_sum_ok
if %TRY% lss 3 (
  ping -n 3 127.0.0.1 >nul
  goto dl_sum
)
echo info: checksums.txt unavailable, skipping checksum verification
goto dl_verify_done
:dl_sum_ok
for /f "usebackq tokens=1,2" %%a in ("%TMPDIR%\checksums.txt") do (
  if /i "%%b"=="%ASSET%" set "WANT=%%a"
)
if not defined WANT (
  echo error: checksum for %ASSET% not found in checksums.txt 1>&2
  goto cleanup_fail
)
set "GOT="
for /f "skip=1 tokens=1" %%h in ('certutil -hashfile "%ASSET_PATH%" SHA256') do if not defined GOT set "GOT=%%h"
if /i not "!GOT!"=="!WANT!" (
  echo error: checksum mismatch for %ASSET%: got !GOT!, want !WANT! 1>&2
  goto cleanup_fail
)
echo info: checksum ok
:dl_verify_done

rem --- install ---------------------------------------------------------------
rem pin System32 bsdtar: a GNU tar earlier in PATH would treat C:\ as a host
"%SystemRoot%\System32\tar.exe" -xf "%ASSET_PATH%" -C "%TMPDIR%"
if errorlevel 1 (
  echo error: extraction failed - tar.exe is bundled with Windows 10 1803+ 1>&2
  goto cleanup_fail
)
if not exist "%TMPDIR%\%BIN_NAME%" (
  echo error: archive did not contain a %BIN_NAME% binary - asset layout mismatch? 1>&2
  goto cleanup_fail
)

if not defined INSTALL_DIR set "INSTALL_DIR=%USERPROFILE%\.local\bin"
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
rem Windows refuses to overwrite a running exe but does allow renaming it:
rem park the old binary aside, drop the new one in place, then remove the old
rem copy (if an older dbpod process still locks it, the .old lingers until
rem the next install cleans it up).
if exist "%INSTALL_DIR%\%BIN_NAME%.old" del /f /q "%INSTALL_DIR%\%BIN_NAME%.old" 2>nul
if exist "%INSTALL_DIR%\%BIN_NAME%" (
  echo info: replacing existing %INSTALL_DIR%\%BIN_NAME%
  ren "%INSTALL_DIR%\%BIN_NAME%" "%BIN_NAME%.old" 2>nul
  if exist "%INSTALL_DIR%\%BIN_NAME%" (
    echo error: cannot replace %INSTALL_DIR%\%BIN_NAME% - is a running dbpod.exe locking it? 1>&2
    goto cleanup_fail
  )
)
copy /y "%TMPDIR%\%BIN_NAME%" "%INSTALL_DIR%\%BIN_NAME%" >nul
if errorlevel 1 (
  echo error: cannot write %INSTALL_DIR%\%BIN_NAME% - is a running dbpod.exe locking the file? 1>&2
  goto cleanup_fail
)
if exist "%INSTALL_DIR%\%BIN_NAME%.old" del /f /q "%INSTALL_DIR%\%BIN_NAME%.old" 2>nul
rd /s /q "%TMPDIR%" 2>nul

rem --- install requested engines ---------------------------------------------
set "FIRST_ENGINE="
for %%e in (!ENGINES!) do (
  if not defined FIRST_ENGINE set "FIRST_ENGINE=%%e"
  echo info: installing engine %%e ...
  "%INSTALL_DIR%\%BIN_NAME%" engine install %%e
  if errorlevel 1 (
    echo error: engine install failed: %%e 1>&2
    exit /b 1
  )
)

echo %PATH%| findstr /i /c:"%INSTALL_DIR%" >nul || (
  echo info: %INSTALL_DIR% is not in your PATH
  echo add for this session:  set "PATH=%INSTALL_DIR%;%%PATH%%"
)

echo.
echo dbpod installed - %INSTALL_DIR%\%BIN_NAME%
"%INSTALL_DIR%\%BIN_NAME%" version
if defined FIRST_ENGINE (
  echo get started:  dbpod run --name dev --engine %FIRST_ENGINE%
) else (
  echo get started:  dbpod engine install mysql@8.0
)
endlocal
exit /b 0

:cleanup_fail
rd /s /q "%TMPDIR%" 2>nul
exit /b 1

:help
echo dbpod installer
echo(
echo usage: curl -fsSL https://dbpod.io/install.bat -o "%%TEMP%%\dbpod-install.bat" ^&^& call "%%TEMP%%\dbpod-install.bat" [options]
echo(
echo options:
echo   --engine engine@version   also install a database engine, repeatable
echo   --version v               pin the dbpod CLI version, default: latest
echo   --install-dir dir         install location, default: %%USERPROFILE%%\.local\bin
echo   -h, --help                show this help
echo(
echo environment:
echo   DBPOD_VERSION        same as --version
echo   DBPOD_ENGINES        comma/space-separated engine refs, same as --engine
echo   DBPOD_INSTALL_DIR    same as --install-dir
echo   DBPOD_DOWNLOAD_BASE  replace the GitHub download base with a mirror URL
exit /b 0

:make_url
rem %1 = base, %2 = layout (1 = GitHub, 0 = dl.dbpod.io), %3 = file; sets URL
if "%~2"=="1" (
  if "%VERSION%"=="latest" ( set "URL=%~1/latest/download/%~3" ) else set "URL=%~1/download/%VERSION%/%~3"
) else (
  if "%VERSION%"=="latest" ( set "URL=%~1/latest/%~3" ) else set "URL=%~1/%VERSION%/%~3"
)
exit /b 0

:try_source
rem %1 = base, %2 = layout, %3 = file, %4 = output path.
rem Downloads with retries (404 fails fast - the mirror will not have the
rem file either); on success sets WIN_BASE/WIN_GH so checksums.txt comes from
rem the same origin the binary came from. A soft-404 host answers 200 with an
rem HTML page - only accept real payload content types.
call :make_url "%~1" "%~2" "%~3"
set /a TS_TRY=0
:ts_retry
set /a TS_TRY+=1
set "TS_CODE="
set "TS_CT="
for /f "tokens=1,2" %%c in ('curl -sL --connect-timeout 10 --max-time 300 -o "%~4" -w "%%{http_code} %%{content_type}" "%URL%"') do (
  set "TS_CODE=%%c"
  set "TS_CT=%%d"
)
if not "%TS_CODE%"=="200" goto ts_fail
if "%TS_CT:~0,4%"=="text" goto ts_soft404
set "WIN_BASE=%~1"
set "WIN_GH=%~2"
exit /b 0
:ts_soft404
echo info: %~1 answered with an HTML page instead of %~3 - skipping this source ...
exit /b 1
:ts_fail
if "%TS_CODE%"=="404" (
  echo info: not found on %~1, trying next source ...
  exit /b 1
)
if %TS_TRY% lss 5 (
  echo info: download from %~1 failed, retrying ...
  ping -n 3 127.0.0.1 >nul
  goto ts_retry
)
echo info: source %~1 unavailable, trying next source ...
exit /b 1
