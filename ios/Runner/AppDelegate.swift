import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var mediaPreviewChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MediaPreviewBridge") else { return }
    let channel = FlutterMethodChannel(name: "im_app/media_preview", binaryMessenger: registrar.messenger())
    mediaPreviewChannel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "videoThumbnail" else { result(FlutterMethodNotImplemented); return }
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        result(FlutterError(code: "preview", message: "视频路径为空", details: nil)); return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
          generator.appliesPreferredTrackTransform = true
          generator.maximumSize = CGSize(width: 320, height: 320)
          let frame = try generator.copyCGImage(at: .zero, actualTime: nil)
          guard let bytes = UIImage(cgImage: frame).jpegData(compressionQuality: 0.75) else {
            throw NSError(domain: "preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "视频封面编码失败"])
          }
          DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: bytes)) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "preview", message: error.localizedDescription, details: nil)) }
        }
      }
    }
  }
}
