@echo off
chcp 65001 > nul
echo ShutdownServer 빌드를 시작합니다...

:: .NET Framework 경로 확인
set "NET_PATH=C:\Windows\Microsoft.NET\Framework64\v4.0.30319"
if not exist "%NET_PATH%\csc.exe" (
    set "NET_PATH=C:\Windows\Microsoft.NET\Framework\v4.0.30319"
)

if not exist "%NET_PATH%\csc.exe" (
    echo [91m오류: .NET Framework를 찾을 수 없습니다.[0m
    echo [93m.NET Framework 4.0 이상이 설치되어 있는지 확인해주세요.[0m
    pause
    exit /b 1
)

:: C# 컴파일러로 빌드
echo [96m.NET Framework 경로: %NET_PATH%[0m
"%NET_PATH%\csc.exe" /target:winexe /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /out:ShutdownServer.exe ShutdownServer.cs

if errorlevel 1 (
    echo [91m빌드 실패![0m
    echo [93m오류를 확인하고 다시 시도해주세요.[0m
) else (
    echo [92m빌드 성공: ShutdownServer.exe가 생성되었습니다.[0m
)

pause 