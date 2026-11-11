import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
final class OutsideSelectionBlur {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private let maximumDimension: CGFloat = 2048
    private var sourceImage: CGImage?
    private var cachedImage: CGImage?

    func image(for source: CGImage) -> CGImage? {
        if sourceImage === source {
            return cachedImage
        }

        sourceImage = source
        cachedImage = nil

        let longestSide = CGFloat(max(source.width, source.height))
        let scale = min(1, maximumDimension / longestSide)
        let extent = CGRect(x: 0, y: 0,
                            width: CGFloat(source.width) * scale,
                            height: CGFloat(source.height) * scale)
        let input = CIImage(cgImage: source)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .clampedToExtent()
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input
        filter.radius = Float(14 * scale)
        guard let output = filter.outputImage?.cropped(to: extent),
              let result = Self.context.createCGImage(output, from: extent)
        else {
            return nil
        }

        cachedImage = result
        return result
    }
}
