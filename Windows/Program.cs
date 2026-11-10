using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace PlanificadorPersonal
{
    static class Program
    {
        private static string DataFolder;
        private static string DataFilePath;
        private static string EmbeddedHtml;
        private static string EmbeddedSeedJson;
        private static DateTime LastActivity = DateTime.UtcNow;

        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            DataFolder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "Planificador"
            );
            Directory.CreateDirectory(DataFolder);
            DataFilePath = Path.Combine(DataFolder, "planner.json");

            EmbeddedHtml = ReadResource("Planificador.app.html");
            EmbeddedSeedJson = ReadResource("Planificador.seed.json");

            if (!string.IsNullOrEmpty(EmbeddedSeedJson))
            {
                EmbeddedHtml = EmbeddedHtml.Replace("__INITIAL_SEED_JSON__", EmbeddedSeedJson);
                if (!File.Exists(DataFilePath))
                {
                    try { File.WriteAllText(DataFilePath, EmbeddedSeedJson, Encoding.UTF8); }
                    catch { }
                }
            }

            TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;
            string url = "http://127.0.0.1:" + port + "/";

            Thread serverThread = new Thread(() => ServeForever(listener));
            serverThread.IsBackground = true;
            serverThread.Start();

            Process browserProc = LaunchAppWindow(url);

            if (browserProc != null)
            {
                // Wait while the app window or connections are active
                while (!browserProc.HasExited || (DateTime.UtcNow - LastActivity).TotalMinutes < 5)
                {
                    Thread.Sleep(2000);
                    if (browserProc.HasExited && (DateTime.UtcNow - LastActivity).TotalSeconds > 25)
                        break;
                }
            }
            else
            {
                // Keep server alive for 12 hours if launched via default shell handler
                Thread.Sleep(TimeSpan.FromHours(12));
            }
        }

        private static string ReadResource(string name)
        {
            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream s = asm.GetManifestResourceStream(name))
            {
                if (s == null) return "";
                using (StreamReader sr = new StreamReader(s, Encoding.UTF8))
                {
                    return sr.ReadToEnd();
                }
            }
        }

        private static Process LaunchAppWindow(string url)
        {
            string[] candidates = new string[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Microsoft\Edge\Application\msedge.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Microsoft\Edge\Application\msedge.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Google\Chrome\Application\chrome.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Google\Chrome\Application\chrome.exe")
            };

            string userProfileDir = Path.Combine(DataFolder, "WindowProfile");
            Directory.CreateDirectory(userProfileDir);

            foreach (string exe in candidates)
            {
                if (File.Exists(exe))
                {
                    try
                    {
                        ProcessStartInfo psi = new ProcessStartInfo
                        {
                            FileName = exe,
                            Arguments = "--app=\"" + url + "\" --window-size=1380,880 --user-data-dir=\"" + userProfileDir + "\" --no-first-run --disable-extensions",
                            UseShellExecute = false
                        };
                        return Process.Start(psi);
                    }
                    catch { }
                }
            }

            try
            {
                return Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            }
            catch
            {
                return null;
            }
        }

        private static void ServeForever(TcpListener listener)
        {
            while (true)
            {
                try
                {
                    TcpClient client = listener.AcceptTcpClient();
                    ThreadPool.QueueUserWorkItem(_ => HandleClient(client));
                }
                catch { }
            }
        }

        private static void HandleClient(TcpClient client)
        {
            LastActivity = DateTime.UtcNow;
            using (client)
            using (NetworkStream stream = client.GetStream())
            {
                stream.ReadTimeout = 10000;
                stream.WriteTimeout = 10000;

                try
                {
                    // Read HTTP header
                    MemoryStream headerBuf = new MemoryStream();
                    int b;
                    int matchState = 0;
                    while ((b = stream.ReadByte()) != -1)
                    {
                        headerBuf.WriteByte((byte)b);
                        if ((matchState == 0 && b == '\r') ||
                            (matchState == 1 && b == '\n') ||
                            (matchState == 2 && b == '\r') ||
                            (matchState == 3 && b == '\n'))
                        {
                            matchState++;
                            if (matchState == 4) break;
                        }
                        else
                        {
                            matchState = (b == '\r') ? 1 : 0;
                        }
                        if (headerBuf.Length > 65536) break;
                    }

                    string headerText = Encoding.ASCII.GetString(headerBuf.ToArray());
                    string[] lines = headerText.Split(new string[] { "\r\n" }, StringSplitOptions.None);
                    if (lines.Length == 0) return;

                    string[] reqParts = lines[0].Split(' ');
                    if (reqParts.Length < 2) return;
                    string method = reqParts[0].ToUpperInvariant();
                    string path = reqParts[1];

                    int contentLength = 0;
                    foreach (string line in lines)
                    {
                        if (line.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
                        {
                            int.TryParse(line.Substring(15).Trim(), out contentLength);
                        }
                    }

                    byte[] bodyBytes = new byte[contentLength];
                    int readTotal = 0;
                    while (readTotal < contentLength)
                    {
                        int n = stream.Read(bodyBytes, readTotal, contentLength - readTotal);
                        if (n <= 0) break;
                        readTotal += n;
                    }

                    if (method == "GET" && path.StartsWith("/api/data"))
                    {
                        string json = "{}";
                        if (File.Exists(DataFilePath))
                        {
                            json = File.ReadAllText(DataFilePath, Encoding.UTF8);
                        }
                        else if (!string.IsNullOrEmpty(EmbeddedSeedJson))
                        {
                            json = EmbeddedSeedJson;
                        }
                        WriteResponse(stream, "200 OK", "application/json; charset=utf-8", Encoding.UTF8.GetBytes(json));
                    }
                    else if (method == "POST" && path.StartsWith("/api/data"))
                    {
                        string body = Encoding.UTF8.GetString(bodyBytes, 0, readTotal);
                        if (!string.IsNullOrWhiteSpace(body) && body.TrimStart().StartsWith("{"))
                        {
                            string tmp = DataFilePath + ".tmp";
                            File.WriteAllText(tmp, body, Encoding.UTF8);
                            if (File.Exists(DataFilePath)) File.Delete(DataFilePath);
                            File.Move(tmp, DataFilePath);
                        }
                        WriteResponse(stream, "200 OK", "application/json; charset=utf-8", Encoding.UTF8.GetBytes("{\"ok\":true}"));
                    }
                    else
                    {
                        WriteResponse(stream, "200 OK", "text/html; charset=utf-8", Encoding.UTF8.GetBytes(EmbeddedHtml));
                    }
                }
                catch { }
            }
        }

        private static void WriteResponse(NetworkStream stream, string status, string contentType, byte[] payload)
        {
            string headers =
                "HTTP/1.1 " + status + "\r\n" +
                "Content-Type: " + contentType + "\r\n" +
                "Content-Length: " + payload.Length + "\r\n" +
                "Cache-Control: no-store\r\n" +
                "Connection: close\r\n\r\n";
            byte[] headerBytes = Encoding.ASCII.GetBytes(headers);
            stream.Write(headerBytes, 0, headerBytes.Length);
            stream.Write(payload, 0, payload.Length);
            stream.Flush();
        }
    }
}
