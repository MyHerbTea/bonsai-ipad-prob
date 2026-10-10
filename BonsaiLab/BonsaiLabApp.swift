import SwiftUI

@main
struct BonsaiLabApp: App {
    init() {
        Build98FAVecAB.installAtProcessLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ProductionView()
        }
    }
}
