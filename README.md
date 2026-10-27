# 轻聊 · Flutter IM 客户端

基于工作区现有 Electron 客户端及 Java IM 服务开发，浅蓝毛玻璃界面，提供消息、联系人、动态、收藏笔记、钱包红包和 AI 对话。

```powershell
.\tool\flutter.ps1 pub get
.\tool\flutter.ps1 run
```

Android 模拟器默认连接 `10.0.2.2`，桌面端与 Web 默认连接 `127.0.0.1`，HTTP 使用 81 端口、WS 使用 80 端口。真机可在登录页右上角配置电脑局域网地址。已保存的设置优先；连接设置提供“使用当前平台默认地址”按钮。

```powershell
.\tool\flutter.ps1 analyze
.\tool\flutter.ps1 test --no-pub
.\tool\flutter.ps1 build apk --debug --no-pub
```

详细功能、代码结构、接口约定、依赖问题解决方式和验收边界见 [移动端开发与联调说明](docs/移动端开发与联调说明.md)。截图采用合成数据。

图标来源、菜单样式及热门动态分页修复见 [图标弹层与热门动态修复](docs/2026-10-26-图标弹层与热门动态修复.md)。应用图标已复用 Electron 原图，安装图标需要重新打包安装后更新。

App 消息 ID 已对齐 Electron 的 Snowflake 格式，消息列表按大整数 ID 排序。原因、WS 精度验证及旧数据边界见 [消息 ID 统一与排序修复](docs/2026-10-27-消息ID统一与排序修复.md)。

冷启动会联网验证已保存的登录状态，失败或超过 5 秒则返回登录页；使用中断网及进程仍在时切回前台保留登录状态。详见 [启动登录与断网处理](docs/2026-10-27-启动登录与断网处理.md)。
