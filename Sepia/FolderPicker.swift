import UIKit
import UniformTypeIdentifiers

/// 选择音乐文件夹（UIDocumentPickerViewController）。
/// 若点「打开」后既不关闭也不回调，多半是 App 签名里缺 application-identifier，见 ci/Sepia.entitlements。
@MainActor
final class FolderPicker: NSObject, UIDocumentPickerDelegate {
    static let shared = FolderPicker()

    private var completion: ((URL) -> Void)?

    func present(completion: @escaping (URL) -> Void) {
        guard let presenter = Self.topViewController() else {
            Log.error("找不到可以弹出文件夹选择器的界面")
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        self.completion = completion
        Log.info("打开文件夹选择器")
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let completion = completion
        self.completion = nil
        guard let url = urls.first else {
            Log.error("文件夹选择器没有返回任何文件夹")
            return
        }
        Log.info("选择器返回：\(url.path)")
        completion?(url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion = nil
        Log.info("取消选择文件夹")
    }

    /// 当前最上层的界面（可能是设置页这样的 sheet）
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
