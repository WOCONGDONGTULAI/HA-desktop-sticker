using System;
using System.Runtime.InteropServices;

namespace HASticker
{
    /// 把窗口真正挂到 Windows 桌面层（Explorer 的 WorkerW）上。
    /// 效果：Win+D 时跟着出现、开其他程序时被正常遮挡、不进 Alt+Tab。
    internal static class DesktopEmbed
    {
        private const uint SMTO_NORMAL = 0x0000;
        private const uint WM_SPAWN_WORKERW = 0x052C;   // Explorer 的私有消息

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr FindWindowEx(IntPtr hWndParent, IntPtr hWndChildAfter,
                                                  string lpszClass, string lpszWindow);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam,
                                                        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);

        [DllImport("user32.dll")]
        private static extern IntPtr GetParent(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        /// 找到桌面图标下面那层 WorkerW；找不到返回 Zero
        public static IntPtr FindWorkerW()
        {
            IntPtr progman = FindWindow("Progman", null);
            if (progman == IntPtr.Zero) return IntPtr.Zero;

            // 这发消息让 Explorer 生成一个 WorkerW（桌面图标容器的兄弟窗口）
            SendMessageTimeout(progman, WM_SPAWN_WORKERW, IntPtr.Zero, IntPtr.Zero,
                               SMTO_NORMAL, 1000, out _);

            IntPtr workerW = IntPtr.Zero;
            EnumWindows((hWnd, lParam) =>
            {
                IntPtr shellView = FindWindowEx(hWnd, IntPtr.Zero, "SHELLDLL_DefView", null);
                if (shellView != IntPtr.Zero)
                {
                    // 紧跟其后的那个顶层 WorkerW 就是我们要挂的
                    IntPtr found = FindWindowEx(IntPtr.Zero, hWnd, "WorkerW", null);
                    if (found != IntPtr.Zero) workerW = found;
                    return false;   // 找到了，停止枚举
                }
                return true;
            }, IntPtr.Zero);

            return workerW;
        }

        public static bool Attach(IntPtr childHandle)
        {
            IntPtr workerW = FindWorkerW();
            if (workerW == IntPtr.Zero) return false;
            return SetParent(childHandle, workerW) != IntPtr.Zero;
        }

        public static bool Detach(IntPtr childHandle)
        {
            return SetParent(childHandle, IntPtr.Zero) != IntPtr.Zero;
        }

        /// Explorer 重启后附着会失效，用来检测并重新贴回
        public static bool IsAttached(IntPtr childHandle)
        {
            IntPtr workerW = FindWorkerW();
            if (workerW == IntPtr.Zero) return false;
            return GetParent(childHandle) == workerW;
        }
    }
}
