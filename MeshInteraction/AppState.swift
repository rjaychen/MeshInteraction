import ARKit
import SwiftUI
import Observation

@Observable
class AppState {

    var currentStyle: ImmersionStyle = .full

    var isImmersiveSpaceOpened: Bool { viewModel != nil }
    private(set) weak var viewModel: ViewModel? = nil

    var boundingRadius: Float = 0.3
    var visualizeSceneMeshes: Bool = false
    var useMatrixShader: Bool = false
    
    func isImmersiveSpaceOpened(with viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    func didLeaveImmersiveSpace() {
        if viewModel != nil {
            arkitSession.stop()
        }
        viewModel = nil
    }

    // MARK: - ARKit state

    var arkitSession = ARKitSession()
    var providersStoppedWithError = false

    func monitorSessionEvents() async {
        for await event in arkitSession.events {
            switch event {
            case .dataProviderStateChanged(_, let newState, let error):
                switch newState {
                case .initialized:
                    break
                case .running:
                    break
                case .paused:
                    break
                case .stopped:
                    if let error {
                        print("An error occurred: \(error)")
                        providersStoppedWithError = true
                    }
                @unknown default:
                    break
                }
            case .authorizationChanged(let type, let status):
                print("Authorization type \(type) changed to \(status)")
            default:
                print("An unknown event occured \(event)")
            }
        }
    }
}
