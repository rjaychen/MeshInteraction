import ARKit
import SwiftUI
import RealityKit

@MainActor
struct ImmersiveView: View {

    let appState: AppState
    @State private var viewModel = ViewModel()
    @ObservedObject var modelHandler = ModelHandler()
    
    var body: some View {
        RealityView { content in
            content.add(viewModel.setupContentEntity())
            viewModel.appState = appState
            Task {
                await viewModel.loadMaterial()
                await viewModel.runARKitSession()
            }
        }
        .task {
            await viewModel.processHandUpdates()
        }
        .task() {
            await viewModel.processReconstructionUpdates()
        }
//        .task() {
//            await viewModel.processImageTrackingUpdates()
//        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            let location3D = value.convert(value.location3D, from: .local, to: .scene)
            print(location3D)
            if appState.enableTapMesh {
                let image = UIImage(named: "dog")
                Task{
                    if let inpainted = await modelHandler.processImage(image!) {
                        await viewModel.setMaterialTexture(uiImage: inpainted)
                        viewModel.createBoundingEntity(location: location3D)
                    }
                }
            } else {
                viewModel.addCube(tapLocation: location3D)
            }
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
