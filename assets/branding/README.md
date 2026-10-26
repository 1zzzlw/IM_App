# 应用图标来源

原始图标来自工作区 Electron 工程 `E:/ElectronProject/WeChat-Electron-vue-vite/build/favicon.ico`，是该工程 electron-builder 指定的安装包/程序图标。

- `app_icon.png`：从原始 ICO 提取的最大 256×256 图层，作为 Flutter 界面及平台图标的统一来源。
- `windows/runner/resources/app_icon.ico`：直接复制原始 ICO，保留原有全部分辨率。
- Android、iOS、macOS、Web：由 `tool/generate_app_icons.py` 调整为对应平台尺寸。Android 另提供自适应前景安全区；iOS 使用不透明底色。

原始素材最大为 256×256，更大平台图标通过重采样生成；没有重新设计标志。替换原图后可以用 `python tool/generate_app_icons.py` 重新生成（需要 Pillow），Windows ICO 按原文件单独替换。
