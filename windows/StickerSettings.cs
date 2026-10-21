using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace HASticker
{
    public enum StickerMode
    {
        Desktop,   // 嵌进 Explorer 桌面层
        Top,       // 永远置顶
        Normal     // 普通窗口
    }

    public class StickerSettings
    {
        public string HaUrl { get; set; } = "";
        public int Width { get; set; } = 320;
        public int Height { get; set; } = 480;
        public int X { get; set; } = -1;   // -1 表示「没存过」，首次放到右下角
        public int Y { get; set; } = -1;
        public double Opacity { get; set; } = 1.0;
        public double Zoom { get; set; } = 1.0;
        public int CornerRadius { get; set; } = 10;
        public StickerMode Mode { get; set; } = StickerMode.Desktop;
        public bool LockPosition { get; set; } = false;
        public bool ShowDragBar { get; set; } = true;

        [JsonIgnore]
        public bool IsConfigured => !string.IsNullOrWhiteSpace(HaUrl);

        /// 没写 http:// 前缀的自动补上
        public string NormalizedUrl()
        {
            string s = (HaUrl ?? "").Trim();
            if (s.Length == 0) return null;
            if (!s.Contains("://")) s = "http://" + s;
            return s;
        }

        public static string SampleUrl => "http://homeassistant.local:8123/sticker?kiosk";

        private static string ConfigPath =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                         "HASticker", "config.json");

        private static readonly JsonSerializerOptions JsonOptions = new JsonSerializerOptions
        {
            WriteIndented = true,
            Converters = { new JsonStringEnumConverter() }
        };

        public static StickerSettings Load()
        {
            try
            {
                if (File.Exists(ConfigPath))
                {
                    string json = File.ReadAllText(ConfigPath);
                    var s = JsonSerializer.Deserialize<StickerSettings>(json, JsonOptions);
                    if (s != null) return s;
                }
            }
            catch
            {
                // 配置文件坏了就用默认值，不让它挡住启动
            }
            return new StickerSettings();
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(ConfigPath));
                File.WriteAllText(ConfigPath, JsonSerializer.Serialize(this, JsonOptions));
            }
            catch
            {
                // 存不下就算了，不影响这次运行
            }
        }
    }
}
