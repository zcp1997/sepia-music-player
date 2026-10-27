import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: Library
    @ObservedObject private var cache = HeadCache.shared
    @Environment(\.dismiss) private var dismiss

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
                    LabeledContent("已缓存", value: "\(cache.entryCount) 首 · \(formattedCacheSize)")
                    if let done = cache.preheatDone {
                        HStack {
                            ProgressView(value: Double(done), total: Double(max(cache.preheatTotal, 1)))
                            Text("\(done)/\(cache.preheatTotal)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        Button("停止预热", role: .destructive) { cache.cancelPreheat() }
                    } else {
                        Button("预热全部歌曲") { cache.preheat(library.songs) }
                            .disabled(library.songs.isEmpty)
                    }
                    Button("清空缓存", role: .destructive) { cache.clear() }
                        .disabled(cache.entryCount == 0)
                } header: {
                    Text("起播缓存")
                } footer: {
                    Text("每首歌在本机保留开头约 1MB，不在本机的歌也能立即起播。预热会逐首从 iCloud 下载、截取开头后释放完整文件，进行中请保持 App 在前台。")
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

    private var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(cache.totalBytes), countStyle: .file)
    }
}
