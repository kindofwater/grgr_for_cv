@echo off
setlocal
REM SSC + KUPID future-only pipeline. The scheduled tasks stay disabled until validation.
set "ROOT=%~dp0.."
set "LOGDIR=%~dp0logs"
set "SUCCESS_MARKER=%~dp0daily_success_date.txt"
set "STATUS=%ROOT%\data\crawl_status.json"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set "TODAY=%%D"
set "LOGFILE=%LOGDIR%\crawler-%TODAY%.log"
cd /d "%ROOT%"
set "PYTHONIOENCODING=utf-8"
if "%CRAWLER_PARSE_MODEL%"=="" set "CRAWLER_PARSE_MODEL=claude-sonnet-5-5"
set "PYTHON=%ROOT%\.venv\Scripts\python.exe"

powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%LOGDIR%' -File -ErrorAction SilentlyContinue | Where-Object LastWriteTime -lt (Get-Date).AddDays(-7) | Remove-Item -Force" >nul 2>&1
echo ==== run started %date% %time% ====>>"%LOGFILE%"

if not exist "%PYTHON%" (
  echo [FAIL] missing virtualenv python>>"%LOGFILE%"
  goto :fail
)

"%PYTHON%" crawling_scripts\crawl_both.py --incremental --auto >>"%LOGFILE%" 2>&1
set "CRAWL_EXIT=%ERRORLEVEL%"

"%PYTHON%" crawling_scripts\crawler_pipeline\cli.py >>"%LOGFILE%" 2>&1
set "PROCESS_EXIT=%ERRORLEVEL%"

if not "%PROCESS_EXIT%"=="0" goto :partial
"%PYTHON%" crawling_scripts\audit_worksite_norm.py >>"%LOGFILE%" 2>&1
if errorlevel 1 goto :partial

REM Everytime is a supplementary source: a failure here must not undo the core
REM pipeline, but it must never fail silently either. It also runs when the SSC/KUPID
REM crawl failed (e.g. SSO login blocked) so one broken source does not stall the other.
"%PYTHON%" crawling_scripts\everytime_crawler.py >>"%LOGFILE%" 2>&1
if errorlevel 1 goto :everytime_failed
"%PYTHON%" crawling_scripts\manual_postings.py data\manual_everytime_postings.json >>"%LOGFILE%" 2>&1
if errorlevel 1 goto :everytime_failed
goto :everytime_done
:everytime_failed
echo [EVERYTIME-FAIL] everytime path failed, core pipeline kept %date% %time%>>"%LOGFILE%"
:everytime_done

if not "%CRAWL_EXIT%"=="0" goto :partial
echo [OK] daily pipeline done %date% %time%>>"%LOGFILE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Date -Format yyyy-MM-dd | Set-Content -Encoding ascii -LiteralPath '%SUCCESS_MARKER%'"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','crawling_scripts\show_crawler_notification.ps1','-Kind','success'"
exit /b 0

:partial
echo [PARTIAL] crawl=%CRAWL_EXIT% process=%PROCESS_EXIT% %date% %time%>>"%LOGFILE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','crawling_scripts\show_crawler_notification.ps1','-Kind','partial'"
exit /b 1

:fail
echo [FAIL] daily pipeline aborted %date% %time%>>"%LOGFILE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','crawling_scripts\show_crawler_notification.ps1','-Kind','fail'"
exit /b 1
