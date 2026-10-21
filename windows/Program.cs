using System;
using System.Threading;
using System.Windows.Forms;

namespace HASticker
{
    internal static class Program
    {
        private const string MutexName = "HASticker_SingleInstance_Mutex";

        [STAThread]
        private static void Main(string[] args)
        {
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            // 只允许一个贴纸在跑，第二个实例直接提示后退出
            using (var mutex = new Mutex(true, MutexName, out bool createdNew))
            {
                if (!createdNew)
                {
                    MessageBox.Show("HA 贴纸已经在运行了。\n看桌面，或者去右下角托盘找图标。",
                                    "HA 贴纸", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                Application.Run(new MainForm(args));
            }
        }
    }
}
