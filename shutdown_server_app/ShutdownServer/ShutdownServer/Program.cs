using System;
using System.Net;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;

class Program
{
    [DllImport("kernel32.dll")]
    static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    const int SW_HIDE = 0;
    const int SW_SHOW = 5;

    static void Main()
    {
        // 콘솔 창 숨기기
        // IntPtr hWnd = GetConsoleWindow();
        // ShowWindow(hWnd, SW_HIDE);

        // 서버 실행
        ShutdownServer.Run();
    }
}

class ShutdownServer
{
    public static void Run()
    {
        HttpListener listener = new HttpListener();
        listener.Prefixes.Add("http://+:8081/");

        try
        {
            listener.Start();
            Console.WriteLine("종료 서버가 실행 중입니다...");

            while (true)
            {
                HttpListenerContext context = listener.GetContext();
                HttpListenerRequest request = context.Request;
                HttpListenerResponse response = context.Response;

                if (request.HttpMethod == "POST" && request.Url.AbsolutePath == "/shutdown")
                {
                    Console.WriteLine("종료 요청을 받음.");
                    try
                    {
                        Process.Start("shutdown", "/s /f /t 0");
                        Console.WriteLine("종료 명령 실행됨.");
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine("shutdown 명령 실행 오류: " + ex.Message);
                    }

                    string responseText = "종료 명령 실행됨.";
                    byte[] buffer = System.Text.Encoding.UTF8.GetBytes(responseText);
                    response.ContentLength64 = buffer.Length;
                    response.OutputStream.Write(buffer, 0, buffer.Length);
                }

                response.Close();
            }
        }
        catch (HttpListenerException hle)
        {
            if (hle.ErrorCode == 5) // 권한 문제 (Access is denied)
            {
                Console.WriteLine("[오류] HttpListener를 시작할 수 없습니다.\n이 프로그램을 반드시 '관리자 권한'으로 실행하세요.");
            }
            else if (hle.ErrorCode == 32) // 포트 사용 중 (Address already in use)
            {
                Console.WriteLine("[오류] 8081 포트가 이미 사용 중입니다. 다른 프로그램이 해당 포트를 점유하고 있습니다.\n명령 프롬프트에서 'netstat -ano | findstr :8081'로 점유 프로세스를 확인하세요.");
            }
            else
            {
                Console.WriteLine($"[HttpListener 오류] {hle.Message}");
            }
        }
        catch (Exception e)
        {
            Console.WriteLine("오류 발생: " + e.Message);
        }
        finally
        {
            listener.Stop();
        }
    }
}