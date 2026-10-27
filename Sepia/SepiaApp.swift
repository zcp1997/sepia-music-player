import SwiftUI

@main
struct SepiaApp: App {
    @StateObject private var library = Library()
    @StateObject private var player = Player()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
        }
    }
}
