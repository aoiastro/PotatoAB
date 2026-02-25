import SwiftUI

@main
struct PotatoABApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Force landscape orientation in a real app by using AppDelegate / Info.plist,
                // but for SwiftUI simplest representation, we want the user to rotate their device.
        }
    }
}
