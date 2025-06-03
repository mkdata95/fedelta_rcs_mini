@echo off
chcp 65001 > nul

:: 기존 ShutdownServer.exe 프로세스 강제 종료
TASKKILL /IM ShutdownServer.exe /F >nul 2>&1

echo [96mShutdownServer 설치를 시작합니다...[0m

:: 프로그램 폴더 생성
mkdir "%ProgramFiles%\ShutdownServer" 2>nul
echo [92m프로그램 폴더 생성됨: %ProgramFiles%\ShutdownServer[0m

:: 실행 파일 복사
copy /Y "ShutdownServer.exe" "%ProgramFiles%\ShutdownServer\"
echo [92m실행 파일 복사됨[0m

:: 방화벽에서 8081 포트 허용 (인바운드)
echo [96m방화벽에서 8081 포트를 허용하는 중...[0m
netsh advfirewall firewall add rule name="ShutdownServer" dir=in action=allow protocol=TCP localport=8081 >nul 2>&1
if errorlevel 1 (
    echo [93m경고: 방화벽 규칙 추가에 실패했습니다. 수동으로 8081 포트를 허용해 주세요.[0m
) else (
    echo [92m방화벽에서 8081 포트 허용 완료[0m
)

:: 관리자 권한으로 실행하는 VBS 스크립트 생성
echo Set UAC = CreateObject^("Shell.Application"^) > "%ProgramFiles%\ShutdownServer\run_as_admin.vbs"
echo UAC.ShellExecute "%ProgramFiles%\ShutdownServer\ShutdownServer.exe", "", "", "runas", 1 >> "%ProgramFiles%\ShutdownServer\run_as_admin.vbs"
echo [92mVBS 스크립트 생성됨[0m

:: 시작 프로그램에 등록
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "ShutdownServer" /t REG_SZ /d "wscript.exe \"%ProgramFiles%\ShutdownServer\run_as_admin.vbs\"" /f
echo [92m시작 프로그램 등록 완료[0m

echo.
echo [92m설치가 완료되었습니다.[0m
echo [96mPC를 재시작하면 자동으로 ShutdownServer가 실행됩니다.[0m
echo [93m지금 ShutdownServer를 시작하시겠습니까? (Y/N)[0m
choice /c yn /n
if errorlevel 2 goto end
start "" "wscript.exe" "%ProgramFiles%\ShutdownServer\run_as_admin.vbs"

:end
pause 