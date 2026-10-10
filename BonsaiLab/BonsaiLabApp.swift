import SwiftUI

@main
struct BonsaiLabApp: App {
    init() {
        _ = Build99AppendOnlyReuse.activeArm
    }

    var body: some Scene {
        WindowGroup {
            ProductionView()
        }
    }
}
