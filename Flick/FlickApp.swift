import SwiftUI

@main
struct FlickApp: App {
    @State private var controller = FlickController()

    var body: some Scene {
        MenuBarExtra("Flick", systemImage: "macwindow.on.rectangle") {
            MenuBarView(controller: controller)
        }
        .menuBarExtraStyle(.menu)
    }
}
