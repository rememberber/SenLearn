import SwiftUI

@main
struct SenLearnApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var appearance = AppearanceSettings()
    @StateObject private var speech: SpeechPlayer

    init() {
        var directory: URL?
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SenLearnUITests", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("--reset-library"), let directory {
                try? FileManager.default.removeItem(at: directory)
                for key in ["lastOpenedBookID", "appearance.theme", "appearance.reduceMotion", "appearance.parentPanel", "speech.engine", "speech.rate"] {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        #endif
        _speech = StateObject(wrappedValue: SpeechPlayer())
        _library = StateObject(wrappedValue: LibraryStore(rootDirectory: directory))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(library: library, appearance: appearance, speech: speech)
                .preferredColorScheme(appearance.theme == .night ? .dark : .light)
        }
    }
}
