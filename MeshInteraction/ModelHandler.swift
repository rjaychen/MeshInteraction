//
//  ModelHandler.swift
//  MeshInteraction
//
//  Created by I3T Duke on 7/9/24.
//

import SwiftUI
import Vision

class ModelHandler: ObservableObject {
    @Published var mask: UIImage?
    private var segmentation_request: VNCoreMLRequest!
    private var inpainting_request: VNCoreMLRequest!
    
    lazy var inpainting: LaMa? = {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndGPU
            let model = try LaMa(configuration: config)
            return model
        } catch let error {
            print(error)
            fatalError("inpainting initialize error")
        }
    }()
    
    init() {
        setupModel()
    }

    private func setupModel() {
        guard let segmentation = try? VNCoreMLModel(for: u2netp().model) else {fatalError("can't load segmentation model.")}
        self.segmentation_request = VNCoreMLRequest(model: segmentation, completionHandler: { [weak self] request, error in
            guard let results = request.results, let firstResult = results.first as? VNPixelBufferObservation else {
                return
            }
        
            let ciImage = CIImage(cvPixelBuffer: firstResult.pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            DispatchQueue.main.async {
                self?.mask = UIImage(cgImage: cgImage)
            }
        })
    }

    func processImage(_ uiImage: UIImage) async -> UIImage? {
        guard let ciImage = CIImage(image: uiImage) else {
            fatalError()
        }
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                do {
                    try handler.perform([self.segmentation_request])
                    Task{
                        if let resultImage = await self.inpaint_with_lama(inputImage: uiImage, mask: self.mask!) {
                            continuation.resume(returning: resultImage)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                } catch {
                    fatalError()
                }
            }
        }
    }
    
    func inpaint_with_lama(inputImage: UIImage, mask: UIImage) async -> UIImage? {
        guard let model = inpainting else { fatalError("can't load inpainting model.") }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var input: LaMaInput?
                    input = try LaMaInput(imageWith: inputImage.cgImage! , maskWith: mask.cgImage!)
                    
                    let start = Date()
                    
                    let out = try! model.prediction(input: input!)
                    let pixelBuffer = out.output
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                    let context = CIContext()
                    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let resultImage = UIImage(cgImage: cgImage)
                    
                    let timeElapsed = -start.timeIntervalSinceNow
                    print(timeElapsed)
                    
                    continuation.resume(returning: resultImage)
                } catch let error {
                    print(error)
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
}
