import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Sepia")
                .font(.largeTitle.bold())
            Text(AppInfo.summary)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}
