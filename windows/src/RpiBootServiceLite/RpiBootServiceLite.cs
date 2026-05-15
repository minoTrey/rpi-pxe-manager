using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace RpiBootServiceLite
{
    internal static class Program
    {
        private static readonly object LogLock = new object();
        private static volatile bool running = true;
        private static string logPath = "";

        private static readonly byte[] Option43 = new byte[]
        {
            0x06, 0x01, 0x03, 0x0A, 0x04, 0x00, 0x50, 0x58,
            0x45, 0x09, 0x14, 0x00, 0x00, 0x11, 0x52, 0x61,
            0x73, 0x70, 0x62, 0x65, 0x72, 0x72, 0x79, 0x20,
            0x50, 0x69, 0x20, 0x42, 0x6F, 0x6F, 0x74, 0xFF
        };

        private static int Main(string[] args)
        {
            Dictionary<string, string> options = ParseArgs(args);
            if (options.ContainsKey("help") || !options.ContainsKey("leases") || !options.ContainsKey("server") || !options.ContainsKey("tftp"))
            {
                PrintUsage();
                return options.ContainsKey("help") ? 0 : 2;
            }

            string leasesPath = options["leases"];
            string serverIpText = options["server"];
            string routerIpText = GetOption(options, "router", serverIpText);
            string dnsIpText = GetOption(options, "dns", routerIpText);
            string subnetText = GetOption(options, "subnet", "255.255.255.0");
            string tftpRoot = Path.GetFullPath(options["tftp"]);
            string bootFile = GetOption(options, "bootfile", "");
            logPath = GetOption(options, "log", "");
            bool enableDhcp = options.ContainsKey("dhcp") || !options.ContainsKey("tftp-only");
            bool enableTftp = options.ContainsKey("tftp") || !options.ContainsKey("dhcp-only");

            IPAddress serverIp = IPAddress.Parse(serverIpText);
            IPAddress routerIp = IPAddress.Parse(routerIpText);
            IPAddress dnsIp = IPAddress.Parse(dnsIpText);
            IPAddress subnetMask = IPAddress.Parse(subnetText);
            IPAddress broadcastIp = GetBroadcast(serverIp, subnetMask);
            Dictionary<string, Lease> leases = LoadLeases(leasesPath);

            Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e)
            {
                e.Cancel = true;
                running = false;
            };

            Log("RPI Boot Service Lite starting");
            Log("Server=" + serverIp + " Router=" + routerIp + " DNS=" + dnsIp + " TFTP=" + tftpRoot);
            Log("Static leases=" + leases.Count);

            List<Thread> threads = new List<Thread>();
            if (enableDhcp)
            {
                DhcpServer dhcp = new DhcpServer(leases, serverIp, routerIp, dnsIp, subnetMask, broadcastIp, bootFile, Option43, Log, IsRunning);
                Thread t = new Thread(dhcp.Run);
                t.IsBackground = true;
                t.Start();
                threads.Add(t);
            }

            if (enableTftp)
            {
                TftpServer tftp = new TftpServer(tftpRoot, Log, IsRunning);
                Thread t = new Thread(tftp.Run);
                t.IsBackground = true;
                t.Start();
                threads.Add(t);
            }

            while (running)
            {
                Thread.Sleep(500);
            }

            Log("RPI Boot Service Lite stopping");
            return 0;
        }

        private static bool IsRunning()
        {
            return running;
        }

        private static string GetOption(Dictionary<string, string> options, string name, string fallback)
        {
            string value;
            return options.TryGetValue(name, out value) ? value : fallback;
        }

        private static Dictionary<string, string> ParseArgs(string[] args)
        {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < args.Length; i++)
            {
                string arg = args[i];
                if (!arg.StartsWith("--")) continue;
                string name = arg.Substring(2);
                string value = "true";
                int eq = name.IndexOf('=');
                if (eq >= 0)
                {
                    value = name.Substring(eq + 1);
                    name = name.Substring(0, eq);
                }
                else if (i + 1 < args.Length && !args[i + 1].StartsWith("--"))
                {
                    value = args[++i];
                }
                result[name] = value;
            }
            return result;
        }

        private static void PrintUsage()
        {
            Console.WriteLine("RpiBootServiceLite --leases leases.tsv --server 10.73.0.10 --router 10.73.0.1 --dns 10.73.0.1 --tftp D:\\tftp --dhcp");
        }

        private static Dictionary<string, Lease> LoadLeases(string path)
        {
            Dictionary<string, Lease> leases = new Dictionary<string, Lease>(StringComparer.OrdinalIgnoreCase);
            foreach (string raw in File.ReadAllLines(path))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                string[] parts = line.Split('\t');
                if (parts.Length < 2) continue;
                Lease lease = new Lease();
                lease.Mac = NormalizeMac(parts[0]);
                lease.Ip = IPAddress.Parse(parts[1]);
                lease.Hostname = parts.Length > 2 ? parts[2] : "";
                lease.Serial = parts.Length > 3 ? parts[3] : "";
                leases[lease.Mac] = lease;
            }
            return leases;
        }

        private static string NormalizeMac(string value)
        {
            StringBuilder sb = new StringBuilder();
            foreach (char c in value)
            {
                if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))
                {
                    sb.Append(char.ToLowerInvariant(c));
                }
            }
            if (sb.Length != 12) return value.ToLowerInvariant();
            return sb.ToString(0, 2) + ":" + sb.ToString(2, 2) + ":" + sb.ToString(4, 2) + ":" +
                   sb.ToString(6, 2) + ":" + sb.ToString(8, 2) + ":" + sb.ToString(10, 2);
        }

        private static IPAddress GetBroadcast(IPAddress address, IPAddress mask)
        {
            byte[] ip = address.GetAddressBytes();
            byte[] m = mask.GetAddressBytes();
            byte[] b = new byte[4];
            for (int i = 0; i < 4; i++) b[i] = (byte)(ip[i] | (m[i] ^ 255));
            return new IPAddress(b);
        }

        private static void Log(string message)
        {
            string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss ") + message;
            lock (LogLock)
            {
                Console.WriteLine(line);
                if (logPath.Length > 0)
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(logPath));
                    File.AppendAllText(logPath, line + Environment.NewLine, Encoding.UTF8);
                }
            }
        }
    }

    internal sealed class Lease
    {
        public string Mac;
        public IPAddress Ip;
        public string Hostname;
        public string Serial;
    }

    internal sealed class DhcpServer
    {
        private readonly Dictionary<string, Lease> leases;
        private readonly IPAddress serverIp;
        private readonly IPAddress routerIp;
        private readonly IPAddress dnsIp;
        private readonly IPAddress subnetMask;
        private readonly IPAddress broadcastIp;
        private readonly string bootFile;
        private readonly byte[] option43;
        private readonly Action<string> log;
        private readonly Func<bool> isRunning;

        public DhcpServer(Dictionary<string, Lease> leases, IPAddress serverIp, IPAddress routerIp, IPAddress dnsIp, IPAddress subnetMask, IPAddress broadcastIp, string bootFile, byte[] option43, Action<string> log, Func<bool> isRunning)
        {
            this.leases = leases;
            this.serverIp = serverIp;
            this.routerIp = routerIp;
            this.dnsIp = dnsIp;
            this.subnetMask = subnetMask;
            this.broadcastIp = broadcastIp;
            this.bootFile = bootFile ?? "";
            this.option43 = option43;
            this.log = log;
            this.isRunning = isRunning;
        }

        public void Run()
        {
            Socket socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            socket.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            socket.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.Broadcast, true);
            socket.Bind(new IPEndPoint(IPAddress.Any, 67));
            UdpClient udp = new UdpClient();
            udp.Client = socket;
            log("DHCP listening on UDP 67");
            IPEndPoint remote = new IPEndPoint(IPAddress.Any, 0);

            while (isRunning())
            {
                try
                {
                    byte[] packet = udp.Receive(ref remote);
                    ThreadPool.QueueUserWorkItem(delegate { HandlePacket(udp, packet); });
                }
                catch (SocketException ex)
                {
                    if (isRunning()) log("DHCP socket error: " + ex.Message);
                }
                catch (Exception ex)
                {
                    if (isRunning()) log("DHCP error: " + ex.Message);
                }
            }
        }

        private void HandlePacket(UdpClient udp, byte[] request)
        {
            if (request.Length < 240) return;
            int hlen = request[2];
            if (hlen < 1 || hlen > 16) return;
            string mac = ReadMac(request, hlen);
            int msgType = ReadDhcpMessageType(request);
            if (msgType != 1 && msgType != 3) return;

            Lease lease;
            if (!leases.TryGetValue(mac, out lease))
            {
                log("DHCP ignored unknown MAC " + mac);
                return;
            }

            int replyType = msgType == 1 ? 2 : 5;
            byte[] response = BuildResponse(request, lease, replyType);
            udp.Send(response, response.Length, new IPEndPoint(IPAddress.Broadcast, 68));
            log("DHCP " + (replyType == 2 ? "OFFER " : "ACK ") + mac + " -> " + lease.Ip);
        }

        private static string ReadMac(byte[] request, int hlen)
        {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < hlen; i++)
            {
                if (i > 0) sb.Append(":");
                sb.Append(request[28 + i].ToString("x2"));
            }
            return sb.ToString();
        }

        private static int ReadDhcpMessageType(byte[] request)
        {
            int i = 240;
            while (i < request.Length)
            {
                int code = request[i++];
                if (code == 0) continue;
                if (code == 255) break;
                if (i >= request.Length) break;
                int len = request[i++];
                if (i + len > request.Length) break;
                if (code == 53 && len > 0) return request[i];
                i += len;
            }
            return 0;
        }

        private byte[] BuildResponse(byte[] request, Lease lease, int replyType)
        {
            byte[] response = new byte[1500];
            response[0] = 2;
            response[1] = request[1];
            response[2] = request[2];
            response[3] = 0;
            Array.Copy(request, 4, response, 4, 4);
            Array.Copy(request, 8, response, 8, 4);
            CopyIp(lease.Ip, response, 16);
            CopyIp(serverIp, response, 20);
            Array.Copy(request, 28, response, 28, 16);
            if (bootFile.Length > 0) WriteAscii(response, 108, 128, bootFile);
            response[236] = 99;
            response[237] = 130;
            response[238] = 83;
            response[239] = 99;

            int offset = 240;
            AddOption(response, ref offset, 53, new byte[] { (byte)replyType });
            AddOption(response, ref offset, 54, serverIp.GetAddressBytes());
            AddOption(response, ref offset, 51, UInt32Bytes(86400));
            AddOption(response, ref offset, 58, UInt32Bytes(43200));
            AddOption(response, ref offset, 59, UInt32Bytes(75600));
            AddOption(response, ref offset, 1, subnetMask.GetAddressBytes());
            AddOption(response, ref offset, 3, routerIp.GetAddressBytes());
            AddOption(response, ref offset, 6, dnsIp.GetAddressBytes());
            AddOption(response, ref offset, 28, broadcastIp.GetAddressBytes());
            AddOption(response, ref offset, 43, option43);
            AddOption(response, ref offset, 66, Encoding.ASCII.GetBytes(serverIp.ToString()));
            if (bootFile.Length > 0) AddOption(response, ref offset, 67, Encoding.ASCII.GetBytes(bootFile));
            response[offset++] = 255;

            byte[] exact = new byte[offset];
            Array.Copy(response, exact, offset);
            return exact;
        }

        private static void CopyIp(IPAddress ip, byte[] target, int offset)
        {
            Array.Copy(ip.GetAddressBytes(), 0, target, offset, 4);
        }

        private static byte[] UInt32Bytes(uint value)
        {
            return new byte[]
            {
                (byte)((value >> 24) & 255),
                (byte)((value >> 16) & 255),
                (byte)((value >> 8) & 255),
                (byte)(value & 255)
            };
        }

        private static void AddOption(byte[] target, ref int offset, byte code, byte[] value)
        {
            target[offset++] = code;
            target[offset++] = (byte)value.Length;
            Array.Copy(value, 0, target, offset, value.Length);
            offset += value.Length;
        }

        private static void WriteAscii(byte[] target, int offset, int max, string value)
        {
            byte[] bytes = Encoding.ASCII.GetBytes(value);
            int count = Math.Min(max - 1, bytes.Length);
            Array.Copy(bytes, 0, target, offset, count);
        }
    }

    internal sealed class TftpServer
    {
        private readonly string root;
        private readonly Action<string> log;
        private readonly Func<bool> isRunning;

        public TftpServer(string root, Action<string> log, Func<bool> isRunning)
        {
            this.root = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            this.log = log;
            this.isRunning = isRunning;
        }

        public void Run()
        {
            UdpClient udp = new UdpClient(new IPEndPoint(IPAddress.Any, 69));
            log("TFTP listening on UDP 69 root=" + root);
            IPEndPoint remote = new IPEndPoint(IPAddress.Any, 0);

            while (isRunning())
            {
                try
                {
                    byte[] packet = udp.Receive(ref remote);
                    if (packet.Length >= 2 && packet[0] == 0 && packet[1] == 1)
                    {
                        byte[] copy = new byte[packet.Length];
                        Array.Copy(packet, copy, packet.Length);
                        IPEndPoint client = new IPEndPoint(remote.Address, remote.Port);
                        ThreadPool.QueueUserWorkItem(delegate { ServeReadRequest(copy, client); });
                    }
                }
                catch (SocketException ex)
                {
                    if (isRunning()) log("TFTP socket error: " + ex.Message);
                }
                catch (Exception ex)
                {
                    if (isRunning()) log("TFTP error: " + ex.Message);
                }
            }
        }

        private void ServeReadRequest(byte[] request, IPEndPoint client)
        {
            string fileName;
            string mode;
            Dictionary<string, string> options;
            if (!ParseRrq(request, out fileName, out mode, out options))
            {
                return;
            }

            string path = ResolvePath(fileName);
            if (path == null || !File.Exists(path))
            {
                SendError(client, 1, "File not found");
                log("TFTP MISS " + client + " " + fileName);
                return;
            }

            int blockSize = 512;
            string requestedBlockSize;
            if (options.TryGetValue("blksize", out requestedBlockSize))
            {
                int parsed;
                if (Int32.TryParse(requestedBlockSize, out parsed))
                {
                    blockSize = Math.Max(8, Math.Min(1468, parsed));
                }
            }

            bool wantsTsize = options.ContainsKey("tsize");
            long fileLength = new FileInfo(path).Length;
            log("TFTP GET " + client + " " + fileName + " bytes=" + fileLength + " blksize=" + blockSize);

            UdpClient transfer = new UdpClient(0);
            transfer.Client.ReceiveTimeout = 3000;
            try
            {
                if (options.Count > 0)
                {
                    Dictionary<string, string> accepted = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    if (options.ContainsKey("blksize")) accepted["blksize"] = blockSize.ToString();
                    if (wantsTsize) accepted["tsize"] = fileLength.ToString();
                    SendPacket(transfer, BuildOack(accepted), client);
                    if (!WaitAck(transfer, client, 0)) return;
                }

                using (FileStream fs = File.OpenRead(path))
                {
                    byte[] buffer = new byte[blockSize];
                    ushort block = 1;
                    while (true)
                    {
                        int read = fs.Read(buffer, 0, buffer.Length);
                        byte[] data = BuildData(block, buffer, read);
                        bool acked = false;
                        for (int attempt = 0; attempt < 5 && !acked; attempt++)
                        {
                            SendPacket(transfer, data, client);
                            acked = WaitAck(transfer, client, block);
                        }
                        if (!acked)
                        {
                            log("TFTP timeout " + client + " " + fileName + " block=" + block);
                            return;
                        }
                        if (read < blockSize) break;
                        block++;
                    }
                }
                log("TFTP DONE " + client + " " + fileName);
            }
            catch (Exception ex)
            {
                log("TFTP transfer error " + client + " " + fileName + ": " + ex.Message);
            }
            finally
            {
                transfer.Close();
            }
        }

        private bool ParseRrq(byte[] request, out string fileName, out string mode, out Dictionary<string, string> options)
        {
            fileName = "";
            mode = "";
            options = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            int offset = 2;
            fileName = ReadZeroString(request, ref offset);
            mode = ReadZeroString(request, ref offset);
            if (fileName.Length == 0) return false;
            while (offset < request.Length)
            {
                string key = ReadZeroString(request, ref offset);
                if (key.Length == 0) break;
                string value = ReadZeroString(request, ref offset);
                options[key] = value;
            }
            return true;
        }

        private static string ReadZeroString(byte[] data, ref int offset)
        {
            int start = offset;
            while (offset < data.Length && data[offset] != 0) offset++;
            string value = Encoding.ASCII.GetString(data, start, offset - start);
            if (offset < data.Length && data[offset] == 0) offset++;
            return value;
        }

        private string ResolvePath(string fileName)
        {
            string clean = fileName.Replace('/', Path.DirectorySeparatorChar).Replace('\\', Path.DirectorySeparatorChar).TrimStart(Path.DirectorySeparatorChar);
            if (clean.IndexOf("..", StringComparison.Ordinal) >= 0) return null;
            string full = Path.GetFullPath(Path.Combine(root, clean));
            if (!full.StartsWith(root, StringComparison.OrdinalIgnoreCase)) return null;
            return full;
        }

        private void SendError(IPEndPoint client, ushort code, string message)
        {
            using (UdpClient udp = new UdpClient(0))
            {
                List<byte> packet = new List<byte>();
                packet.Add(0);
                packet.Add(5);
                packet.Add((byte)(code >> 8));
                packet.Add((byte)(code & 255));
                packet.AddRange(Encoding.ASCII.GetBytes(message));
                packet.Add(0);
                SendPacket(udp, packet.ToArray(), client);
            }
        }

        private static byte[] BuildOack(Dictionary<string, string> options)
        {
            List<byte> packet = new List<byte>();
            packet.Add(0);
            packet.Add(6);
            foreach (KeyValuePair<string, string> item in options)
            {
                packet.AddRange(Encoding.ASCII.GetBytes(item.Key));
                packet.Add(0);
                packet.AddRange(Encoding.ASCII.GetBytes(item.Value));
                packet.Add(0);
            }
            return packet.ToArray();
        }

        private static byte[] BuildData(ushort block, byte[] buffer, int count)
        {
            byte[] packet = new byte[count + 4];
            packet[0] = 0;
            packet[1] = 3;
            packet[2] = (byte)(block >> 8);
            packet[3] = (byte)(block & 255);
            Array.Copy(buffer, 0, packet, 4, count);
            return packet;
        }

        private static void SendPacket(UdpClient udp, byte[] packet, IPEndPoint remote)
        {
            udp.Send(packet, packet.Length, remote);
        }

        private static bool WaitAck(UdpClient udp, IPEndPoint expected, ushort block)
        {
            try
            {
                while (true)
                {
                    IPEndPoint remote = new IPEndPoint(IPAddress.Any, 0);
                    byte[] packet = udp.Receive(ref remote);
                    if (!remote.Address.Equals(expected.Address) || remote.Port != expected.Port) continue;
                    if (packet.Length >= 4 && packet[0] == 0 && packet[1] == 4)
                    {
                        ushort ack = (ushort)((packet[2] << 8) | packet[3]);
                        if (ack == block) return true;
                    }
                    if (packet.Length >= 4 && packet[0] == 0 && packet[1] == 5) return false;
                }
            }
            catch (SocketException)
            {
                return false;
            }
        }
    }
}
