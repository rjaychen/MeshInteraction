import Metal
import CoreML

public struct Point: Equatable {
    public var x: Float
    public var y: Float
    public var label: Int
      
    public init(x: Float, y: Float, label: Int) {
        self.x = x
        self.y = y
        self.label = label
    }
}

public class SegmentAnything {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue!
    private let imageProcessor: ImageProcessor
    
    private var width: Int!
    private var height: Int!
    
    private var encoder: edge_sam_3x_encoder! // input: 1 × 3 × 1024 × 1024 | output: 1 × 256 × 64 × 64
    public var imageEmbeddings: MLMultiArray!
    
    private var decoder: edge_sam_3x_decoder! // input: 1 × 256 × 64 × 64 | output: 1 × 4 × 256 × 256
    
    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.imageProcessor = ImageProcessor(device: device,
                                             mean: SIMD3<Float>(123.675 / 255.0, 116.28 / 255.0, 103.53 / 255.0),
                                             std: SIMD3<Float>(58.395 / 255.0, 57.12 / 255.0, 57.375 / 255.0))
    }
    
    public func load() {
        self.imageProcessor.load()
        
        let modelConfiguration = MLModelConfiguration()
        modelConfiguration.computeUnits = .all
        
        self.encoder = try! edge_sam_3x_encoder(configuration: modelConfiguration)
        self.decoder = try! edge_sam_3x_decoder(configuration: modelConfiguration)
    }
    
    public func preprocess(image: MTLTexture) {
        self.width = image.width
        self.height = image.height
        let resizedImage = self.imageProcessor.preprocess(image: image, commandQueue: self.commandQueue)
        let encoderInput = edge_sam_3x_encoderInput(image: resizedImage)
        let encoderOutput = try! self.encoder.prediction(input: encoderInput)
        self.imageEmbeddings = encoderOutput.image_embeddings
        //print(self.imageProcessor.mapPoints(points: [(100.0, 100.0)]))
    }
    
    public func predictMask(points: [Point]) -> [MTLTexture] {
        let (pointsTensor, labelTensor) = self.imageProcessor.mapPoints(points: points)
        
        let decoderInput = edge_sam_3x_decoderInput(image_embeddings: self.imageEmbeddings, point_coords: pointsTensor, point_labels: labelTensor)
        let decoderOutput = try! self.decoder.prediction(input: decoderInput)
        
        let masks = self.imageProcessor.postprocess(masks: decoderOutput.masks, commandQueue: commandQueue)
        
        return masks
        //return masks
    }
    
}
