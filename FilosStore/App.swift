import SwiftUI

@main
struct FilosStoreApp: App {
    @StateObject private var locations = LocationStore()
    @StateObject private var favorites = FavoriteStore()
    @StateObject private var log = AppLog()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locations)
                .environmentObject(favorites)
                .environmentObject(log)
        }
    }
}
