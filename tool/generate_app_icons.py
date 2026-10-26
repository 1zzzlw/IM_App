"""将已复制的 Electron 图标适配平台尺寸；不改变标志设计，不依赖 Flutter 插件。

运行：python tool/generate_app_icons.py（需要 Pillow）
"""

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/app_icon.png"
BACKGROUND = (242, 244, 252, 255)
logo = Image.open(SOURCE).convert("RGBA")


def icon(size, fraction=0.82, opaque=True):
    canvas = Image.new("RGBA", (size, size), BACKGROUND if opaque else (0, 0, 0, 0))
    side = round(size * fraction)
    image = logo.resize((side, side), Image.Resampling.LANCZOS)
    canvas.alpha_composite(image, ((size - side) // 2, (size - side) // 2))
    return canvas.convert("RGB") if opaque else canvas


for density, scale in [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)]:
    folder = ROOT / f"android/app/src/main/res/mipmap-{density}"
    folder.mkdir(parents=True, exist_ok=True)
    icon(round(48 * scale)).save(folder / "ic_launcher.png")
    # Adaptive icon 的前景画布 108dp，将标志放在中央安全区域以兼容圆形/方形遮罩。
    icon(round(108 * scale), fraction=0.61, opaque=False).save(folder / "ic_launcher_foreground.png")

for location in ["ios/Runner/Assets.xcassets/AppIcon.appiconset", "macos/Runner/Assets.xcassets/AppIcon.appiconset"]:
    folder = ROOT / location
    manifest = json.loads((folder / "Contents.json").read_text(encoding="utf-8"))
    for item in manifest["images"]:
        if "filename" not in item:
            continue
        size = round(float(item["size"].split("x")[0]) * float(item["scale"].rstrip("x")))
        icon(size).save(folder / item["filename"])

for size in [192, 512]:
    icon(size).save(ROOT / f"web/icons/Icon-{size}.png")
    icon(size, fraction=0.61).save(ROOT / f"web/icons/Icon-maskable-{size}.png")
icon(32).save(ROOT / "web/favicon.png")
print("Android、iOS、macOS 和 Web 图标已生成；Windows 使用 Electron 原始 ICO。")
