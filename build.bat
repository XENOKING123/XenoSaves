@echo off
setlocal EnableExtensions EnableDelayedExpansion
title GarlicTransfer - Windows build
cd /d "%~dp0"

rem ============================================================================
rem  GarlicTransfer Windows build
rem
rem  Mirrors .github/workflows/build.yml (build-windows):
rem      npm ci
rem      npx electron-builder --win --publish never
rem  Output: dist\GarlicTransfer Setup <version>.exe  (NSIS installer)
rem
rem  Usage:
rem      build.bat                  full build (checks + tests + installer)
rem      build.bat notest           skip the node/python test suites
rem      build.bat embed            also bundle a private Python runtime, so the
rem                                 installer does not need Python on the target PC
rem      build.bat embed notest     both
rem
rem  Requirements: Node.js 18+ (CI uses 22), and Python 3.10+ for the tests.
rem  The first electron-builder run downloads Electron + winCodeSign from GitHub,
rem  so it needs network access and can take several minutes.
rem ============================================================================

set "EMBED=0"
set "RUNTESTS=1"
for %%A in (%*) do (
    if /i "%%~A"=="embed"  set "EMBED=1"
    if /i "%%~A"=="notest" set "RUNTESTS=0"
)

echo ============================================
echo   GarlicTransfer - Windows build
echo   embed python : %EMBED%
echo   run tests    : %RUNTESTS%
echo ============================================
echo.

rem ---------------------------------------------------------------- preflight
where node >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Node.js was not found on PATH.
    echo         Install Node.js 18 or newer from https://nodejs.org and reopen this shell.
    goto :fail
)
for /f "delims=" %%v in ('node -v') do set "NODEVER=%%v"
echo [OK] node %NODEVER%

where npm >nul 2>&1
if errorlevel 1 (
    echo [ERROR] npm was not found on PATH ^(it ships with Node.js^).
    goto :fail
)
for /f "delims=" %%v in ('npm -v') do echo [OK] npm %%v

where python >nul 2>&1
if errorlevel 1 (
    echo [WARN] Python was not found on PATH.
    echo        The tests will be skipped, and unless you build with "embed" the
    echo        installed app will need Python 3.10+ with "cryptography" to run.
    set "HAVEPY=0"
) else (
    set "HAVEPY=1"
    for /f "tokens=2 delims= " %%v in ('python --version 2^>^&1') do echo [OK] python %%v
    python -c "import cryptography" >nul 2>&1
    if errorlevel 1 (
        echo [WARN] the Python "cryptography" package is missing:
        echo          python -m pip install -r requirements.txt
        echo        Needed for the tests, and at runtime unless you build with "embed".
    ) else (
        echo [OK] python cryptography
    )
)

if not exist package-lock.json (
    echo [ERROR] package-lock.json is missing, so "npm ci" cannot run.
    echo         Restore it from the repository, or change npm ci to npm install below.
    goto :fail
)

rem ------------------------------------------------------------ dependencies
echo.
echo [BUILD] npm ci
call npm ci
if errorlevel 1 (
    echo [ERROR] npm ci failed.
    goto :fail
)

rem ------------------------------------------------------------------ checks
if "%RUNTESTS%"=="1" (
    echo.
    echo [CHECK] npm run check  ^(syntax-check every electron file^)
    call npm run check
    if errorlevel 1 goto :fail

    echo [CHECK] node --test
    call node --test tests/account_id.test.cjs tests/pairing_store.test.cjs
    if errorlevel 1 goto :fail

    if "%HAVEPY%"=="1" (
        echo [CHECK] python -m py_compile
        python -m py_compile poc/dt_backend.py poc/dt_download.py poc/dt_metadata.py poc/dt_source.py poc/dt_discovery.py poc/dt_pair.py poc/dt_ppr_power.py
        if errorlevel 1 goto :fail

        echo [CHECK] python -m unittest
        python -m unittest discover -s tests -p "test_*.py"
        if errorlevel 1 goto :fail
    ) else (
        echo [CHECK] skipped the Python checks ^(no python on PATH^)
    )
) else (
    echo.
    echo [CHECK] skipped ^(notest^)
)

rem ------------------------------------------------- optional bundled python
if "%EMBED%"=="1" (
    call :embed_python
    if errorlevel 1 goto :fail
)

rem --------------------------------------------- winCodeSign cache (Windows)
call :ensure_wincodesign
if errorlevel 1 goto :fail

rem ------------------------------------------------------------------- build
echo.
echo [BUILD] electron-builder --win
if "%EMBED%"=="1" (
    call npx electron-builder --win --publish never --config electron-builder.embed.js
) else (
    call npx electron-builder --win --publish never
)
if errorlevel 1 (
    echo.
    echo [ERROR] electron-builder failed.
    echo         First runs download Electron and winCodeSign from GitHub; if that
    echo         timed out, just run this again. If you are behind a proxy, set
    echo         HTTPS_PROXY before building.
    goto :fail
)

rem ------------------------------------------------------------------ report
echo.
echo ============================================
echo   BUILD OK
echo ============================================
if exist dist (
    for %%F in (dist\*.exe) do echo   %%~nxF   ^(%%~zF bytes^)
    echo.
    echo   Installer: dist\
) else (
    echo   [WARN] no dist folder was produced
)
if "%EMBED%"=="0" (
    echo.
    echo   NOTE: the app runs its Python backend with "python" from PATH
    echo         ^(electron/paths.cjs falls back to it when resources\python is
    echo         absent^). The target PC needs Python 3.10+ with:
    echo             python -m pip install cryptography
    echo         Build with "build.bat embed" to bundle a private runtime instead.
)
echo ============================================
pause
exit /b 0


rem ============================================================================
rem  Bundle a private, self-contained Python into build\python so that
rem  electron/paths.cjs pythonBin() finds resources\python\python.exe.
rem ============================================================================
:embed_python
set "PYVER=3.12.7"
set "PYDIR=build\python"
set "PYZIP=%TEMP%\python-%PYVER%-embed-amd64.zip"
set "GETPIP=%TEMP%\get-pip.py"

echo.
echo [EMBED] bundling Python %PYVER% into %PYDIR%
if exist "%PYDIR%\python.exe" (
    echo [EMBED] %PYDIR%\python.exe already exists - reusing it
    goto :fix_pth
)
if not exist build mkdir build
if exist "%PYDIR%" rmdir /s /q "%PYDIR%"

echo [EMBED] downloading the embeddable runtime
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/%PYVER%/python-%PYVER%-embed-amd64.zip' -OutFile '%PYZIP%'"
if errorlevel 1 (
    echo [ERROR] could not download Python %PYVER%. Build without "embed", or place
    echo         an embeddable runtime in %PYDIR% yourself and re-run.
    exit /b 1
)

echo [EMBED] extracting
tar -xf "%PYZIP%" -C "%PYDIR%" 2>nul
if not exist "%PYDIR%\python.exe" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%PYZIP%' -DestinationPath '%PYDIR%' -Force"
)
if not exist "%PYDIR%\python.exe" (
    echo [ERROR] extraction did not produce %PYDIR%\python.exe
    exit /b 1
)

:fix_pth
rem Two things the embeddable runtime needs in its ._pth file, because when that
rem file exists Python builds sys.path from it ALONE and ignores PYTHONPATH:
rem   * "import site"  - otherwise pip-installed packages are not importable
rem   * ".."            - the installed resources folder, i.e. the parent of
rem                        python\.  main.cjs spawns the backend with
rem                        PYTHONPATH=resources so that "poc" resolves; the bundled
rem                        interpreter cannot see that variable, so the same
rem                        directory has to be listed here instead.  Without it
rem                        every backend call dies with
rem                        "No module named 'poc'".
echo [EMBED] configuring the ._pth file ^(site-packages + the resources root^)
for %%P in ("%PYDIR%\python*._pth") do (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$p='%%~fP';" ^
      "$lines=@(Get-Content $p) -replace '^#\s*import site','import site';" ^
      "if ($lines -notcontains '..') { $lines += '..' };" ^
      "Set-Content -Path $p -Value $lines"
)
type "%PYDIR%\python312._pth" 2>nul | findstr /r /c:"^\.\.$" >nul
if errorlevel 1 (
    echo [ERROR] the ._pth file was not updated with the resources root
    exit /b 1
)

if not exist "%PYDIR%\Lib\site-packages\cryptography" (
    echo [EMBED] installing pip
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "Invoke-WebRequest -Uri 'https://bootstrap.pypa.io/get-pip.py' -OutFile '%GETPIP%'"
    if errorlevel 1 (
        echo [ERROR] could not download get-pip.py
        exit /b 1
    )
    "%PYDIR%\python.exe" "%GETPIP%" --no-warn-script-location
    if errorlevel 1 (
        echo [ERROR] get-pip.py failed
        exit /b 1
    )

    echo [EMBED] installing the backend requirements
    "%PYDIR%\python.exe" -m pip install --no-warn-script-location -r requirements.txt
    if errorlevel 1 (
        echo [ERROR] pip install -r requirements.txt failed
        exit /b 1
    )
) else (
    echo [EMBED] cryptography is already installed - skipping pip
)

echo [EMBED] verifying
"%PYDIR%\python.exe" -c "import cryptography, sys; print('  python', sys.version.split()[0], '+ cryptography', cryptography.__version__)"
if errorlevel 1 (
    echo [ERROR] the bundled runtime cannot import cryptography
    exit /b 1
)

:embed_done
rem Keep the bundle out of any archive of the source tree
findstr /i /c:"build/python" .gitignore >nul 2>&1
if errorlevel 1 echo build/python/>> .gitignore
exit /b 0


rem ============================================================================
rem  Seed the winCodeSign cache ourselves.
rem
rem  winCodeSign-2.6.0.7z contains two macOS symlinks (darwin/10.12/lib/
rem  libcrypto.dylib and libssl.dylib).  Creating a symlink on Windows needs
rem  SeCreateSymbolicLinkPrivilege, so unless Developer Mode is on or the shell
rem  is elevated, 7za exits with an error and electron-builder aborts the whole
rem  build - even though nothing is being signed and those two files are never
rem  used on Windows.  Extracting manually and tolerating that error avoids
rem  needing admin rights.
rem ============================================================================
:ensure_wincodesign
set "WCSVER=2.6.0"
set "WCSCACHE=%LOCALAPPDATA%\electron-builder\Cache\winCodeSign"
set "WCSDIR=%WCSCACHE%\winCodeSign-%WCSVER%"
set "WCSOK=%WCSDIR%\windows-10\x64\signtool.exe"
if exist "%WCSOK%" exit /b 0

echo.
echo [PREP] seeding the winCodeSign %WCSVER% cache
echo        ^(electron-builder's own extraction aborts on two macOS symlinks in
echo         this archive unless Developer Mode or admin rights allow symlinks^)
if not exist "%WCSCACHE%" mkdir "%WCSCACHE%"

set "SEVENZIP=node_modules\7zip-bin\win\x64\7za.exe"
if not exist "%SEVENZIP%" (
    echo [PREP] 7zip-bin is not installed yet; letting electron-builder try on its own.
    echo        If it fails on "Cannot create symbolic link", enable Windows
    echo        Developer Mode or re-run this script from an Administrator prompt.
    exit /b 0
)

rem Reuse a copy electron-builder already downloaded, otherwise fetch it
set "WCSZIP="
for %%F in ("%WCSCACHE%\*.7z") do if not defined WCSZIP set "WCSZIP=%%~fF"
if not defined WCSZIP (
    set "WCSZIP=%TEMP%\winCodeSign-%WCSVER%.7z"
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
      "Invoke-WebRequest -Uri 'https://github.com/electron-userland/electron-builder-binaries/releases/download/winCodeSign-%WCSVER%/winCodeSign-%WCSVER%.7z' -OutFile '%TEMP%\winCodeSign-%WCSVER%.7z'"
    if not exist "%TEMP%\winCodeSign-%WCSVER%.7z" (
        echo [ERROR] could not download winCodeSign-%WCSVER%.7z
        exit /b 1
    )
    set "WCSZIP=%TEMP%\winCodeSign-%WCSVER%.7z"
)

if exist "%WCSDIR%" rmdir /s /q "%WCSDIR%"
"%SEVENZIP%" x -bd -y "%WCSZIP%" "-o%WCSDIR%" >nul 2>&1
rem exit code 2 here is just the two darwin symlinks; the Windows payload is complete
if not exist "%WCSOK%" (
    echo [ERROR] extracting winCodeSign did not produce %WCSOK%
    echo         Enable Windows Developer Mode, or run this script as Administrator.
    exit /b 1
)
echo [PREP] winCodeSign ready at %WCSDIR%
exit /b 0


:fail
echo.
echo ============================================
echo   BUILD FAILED - see the message above
echo ============================================
pause
exit /b 1
