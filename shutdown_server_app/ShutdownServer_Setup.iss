[Setup]
AppName=PC 종료 서버 (ShutdownServer)
AppVersion=1.0
AppPublisher=PC Control Solutions
DefaultDirName={autopf}\ShutdownServer
DefaultGroupName=PC 종료 서버
AllowNoIcons=yes
OutputDir=.
OutputBaseFilename=ShutdownServer_Setup
SetupIconFile=
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
DisableDirPage=yes
DisableProgramGroupPage=yes

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Files]
Source: "ShutdownServer.exe"; DestDir: "{app}"; Flags: ignoreversion

[Run]
; 방화벽 규칙 추가
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""ShutdownServer"" dir=in action=allow protocol=TCP localport=8081"; Flags: runhidden; Description: "방화벽에서 8081 포트 허용"

; ICMP 핑 허용 (IPv4)
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""Allow ICMP IPv4"" protocol=icmpv4:8,any dir=in action=allow"; Flags: runhidden; Description: "방화벽에서 ICMPv4 핑 허용"

; ICMP 핑 허용 (IPv6)  
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""Allow ICMP IPv6"" protocol=icmpv6:128,any dir=in action=allow"; Flags: runhidden; Description: "방화벽에서 ICMPv6 핑 허용"

; 시작 프로그램에 등록 (관리자 권한으로 실행되도록 VBS 스크립트 생성 및 등록)
Filename: "{sys}\cmd.exe"; Parameters: "/c echo Set UAC = CreateObject(""Shell.Application"") > ""{app}\run_as_admin.vbs"""; Flags: runhidden
Filename: "{sys}\cmd.exe"; Parameters: "/c echo UAC.ShellExecute ""{app}\ShutdownServer.exe"", """", """", ""runas"", 0 >> ""{app}\run_as_admin.vbs"""; Flags: runhidden
Filename: "reg"; Parameters: "add ""HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"" /v ""ShutdownServer"" /t REG_SZ /d ""wscript.exe \""{app}\run_as_admin.vbs\"""" /f"; Flags: runhidden

; ShutdownServer 즉시 시작
Filename: "wscript.exe"; Parameters: """{app}\run_as_admin.vbs"""; Description: "PC 종료 서버 시작"; Flags: postinstall runasoriginaluser nowait

[UninstallRun]
; 실행 중인 프로세스 종료
Filename: "taskkill"; Parameters: "/f /im ShutdownServer.exe"; Flags: runhidden

; 시작 프로그램에서 제거
Filename: "reg"; Parameters: "delete ""HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"" /v ""ShutdownServer"" /f"; Flags: runhidden

; 방화벽 규칙 제거
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""ShutdownServer"""; Flags: runhidden

; ICMP 방화벽 규칙 제거
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""Allow ICMP IPv4"""; Flags: runhidden

Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""Allow ICMP IPv6"""; Flags: runhidden

[UninstallDelete]
Type: files; Name: "{app}\run_as_admin.vbs"

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    // 기존에 실행 중인 프로세스가 있다면 종료
    Exec('taskkill', '/f /im ShutdownServer.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end; 