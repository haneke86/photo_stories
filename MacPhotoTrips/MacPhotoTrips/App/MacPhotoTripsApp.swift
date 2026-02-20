import SwiftUI
import SwiftData

@main
struct MacPhotoTripsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: CachedGeocode.self)
    }
}
