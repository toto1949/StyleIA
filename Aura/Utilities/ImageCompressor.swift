import UIKit

enum ImageCompressionError: Error {
    case jpegEncodingFailed
}

struct ImageCompressor {
    func compressedJPEGData(
        from image: UIImage,
        maxLongestSide: CGFloat = 1024,
        quality: CGFloat = 0.82
    ) throws -> Data {
        let resized = image.resized(maxLongestSide: maxLongestSide)
        guard let data = resized.jpegData(compressionQuality: quality) else {
            throw ImageCompressionError.jpegEncodingFailed
        }
        return data
    }
}
