using System;
using System.Net;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Drawing;
using System.Threading;

class Program
{
    [DllImport("kernel32.dll")]
    static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    const int SW_HIDE = 0;
    const int SW_SHOW = 5;

    [STAThread]
    static void Main()
    {
        // 콘솔 창 숨기기
        IntPtr hWnd = GetConsoleWindow();
        ShowWindow(hWnd, SW_HIDE);

        // Windows Forms 애플리케이션 활성화
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        // ShutdownServer 시작
        ShutdownServer server = new ShutdownServer();
        server.Start();

        // 메시지 루프 실행
        Application.Run();
    }
}

class ShutdownServer
{
    private HttpListener listener;
    private NotifyIcon trayIcon;
    private Thread serverThread;
    private bool isRunning = false;

    public void Start()
    {
        // 시스템 트레이 아이콘 생성
        CreateTrayIcon();

        // HTTP 서버 시작
        StartHttpServer();
    }

    private void CreateTrayIcon()
    {
        trayIcon = new NotifyIcon();
        trayIcon.Text = "PC 종료 서버 (포트: 8081)";
        trayIcon.Icon = SystemIcons.Information; // 파란색 정보 아이콘으로 변경 (매우 눈에 잘 띔)
        trayIcon.Visible = true;

        // 우클릭 메뉴 생성
        ContextMenuStrip contextMenu = new ContextMenuStrip();
        
        ToolStripMenuItem statusItem = new ToolStripMenuItem("상태: 실행 중");
        statusItem.Enabled = false;
        contextMenu.Items.Add(statusItem);
        
        contextMenu.Items.Add("-"); // 구분선
        
        ToolStripMenuItem exitItem = new ToolStripMenuItem("종료");
        exitItem.Click += (sender, e) => ExitApplication();
        contextMenu.Items.Add(exitItem);

        trayIcon.ContextMenuStrip = contextMenu;

        // 더블클릭 시 상태 메시지 표시
        trayIcon.DoubleClick += (sender, e) => 
        {
            MessageBox.Show("PC 종료 서버가 실행 중입니다.\n포트: 8081\n\nPOST 요청을 http://localhost:8081/shutdown 으로 보내면 PC가 종료됩니다.", 
                           "PC 종료 서버", MessageBoxButtons.OK, MessageBoxIcon.Information);
        };
    }

    private void StartHttpServer()
    {
        serverThread = new Thread(() =>
        {
            listener = new HttpListener();
            listener.Prefixes.Add("http://+:8081/");

            try
            {
                listener.Start();
                isRunning = true;
                UpdateTrayIcon("상태: 실행 중 (포트: 8081)", SystemIcons.Information);

                while (isRunning)
                {
                    try
                    {
                        HttpListenerContext context = listener.GetContext();
                        HttpListenerRequest request = context.Request;
                        HttpListenerResponse response = context.Response;

                        if (request.HttpMethod == "POST" && request.Url.AbsolutePath == "/shutdown")
                        {
                            ShowTrayMessage("종료 요청 수신", "PC 종료 명령을 실행합니다.", ToolTipIcon.Warning);
                            
                            try
                            {
                                Process.Start("shutdown", "/s /f /t 0");
                            }
                            catch (Exception ex)
                            {
                                ShowTrayMessage("오류", "shutdown 명령 실행 오류: " + ex.Message, ToolTipIcon.Error);
                            }

                            string responseText = "종료 명령 실행됨.";
                            byte[] buffer = System.Text.Encoding.UTF8.GetBytes(responseText);
                            response.ContentLength64 = buffer.Length;
                            response.OutputStream.Write(buffer, 0, buffer.Length);
                        }

                        response.Close();
                    }
                    catch (HttpListenerException)
                    {
                        // 서버가 중지될 때 발생하는 예외 무시
                        break;
                    }
                }
            }
            catch (HttpListenerException hle)
            {
                if (hle.ErrorCode == 5) // 권한 문제
                {
                    UpdateTrayIcon("상태: 오류 (권한 부족)", SystemIcons.Error);
                    ShowTrayMessage("오류", "관리자 권한으로 실행하세요.", ToolTipIcon.Error);
                }
                else if (hle.ErrorCode == 32) // 포트 사용 중
                {
                    UpdateTrayIcon("상태: 오류 (포트 사용 중)", SystemIcons.Warning);
                    ShowTrayMessage("오류", "8081 포트가 이미 사용 중입니다.", ToolTipIcon.Error);
                }
                else
                {
                    UpdateTrayIcon("상태: 오류", SystemIcons.Error);
                    ShowTrayMessage("오류", hle.Message, ToolTipIcon.Error);
                }
            }
            catch (Exception e)
            {
                UpdateTrayIcon("상태: 오류", SystemIcons.Error);
                ShowTrayMessage("오류", e.Message, ToolTipIcon.Error);
            }
        });

        serverThread.IsBackground = true;
        serverThread.Start();
    }

    private void UpdateTrayIcon(string status, Icon icon)
    {
        trayIcon.ContextMenuStrip.Items[0].Text = status;
        trayIcon.Icon = icon;
    }

    private void ShowTrayMessage(string title, string message, ToolTipIcon icon)
    {
        trayIcon.ShowBalloonTip(3000, title, message, icon);
    }

    private void ExitApplication()
    {
        isRunning = false;
        
        if (listener != null && listener.IsListening)
        {
            listener.Stop();
        }

        if (trayIcon != null)
        {
            trayIcon.Visible = false;
            trayIcon.Dispose();
        }

        Application.Exit();
    }
} 