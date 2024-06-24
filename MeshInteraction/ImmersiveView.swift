import ARKit
import SwiftUI
import RealityKit

@MainActor
struct ImmersiveView: View {

    let appState: AppState
    @State private var viewModel = ViewModel()

    var body: some View {
        RealityView { content in
            content.add(viewModel.setupContentEntity())
            viewModel.appState = appState

            Task {
                await viewModel.runARKitSession()
            }
        }
        .task {
            await viewModel.processHandUpdates()
        }
        .task() {
            await viewModel.processReconstructionUpdates()
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            let location3D = value.convert(value.location3D, from: .local, to: .scene)
            print(location3D)
            // change the color of the entity mesh at the scene
            //var myMat = SimpleMaterial(color: .magenta.withAlphaComponent(0.8), isMetallic: false)
            //myMat.triangleFillMode = .lines
            //value.entity.components[ModelComponent.self]?.materials = [myMat]
            viewModel.createBoundingEntity(location: location3D)
            // viewModel.addCube(tapLocation: location3D)
        })
        .onAppear() {
            print("Entering immersive space.")
            appState.isImmersiveSpaceOpened(with: viewModel)
        }
        .onDisappear() {
            print("Leaving immersive space.")
            appState.didLeaveImmersiveSpace()
        }
    }
}
