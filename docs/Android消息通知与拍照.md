# Android 消息通知与拍照

日期：2026-10-28。按最终要求仅接入 Android，不继续适配 iOS，不生成安装包。

## 使用入口

- “我的 → 消息与后台接收”：设置新消息提醒、消息提示音和后台连接保活，查看系统通知权限，打开系统省电设置。
- 聊天工具栏“拍照”：调用系统相机，压缩至最长边 2560、质量 85，预览确认后复用现有分片上传与图片消息流程。

## 行为

- 前台显示可点击的顶部消息卡片，并播放项目已有提示音；后台交给 Android 系统通知，可点击打开对应会话。
- 顶部卡片通过导航器的 `OverlayEntry` 展示。已修复原先把卡片放在 `MaterialApp.builder` 中、与导航器并列，导致按钮 `RawTooltip` 找不到 `Overlay` 的问题。
- 过滤重复消息、自己的消息、免打扰会话、正在前台查看的会话；同一波提醒的前台声音有间隔限制。
- App 退到后台后，当前聊天页的新消息仍累计未读，不再误标为已读。
- Android 使用带常驻通知的前台服务，Application 持有 Flutter 引擎，复用原有聊天连接，不创建第二条 WebSocket。退出登录或关闭保活时停止服务并释放唤醒锁。
- 取消拍照不发送消息，拒绝权限有提示，快速点击只打开一次相机；保存拍摄所属账号、服务器、会话，处理 Android 相机期间发生回收后的照片恢复。

## 范围与验证

- 本轮为 iOS 增加的 APNs 后端接口、设备注册、发送逻辑、配置、测试及 iOS 原生改动已撤回。之前的弱网在线状态修复保留。
- `flutter analyze --no-pub` 通过。
- 顶部消息卡片的复现回归覆盖 320 像素窄屏、长按关闭按钮显示提示、关闭卡片和点击进入聊天；修改前能复现 `No Overlay widget found`，修改后通过。
- 消息提醒、拍照恢复、原生通知调用、后台服务启停、现有状态同步、文件及红包等相关测试共 18 项通过。通知和服务启停的 Dart 测试使用原生通道桩，相机测试使用模拟系统相机。
- 未完成 APK 打包或真机声音、通知权限、锁屏及厂商省电策略下的验收。用户选择自行打包；本机此前 Gradle 与 ADB 的启动检查遇到 Windows Socket 10106，未修改系统网络配置。

前台服务提高后台连接持续运行的机会，仍受系统强制停止和省电策略影响。相关平台边界见 [Android 前台服务类型](https://developer.android.com/develop/background-work/services/fgs/service-types) 和 [Doze 限制](https://developer.android.com/training/monitoring-device-state/doze-standby)。相机恢复遵循 [image_picker 官方说明](https://pub.dev/packages/image_picker)。
