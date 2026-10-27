import SwiftUI

@main
struct SepiaApp: App {
    @StateObject private var library = Library()
    @StateObject private var player = Player()

    init() {
        // 启动就写一条，保证「文件」App 里一定能看到日志文件
        Log.info("启动 \(AppInfo.summary)，iOS \(UIDevice.current.systemVersion)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
        }
    }
}
