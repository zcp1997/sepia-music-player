import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Library.keepAllLocalKey) private var keepAllLocal = false

    var body: some View {
        NavigationStack {
            Form {
                Section("音乐文件夹") {
                    LabeledContent("当前", value: library.rootURL?.lastPathComponent ?? "未选择")
                    LabeledContent("歌曲", value: "\(library.songs.count) 首")
                    Button("更换文件夹") {
                        FolderPicker.shared.present { library.setFolder($0) }
                    }
                    Button(library.isScanning ? "正在扫描…" : "重新扫描") { library.rescan() }
                        .disabled(library.isScanning)
                }

                Section {
                    Toggle("保持全部歌曲在本机", isOn: $keepAllLocal)
                        .onChange(of: keepAllLocal) { isOn in
                            if isOn { library.downloadMissingIfNeeded() }
                        }
                } footer: {
                    Text("打开后，每次扫描完都会请系统在后台下载还不在本机的歌和歌词；被系统移除的歌，下次打开 App 也会补回来。会占用和曲库一样大的空间。")
                }

                Section {
                    LabeledContent("版本", value: AppInfo.summary)
                } footer: {
                    Text("运行日志：「文件」App → 我的 iPhone → Sepia → sepia.log")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
