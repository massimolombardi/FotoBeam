import AppKit
import Foundation
import ImageIO

@MainActor
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 1_000
    }

    func cachedImage(for file: URL, pixelSize: Int) -> NSImage? {
        cache.object(forKey: cacheKey(file: file, pixelSize: pixelSize) as NSString)
    }

    func image(for file: URL, pixelSize: Int) async -> NSImage? {
        let key = cacheKey(file: file, pixelSize: pixelSize)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let data = await Task.detached(priority: .utility) {
            thumbnailData(for: file, pixelSize: pixelSize)
        }.value

        guard let data, let image = NSImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    private func cacheKey(file: URL, pixelSize: Int) -> String {
        "\(file.path)|\(pixelSize)"
    }
}

private func thumbnailData(for file: URL, pixelSize: Int) -> Data? {
    guard
        let source = CGImageSourceCreateWithURL(file as CFURL, nil),
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelSize
            ] as CFDictionary
        )
    else {
        return nil
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImage(destination, thumbnail, nil)
    guard CGImageDestinationFinalize(destination) else {
        return nil
    }
    return data as Data
}
