import SwiftUI

@main
@MainActor
struct MeshInteractionApp: App {
    // MARK: Must Add NSWorldSensingUsageDescription to App Keys
    @State private var appState = AppState()

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(
                appState: appState
            )
        }
        .defaultSize(CGSize(width: 480, height: 640))
        
        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView(
                appState: appState
            )
        }
        .onChange(of: scenePhase, initial: true) {
            if scenePhase != .active {
                if appState.isImmersiveSpaceOpened {
                    Task {
                        await dismissImmersiveSpace()
                        appState.didLeaveImmersiveSpace()
                    }
                }
            }
        }
        .immersionStyle(selection: $appState.currentStyle, in: .mixed, .progressive, .full)
    }
}
