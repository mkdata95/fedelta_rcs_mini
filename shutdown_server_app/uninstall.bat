@echo off
chcp 65001 > nul
echo [96mShutdownServer 제거를 시작합니다...[0m

:: 관리자 권한 확인
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [91m관리자 권한이 필요합니다.[0m
    echo [93m이 프로그램을 마우스 우클릭하여 "관리자 권한으로 실행"을 선택해주세요.[0m
    pause
    exit /b 1
)

:: 실행 중인 프로세스 종료 (여러 번 시도)
echo [96m실행 중인 프로세스를 종료합니다...[0m
taskkill /f /im ShutdownServer.exe >nul 2>&1
timeout /t 2 >nul
taskkill /f /im ShutdownServer.exe >nul 2>&1

:: 시작 프로그램 등록 제거
echo [96m시작 프로그램 등록을 제거합니다...[0m
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "ShutdownServer" /f >nul 2>&1
echo [92m시작 프로그램에서 제거됨[0m

:: 방화벽 규칙 제거
echo [96m방화벽 규칙을 제거하는 중...[0m
netsh advfirewall firewall delete rule name="ShutdownServer" >nul 2>&1
if errorlevel 1 (
    echo [93m경고: 방화벽 규칙 제거에 실패했습니다.[0m
) else (
    echo [92m방화벽 규칙 제거 완료[0m
)

:: 프로그램 파일 삭제 전 잠시 대기 (프로세스가 완전히 종료되기를 기다림)
timeout /t 2 >nul

:: 프로그램 파일 삭제
echo [96m프로그램 파일을 삭제합니다...[0m
if exist "%ProgramFiles%\ShutdownServer\run_as_admin.vbs" (
    del /f /q "%ProgramFiles%\ShutdownServer\run_as_admin.vbs" >nul 2>&1
)
if exist "%ProgramFiles%\ShutdownServer\ShutdownServer.exe" (
    del /f /q "%ProgramFiles%\ShutdownServer\ShutdownServer.exe" >nul 2>&1
)
if exist "%ProgramFiles%\ShutdownServer" (
    rmdir /s /q "%ProgramFiles%\ShutdownServer" >nul 2>&1
)

:: 제거 완료 확인
if exist "%ProgramFiles%\ShutdownServer" (
    echo.
    echo [91m경고: 일부 파일이 완전히 제거되지 않았을 수 있습니다.[0m
    echo [93m컴퓨터를 재시작한 후 수동으로 삭제해주세요: %ProgramFiles%\ShutdownServer[0m
) else (
    echo.
    echo [92mShutdownServer가 성공적으로 제거되었습니다.[0m
)

echo.
echo [96m컴퓨터를 재시작하면 더 이상 프로그램이 자동으로 실행되지 않습니다.[0m
echo [93m지금 컴퓨터를 재시작하시겠습니까? (Y/N)[0m
choice /c yn /n /m "선택하세요: "
if errorlevel 2 goto end
shutdown /r /t 5 /c "ShutdownServer 제거를 완료하기 위해 시스템을 재시작합니다."

:end
pause 