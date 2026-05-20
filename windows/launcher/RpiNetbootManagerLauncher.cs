using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

namespace RpiNetbootWindows
{
    internal static class RpiNetbootManagerLauncher
    {
        [STAThread]
        private static int Main(string[] args)
        {
            string exePath = Assembly.GetExecutingAssembly().Location;
            string exeName = Path.GetFileNameWithoutExtension(exePath) ?? "";
            bool admin = exeName.IndexOf("Admin", StringComparison.OrdinalIgnoreCase) >= 0;
            string task = "menu";

            foreach (string arg in args)
            {
                if (arg.Equals("--admin", StringComparison.OrdinalIgnoreCase))
                {
                    admin = true;
                    continue;
                }
                if (arg.StartsWith("--task=", StringComparison.OrdinalIgnoreCase))
                {
                    task = arg.Substring("--task=".Length);
                }
            }

            string projectRoot = Path.GetDirectoryName(exePath);
            if (String.IsNullOrWhiteSpace(projectRoot))
            {
                projectRoot = Environment.CurrentDirectory;
            }

            string scriptPath = Path.Combine(projectRoot, "tools", "rpi-netboot-manager.ps1");
            if (!File.Exists(scriptPath))
            {
                MessageBox.Show(
                    "Cannot find automation script:\n" + scriptPath,
                    "RPI Netboot Manager",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 2;
            }

            string arguments =
                "-NoProfile -ExecutionPolicy Bypass -NoExit -File " +
                Quote(scriptPath) +
                " -Task " +
                Quote(task);

            ProcessStartInfo startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = arguments,
                WorkingDirectory = projectRoot,
                UseShellExecute = true
            };

            if (admin)
            {
                startInfo.Verb = "runas";
            }

            try
            {
                Process.Start(startInfo);
                return 0;
            }
            catch (System.ComponentModel.Win32Exception ex)
            {
                MessageBox.Show(
                    "Launch cancelled or failed:\n" + ex.Message,
                    "RPI Netboot Manager",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
                return 1;
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "Launch failed:\n" + ex.Message,
                    "RPI Netboot Manager",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }
        }

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }
    }
}
