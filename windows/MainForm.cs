using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace HASticker
{
    public class MainForm : Form
    {
        private const int WM_HOTKEY = 0x0312;
        private const int HOTKEY_ID = 9001;
        private const uint MOD_ALT = 0x0001;
        private const uint MOD_CONTROL = 0x0002;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        private WebView2 webView;
        private Panel dragBar;
        private NotifyIcon trayIcon;
        private ContextMenuStrip menu;
        private Timer watchdog;

        private StickerSettings settings;
        private readonly string[] args;
        private bool dragging;
        private Point dragOffset;

        public MainForm(string[] args)
        {
            this.args = args ?? Array.Empty<string>();
            settings = StickerSettings.Load();

            // --reset 恢复默认配置
            if (Array.IndexOf(this.args, "--reset") >= 0)
            {
                settings = new StickerSettings();
                settings.Save();
            }

            Text = "HA 贴纸";
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            ShowInTaskbar = false;
            BackColor = Color.FromArgb(28, 28, 30);
            Font = new Font("Microsoft YaHei UI", 9f);
            Size = new Size(Math.Max(settings.Width, 160), Math.Max(settings.Height, 160));
            Opacity = settings.Opacity;

            menu = BuildMenu();

            BuildWebView();
            BuildDragBar();
            BuildTray();

            dragBar.ContextMenuStrip = menu;
            trayIcon.ContextMenuStrip = menu;

            PositionWindow();
        }

        // ---------- 界面 ----------

        private void BuildWebView()
        {
            webView = new WebView2
            {
                Dock = DockStyle.Fill,
                DefaultBackgroundColor = Color.Transparent
            };
            Controls.Add(webView);
        }

        private void BuildDragBar()
        {
            dragBar = new Panel
            {
                Dock = DockStyle.Top,
                Height = 26,
                BackColor = Color.FromArgb(190, 32, 32, 34),
                Cursor = Cursors.SizeAll,
                Visible = settings.ShowDragBar
            };

            var title = new Label
            {
                Text = "HA",
                Dock = DockStyle.Left,
                Width = 30,
                ForeColor = Color.Gainsboro,
                TextAlign = ContentAlignment.MiddleCenter
            };

            var btnHide = MakeBarButton("—", "隐藏到托盘");
            var btnClose = MakeBarButton("×", "退出贴纸");
            btnHide.Click += (s, e) => Hide();
            btnClose.Click += (s, e) => Close();

            // 后加的在上面：按钮 → 标题 →（剩下的空白留给拖动）
            dragBar.Controls.Add(title);
            dragBar.Controls.Add(btnClose);
            dragBar.Controls.Add(btnHide);

            BindDrag(dragBar);
            BindDrag(title);
            Controls.Add(dragBar);
            dragBar.BringToFront();
        }

        private Button MakeBarButton(string text, string tip)
        {
            var btn = new Button
            {
                Text = text,
                Dock = DockStyle.Right,
                Width = 28,
                FlatStyle = FlatStyle.Flat,
                ForeColor = Color.Gainsboro,
                BackColor = Color.FromArgb(190, 32, 32, 34)
            };
            btn.FlatAppearance.BorderSize = 0;
            btn.FlatAppearance.MouseOverBackColor = Color.FromArgb(90, 90, 95);
            btn.FlatAppearance.MouseDownBackColor = Color.FromArgb(120, 120, 125);
            toolTip0.SetToolTip(btn, tip);
            return btn;
        }

        private readonly ToolTip toolTip0 = new ToolTip();

        private void BindDrag(Control c)
        {
            c.MouseDown += OnDragMouseDown;
            c.MouseMove += OnDragMouseMove;
            c.MouseUp += OnDragMouseUp;
        }

        private void OnDragMouseDown(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            if (settings.LockPosition) return;
            dragging = true;
            dragOffset = new Point(Cursor.Position.X - Location.X, Cursor.Position.Y - Location.Y);
        }

        private void OnDragMouseMove(object sender, MouseEventArgs e)
        {
            if (!dragging) return;
            Location = new Point(Cursor.Position.X - dragOffset.X, Cursor.Position.Y - dragOffset.Y);
        }

        private void OnDragMouseUp(object sender, MouseEventArgs e)
        {
            if (!dragging) return;
            dragging = false;
            SavePosition();
        }

        private void BuildTray()
        {
            trayIcon = new NotifyIcon
            {
                Icon = SystemIcons.Application,
                Visible = true,
                Text = "HA 贴纸"
            };
            trayIcon.DoubleClick += (s, e) => ToggleVisible();
        }

        private ContextMenuStrip BuildMenu()
        {
            var m = new ContextMenuStrip();

            m.Items.Add("显示 / 隐藏", null, (s, e) => ToggleVisible());
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add("设置…", null, (s, e) => OpenSettings());
            m.Items.Add("重新加载", null, (s, e) => Reload());
            m.Items.Add("在浏览器里打开 HA", null, (s, e) => OpenInBrowser());
            m.Items.Add(new ToolStripSeparator());

            var modeMenu = new ToolStripMenuItem("贴法");
            foreach (StickerMode mode in Enum.GetValues(typeof(StickerMode)))
            {
                var item = new ToolStripMenuItem(ModeName(mode)) { Tag = mode };
                item.Click += (s, e) => { SetMode((StickerMode)((ToolStripMenuItem)s).Tag); };
                modeMenu.DropDownItems.Add(item);
            }
            m.Items.Add(modeMenu);

            var opacityMenu = new ToolStripMenuItem("透明度");
            foreach (double v in new[] { 0.5, 0.7, 0.85, 1.0 })
            {
                var item = new ToolStripMenuItem((int)(v * 100) + "%") { Tag = v };
                item.Click += (s, e) => { SetOpacity((double)((ToolStripMenuItem)s).Tag); };
                opacityMenu.DropDownItems.Add(item);
            }
            m.Items.Add(opacityMenu);

            var lockItem = new ToolStripMenuItem("锁定位置") { CheckOnClick = true };
            lockItem.Click += (s, e) =>
            {
                settings.LockPosition = lockItem.Checked;
                settings.Save();
            };
            m.Items.Add(lockItem);

            m.Items.Add("重新贴回桌面", null, (s, e) => ReattachDesktop());
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add("清除 HA 登录状态", null, (s, e) => ClearLogin());
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add("退出", null, (s, e) => Close());

            m.Opening += (s, e) => UpdateMenuStates(m, lockItem, modeMenu, opacityMenu);
            return m;
        }

        private void UpdateMenuStates(ContextMenuStrip m, ToolStripMenuItem lockItem,
                                      ToolStripMenuItem modeMenu, ToolStripMenuItem opacityMenu)
        {
            lockItem.Checked = settings.LockPosition;
            foreach (ToolStripItem item in modeMenu.DropDownItems)
            {
                if (item is ToolStripMenuItem mi && mi.Tag is StickerMode mode)
                    mi.Checked = (mode == settings.Mode);
            }
            foreach (ToolStripItem item in opacityMenu.DropDownItems)
            {
                if (item is ToolStripMenuItem mi && mi.Tag is double v)
                    mi.Checked = Math.Abs(v - settings.Opacity) < 0.001;
            }
        }

        private static string ModeName(StickerMode mode)
        {
            switch (mode)
            {
                case StickerMode.Desktop: return "桌面层（贴住桌面）";
                case StickerMode.Top: return "置顶（浮在所有窗口上）";
                default: return "普通窗口";
            }
        }

        // ---------- 启动 ----------

        protected override async void OnShown(EventArgs e)
        {
            base.OnShown(e);

            ApplyRegion();
            RegisterHotKey(Handle, HOTKEY_ID, MOD_CONTROL | MOD_ALT, (uint)Keys.H);

            await InitWebViewAsync();

            if (!settings.IsConfigured || Array.IndexOf(args, "--settings") >= 0)
                OpenSettings();

            StartWatchdog();
        }

        private async Task InitWebViewAsync()
        {
            try
            {
                string userData = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "HASticker", "WebView2Data");

                var env = await CoreWebView2Environment.CreateAsync(userDataFolder: userData);
                await webView.EnsureCoreWebView2Async(env);

                // 桌面层模式下窗口是 Explorer 的子窗口，不能设 TopMost，所以顺序有讲究
                ApplyMode();
                webView.ZoomFactor = settings.Zoom;
                Navigate();
            }
            catch (Exception ex)
            {
                MessageBox.Show("WebView2 初始化失败，需要装 Microsoft Edge WebView2 Runtime。\n\n" + ex.Message,
                                "HA 贴纸", MessageBoxButtons.OK, MessageBoxIcon.Error);
                try { Process.Start(new ProcessStartInfo("https://developer.microsoft.com/microsoft-edge/webview2/") { UseShellExecute = true }); }
                catch { /* 打不开就算了 */ }
            }
        }

        // ---------- 网页 ----------

        private void Navigate()
        {
            if (webView == null || webView.CoreWebView2 == null) return;

            string url = settings.NormalizedUrl();
            if (url == null)
            {
                ShowHintPage();
                return;
            }
            webView.CoreWebView2.Navigate(url);
        }

        private void Reload()
        {
            if (webView == null) return;
            if (webView.CoreWebView2 == null || string.IsNullOrEmpty(settings.NormalizedUrl()))
            {
                Navigate();
                return;
            }
            webView.CoreWebView2.Reload();
        }

        private void ShowHintPage()
        {
            if (webView?.CoreWebView2 == null) return;
            string html =
                "<html><body style='margin:0;height:100vh;display:flex;align-items:center;" +
                "justify-content:center;background:#1c1c1e;color:#d0d0d0;" +
                "font-family:\"Microsoft YaHei UI\",sans-serif;text-align:center'>" +
                "<div><div style='font-size:15px;margin-bottom:8px'>还没设置 Home Assistant 地址</div>" +
                "<div style='font-size:12px;color:#888'>" +
                "右键这条标题栏，或点右下角托盘图标 → 设置</div></div></body></html>";
            webView.CoreWebView2.NavigateToString(html);
        }

        // ---------- 模式 ----------

        private void ApplyMode()
        {
            switch (settings.Mode)
            {
                case StickerMode.Desktop:
                    TopMost = false;
                    if (!DesktopEmbed.Attach(Handle))
                    {
                        // 挂不上（Explorer 还没起来等）先退化成置顶，看门狗会再试
                        settings.Mode = StickerMode.Top;
                        settings.Save();
                        TopMost = true;
                    }
                    break;

                case StickerMode.Top:
                    DesktopEmbed.Detach(Handle);
                    TopMost = true;
                    break;

                default:
                    DesktopEmbed.Detach(Handle);
                    TopMost = false;
                    break;
            }
        }

        private void ReattachDesktop()
        {
            settings.Mode = StickerMode.Desktop;
            settings.Save();
            TopMost = false;
            if (!DesktopEmbed.Attach(Handle))
            {
                MessageBox.Show("没找到 Explorer 桌面窗口（资源管理器是不是没启动？）。\n先按置顶模式用着。",
                                "HA 贴纸", MessageBoxButtons.OK, MessageBoxIcon.Information);
                settings.Mode = StickerMode.Top;
                TopMost = true;
                settings.Save();
            }
        }

        private void StartWatchdog()
        {
            watchdog = new Timer { Interval = 10000 };
            watchdog.Tick += (s, e) =>
            {
                if (settings.Mode == StickerMode.Desktop && !DesktopEmbed.IsAttached(Handle))
                    DesktopEmbed.Attach(Handle);
            };
            watchdog.Start();
        }

        // ---------- 外观 ----------

        private void ApplyRegion()
        {
            if (settings.CornerRadius <= 0)
            {
                Region = null;
                return;
            }
            using (var path = RoundedRectPath(new Rectangle(0, 0, Width, Height), settings.CornerRadius))
            {
                Region = new Region(path);
            }
        }

        private static GraphicsPath RoundedRectPath(Rectangle rect, int radius)
        {
            int d = radius * 2;
            var path = new GraphicsPath();
            path.AddArc(rect.X, rect.Y, d, d, 180, 90);
            path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
            path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            ApplyRegion();
        }

        // ---------- 位置 ----------

        private void PositionWindow()
        {
            if (settings.X >= 0 && settings.Y >= 0)
            {
                var p = new Point(settings.X, settings.Y);
                foreach (var screen in Screen.AllScreens)
                {
                    if (screen.WorkingArea.Contains(p))
                    {
                        Location = p;
                        return;
                    }
                }
            }

            var area = Screen.PrimaryScreen.WorkingArea;
            Location = new Point(area.Right - Width - 20, area.Bottom - Height - 20);
        }

        private void SavePosition()
        {
            settings.X = Location.X;
            settings.Y = Location.Y;
            settings.Width = Width;
            settings.Height = Height;
            settings.Save();
        }

        // ---------- 交互 ----------

        private void ToggleVisible()
        {
            if (Visible)
            {
                Hide();
            }
            else
            {
                Show();
                BringToFront();
            }
        }

        private void OpenSettings()
        {
            using (var dlg = new SettingsDialog(settings))
            {
                if (dlg.ShowDialog(this) == DialogResult.OK)
                {
                    settings = dlg.Result;
                    settings.Save();
                    ApplySettings();
                }
            }
        }

        private void ApplySettings()
        {
            Size = new Size(Math.Max(settings.Width, 160), Math.Max(settings.Height, 160));
            Opacity = settings.Opacity;
            dragBar.Visible = settings.ShowDragBar;
            if (webView?.CoreWebView2 != null) webView.ZoomFactor = settings.Zoom;
            ApplyRegion();
            ApplyMode();
            PositionWindow();
            Navigate();
        }

        private void SetMode(StickerMode mode)
        {
            settings.Mode = mode;
            settings.Save();
            ApplyMode();
        }

        private void SetOpacity(double value)
        {
            settings.Opacity = value;
            settings.Save();
            Opacity = value;
        }

        private void OpenInBrowser()
        {
            string url = settings.NormalizedUrl();
            if (url == null) { OpenSettings(); return; }
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
            catch { /* 忽略 */ }
        }

        private void ClearLogin()
        {
            string dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "HASticker", "WebView2Data");

            var r = MessageBox.Show(
                "清除登录状态后要重启贴纸才会生效。\n现在退出贴纸吗？（退出后请手动再启动）",
                "HA 贴纸", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (r != DialogResult.Yes) return;

            Close();
            try
            {
                if (Directory.Exists(dir)) Directory.Delete(dir, true);
            }
            catch
            {
                MessageBox.Show("没能自动删除，手动删这个目录即可：\n" + dir,
                                "HA 贴纸", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        // ---------- 收尾 ----------

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HOTKEY_ID)
            {
                ToggleVisible();
                return;
            }
            base.WndProc(ref m);
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            UnregisterHotKey(Handle, HOTKEY_ID);
            watchdog?.Stop();
            SavePosition();
            if (trayIcon != null)
            {
                trayIcon.Visible = false;
                trayIcon.Dispose();
                trayIcon = null;
            }
            base.OnFormClosing(e);
        }
    }
}
