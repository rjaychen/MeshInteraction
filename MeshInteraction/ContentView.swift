import SwiftUI
import RealityKit

struct ContentView: View {

    @State var appState: AppState

    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        VStack { /// Outside Immersive Space
            if !appState.isImmersiveSpaceOpened {
                let openSpace = {
                    switch await openImmersiveSpace(id: "ImmersiveSpace") {
                    case .opened:
                        break
                    case .error:
                        print("An error occurred when trying to open the immersive space \("ImmersiveSpace")")
                    case .userCancelled:
                        print("The user declined opening immersive space \("ImmersiveSpace")")
                    @unknown default:
                        break
                    }
                }
                let imageTracking = {
                    switch await openImmersiveSpace(id: "ImageTracking") {
                    case .opened:
                        break
                    case .error:
                        print("An error occurred when trying to open the immersive space \("ImmersiveSpace")")
                    case .userCancelled:
                        print("The user declined opening immersive space \("ImmersiveSpace")")
                    @unknown default:
                        break
                    }
                }
                Section("Select A Viewing Style") {
                    Button("Mixed View") {
                        Task {
                            appState.currentStyle = .mixed
                            await openSpace()
                        }
                    }
                    Button("Progressive View") {
                        Task {
                            appState.currentStyle = .progressive
                            await openSpace()
                        }
                    }
                    Button("Full View") {
                        Task {
                            appState.currentStyle = .full
                            await openSpace()
                        }
                    }
                    Button("Image Tracking") {
                        Task {
                            appState.currentStyle = .mixed
                            await imageTracking()
                        }
                    }
                }
                Toggle("Scene Mesh", isOn: $appState.visualizeSceneMeshes).padding()
                Toggle("Matrix Shader", isOn: $appState.useMatrixShader).padding().disabled(appState.useBlurShader)
                Toggle("Blur Shader", isOn: $appState.useBlurShader).padding().disabled(appState.useMatrixShader)
                Toggle("Toggle Tap Mesh", isOn: $appState.enableTapMesh).padding()
            } else { /// Inside Immersive Space
                VStack {
                    Spacer()
                    Button {
                        Task {
                            await dismissImmersiveSpace()
                            appState.didLeaveImmersiveSpace()
                        }
                    } label: {
                        Label("Return Home", systemImage: "xmark.circle")
                            .frame(minWidth: 200)
                    }
                    Spacer()
                    Slider(value: $appState.boundingRadius, in: 0.0...1.5)
                    Text("Bounding Radius: \(appState.boundingRadius, specifier: "%.3f")")
                    Spacer()
                    if let uiImage = UIImage(named: "testCameraFrame") {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                    }
                }
            }
        }
        .padding()
        .onChange(of: scenePhase, initial: true) {
            print("Scene phase: \(scenePhase)")
            if scenePhase == .active {
                // do nothing
            } else {
                if appState.isImmersiveSpaceOpened {
                    Task {
                        await dismissImmersiveSpace()
                        appState.didLeaveImmersiveSpace()
                    }
                }
            }
        }
        .onChange(of: appState.providersStoppedWithError, { _, providersStoppedWithError in
            if providersStoppedWithError {
                if appState.isImmersiveSpaceOpened {
                    Task {
                        await dismissImmersiveSpace()
                        appState.didLeaveImmersiveSpace()
                    }
                }
                appState.providersStoppedWithError = false
            }
        })
        .task {
            await appState.monitorSessionEvents()
        }
    }
}
