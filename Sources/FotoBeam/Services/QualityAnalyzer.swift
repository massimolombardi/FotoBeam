import AppKit
import CryptoKit
import Foundation
import ImageIO

struct QualityAnalyzer: Sendable {
    func analyze(files: [URL]) -> QualityAnalysis {
        var result = QualityAnalysis()
        var exactHashBuckets: [String: [URL]] = [:]
        var imageHashes: [(file: URL, hash: UInt64)] = []

        for file in files {
            var info = FileQualityInfo()

            if let hash = sha256(file: file) {
                exactHashBuckets[hash, default: []].append(file)
            }

            if isImage(file), let image = cgImage(file: file, maxPixelSize: 256) {
                if let hash = averageHash(image: image) {
                    info.perceptualHash = hash
                    imageHashes.append((file, hash))
                }
                info.blurScore = sharpnessScore(image: image)
            }

            result.files[file.path] = info
        }

        let duplicateGroups = exactHashBuckets.values
            .filter { $0.count > 1 }
            .map { $0.map(\.path).sorted() }
            .sorted { $0.first ?? "" < $1.first ?? "" }

        result.exactDuplicateGroups = duplicateGroups
        for (index, group) in duplicateGroups.enumerated() {
            for path in group {
                result.files[path, default: FileQualityInfo()].exactDuplicateGroup = index
            }
        }

        let similarGroups = findSimilarGroups(imageHashes)
            .map { group in group.map(\.path).sorted() }
            .filter { $0.count > 1 }
            .sorted { $0.first ?? "" < $1.first ?? "" }

        result.similarGroups = similarGroups
        for (index, group) in similarGroups.enumerated() {
            for path in group {
                result.files[path, default: FileQualityInfo()].similarGroup = index
            }
        }

        return result
    }

    private func sha256(file: URL) -> String? {
        guard let stream = InputStream(url: file) else {
            return nil
        }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                return nil
            }
            if count > 0 {
                hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: count))
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func isImage(_ file: URL) -> Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif"].contains(file.pathExtension.lowercased())
    }

    private func cgImage(file: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private func averageHash(image: CGImage) -> UInt64? {
        guard let samples = grayscaleSamples(image: image, width: 8, height: 8), samples.count == 64 else {
            return nil
        }
        let average = samples.reduce(0, +) / Double(samples.count)
        return samples.enumerated().reduce(UInt64(0)) { partial, item in
            item.element >= average ? partial | (UInt64(1) << UInt64(item.offset)) : partial
        }
    }

    private func sharpnessScore(image: CGImage) -> Double? {
        guard let samples = grayscaleSamples(image: image, width: 32, height: 32), samples.count == 1024 else {
            return nil
        }

        var total = 0.0
        var comparisons = 0.0
        for y in 0..<32 {
            for x in 0..<32 {
                let value = samples[y * 32 + x]
                if x + 1 < 32 {
                    total += abs(value - samples[y * 32 + x + 1])
                    comparisons += 1
                }
                if y + 1 < 32 {
                    total += abs(value - samples[(y + 1) * 32 + x])
                    comparisons += 1
                }
            }
        }

        guard comparisons > 0 else {
            return nil
        }
        return total / comparisons
    }

    private func grayscaleSamples(image: CGImage, width: Int, height: Int) -> [Double]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return stride(from: 0, to: pixels.count, by: 4).map { index in
            let red = Double(pixels[index])
            let green = Double(pixels[index + 1])
            let blue = Double(pixels[index + 2])
            return red * 0.299 + green * 0.587 + blue * 0.114
        }
    }

    private func findSimilarGroups(_ hashes: [(file: URL, hash: UInt64)]) -> [[URL]] {
        var parent = Array(0..<hashes.count)

        func root(_ index: Int) -> Int {
            var current = index
            while parent[current] != current {
                current = parent[current]
            }
            return current
        }

        func unite(_ first: Int, _ second: Int) {
            let firstRoot = root(first)
            let secondRoot = root(second)
            if firstRoot != secondRoot {
                parent[secondRoot] = firstRoot
            }
        }

        for first in hashes.indices {
            for second in hashes.indices where second > first {
                let distance = (hashes[first].hash ^ hashes[second].hash).nonzeroBitCount
                if distance <= AppConfig.similarPhotoDistanceThreshold {
                    unite(first, second)
                }
            }
        }

        var groups: [Int: [URL]] = [:]
        for index in hashes.indices {
            groups[root(index), default: []].append(hashes[index].file)
        }
        return groups.values.filter { $0.count > 1 }
    }
}
