using System;
using System.Drawing;
using System.Windows.Forms;

namespace HASticker
{
    public class SettingsDialog : Form
    {
        private TextBox txtUrl;
        private NumericUpDown numWidth;
        private NumericUpDown numHeight;
        private NumericUpDown numZoom;
        private NumericUpDown numOpacity;
        private NumericUpDown numRadius;
        private ComboBox cmbMode;
        private CheckBox chkLock;
        private CheckBox chkBar;

        public StickerSettings Result { get; private set; }

        private readonly StickerSettings source;

        public SettingsDialog(StickerSettings current)
        {
            source = current;
            Text = "HA 贴纸设置";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Microsoft YaHei UI", 9f);
            Size = new Size(460, 400);
            TopMost = true;

            var layout = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 2,
                Padding = new Padding(16, 14, 16, 6)
            };
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

            // 地址
            layout.Controls.Add(Label("HA 地址"), 0, 0);
            txtUrl = new TextBox { Dock = DockStyle.Fill, Text = current.HaUrl };
            layout.Controls.Add(txtUrl, 1, 0);

            var tip = new Label
            {
                Text = "例：" + StickerSettings.SampleUrl + "（?kiosk 隐藏侧边栏和顶栏）",
                ForeColor = Color.Gray,
                Font = new Font("Microsoft YaHei UI", 8f),
                Dock = DockStyle.Fill,
                AutoSize = true
            };
            layout.Controls.Add(new Label(), 0, 1);
            layout.Controls.Add(tip, 1, 1);

            // 尺寸
            layout.Controls.Add(Label("宽 (px)"), 0, 2);
            numWidth = Num(160, 1600, current.Width, 1);
            layout.Controls.Add(numWidth, 1, 2);

            layout.Controls.Add(Label("高 (px)"), 0, 3);
            numHeight = Num(160, 2000, current.Height, 1);
            layout.Controls.Add(numHeight, 1, 3);

            layout.Controls.Add(Label("缩放 %"), 0, 4);
            numZoom = Num(50, 200, (int)Math.Round(current.Zoom * 100), 10);
            layout.Controls.Add(numZoom, 1, 4);

            layout.Controls.Add(Label("透明度 %"), 0, 5);
            numOpacity = Num(40, 100, (int)Math.Round(current.Opacity * 100), 5);
            layout.Controls.Add(numOpacity, 1, 5);

            layout.Controls.Add(Label("圆角"), 0, 6);
            numRadius = Num(0, 40, current.CornerRadius, 2);
            layout.Controls.Add(numRadius, 1, 6);

            // 贴法
            layout.Controls.Add(Label("贴法"), 0, 7);
            cmbMode = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList };
            cmbMode.Items.Add("桌面层（贴住桌面）");
            cmbMode.Items.Add("置顶（浮在所有窗口上）");
            cmbMode.Items.Add("普通窗口");
            cmbMode.SelectedIndex = (int)current.Mode;
            layout.Controls.Add(cmbMode, 1, 7);

            // 开关
            chkLock = new CheckBox { Text = "锁定位置（不能拖动）", Checked = current.LockPosition, Dock = DockStyle.Fill };
            chkBar = new CheckBox { Text = "显示顶部拖动条", Checked = current.ShowDragBar, Dock = DockStyle.Fill };
            layout.Controls.Add(chkLock, 1, 8);
            layout.Controls.Add(chkBar, 1, 9);

            // 按钮
            var buttons = new FlowLayoutPanel
            {
                Dock = DockStyle.Bottom,
                FlowDirection = FlowDirection.RightToLeft,
                Height = 48,
                Padding = new Padding(0, 0, 14, 0)
            };
            var ok = new Button { Text = "保存", Width = 88, Height = 30 };
            var cancel = new Button { Text = "取消", Width = 88, Height = 30 };
            ok.Click += OnOK;
            cancel.Click += (s, e) => { DialogResult = DialogResult.Cancel; Close(); };
            buttons.Controls.Add(ok);
            buttons.Controls.Add(cancel);

            Controls.Add(layout);
            Controls.Add(buttons);
            AcceptButton = ok;
            CancelButton = cancel;
        }

        private static Label Label(string text)
        {
            return new Label
            {
                Text = text,
                AutoSize = true,
                Anchor = AnchorStyles.Left,
                Padding = new Padding(0, 6, 0, 0)
            };
        }

        private static NumericUpDown Num(int min, int max, int value, int step)
        {
            return new NumericUpDown
            {
                Minimum = min,
                Maximum = max,
                Value = Math.Min(max, Math.Max(min, value)),
                Increment = step,
                Dock = DockStyle.Fill
            };
        }

        private void OnOK(object sender, EventArgs e)
        {
            var s = new StickerSettings
            {
                HaUrl = txtUrl.Text.Trim(),
                Width = (int)numWidth.Value,
                Height = (int)numHeight.Value,
                Zoom = (int)numZoom.Value / 100.0,
                Opacity = (int)numOpacity.Value / 100.0,
                CornerRadius = (int)numRadius.Value,
                Mode = (StickerMode)cmbMode.SelectedIndex,
                LockPosition = chkLock.Checked,
                ShowDragBar = chkBar.Checked,
                X = source.X,
                Y = source.Y
            };
            Result = s;
            DialogResult = DialogResult.OK;
            Close();
        }
    }
}
