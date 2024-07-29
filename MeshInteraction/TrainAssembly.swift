//
//  TrainAssembly.swift
//  MeshInteraction
//
//  Created by I3T Duke on 7/29/24.
//

import ARKit
import SwiftUI
import RealityKit

struct TrainAssembly: View {

    let appState: AppState
    @State private var viewModel = ViewModel()
    
    var body: some View {
        RealityView { content in
            content.add(viewModel.setupContentEntity())
            viewModel.appState = appState
            Task {
                await viewModel.loadMaterial()
                await viewModel.runARKitSession()
            }
        }
        .task() {
            await viewModel.processImageTrackingUpdates()
        }
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
