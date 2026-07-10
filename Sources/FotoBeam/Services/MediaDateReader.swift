import Foundation
import ImageIO

struct MediaDateReader {
    func captureDate(for file: URL) -> (date: Date?, source: RenameDateSource) {
        if let overrideDate = DateOverrideStore.date(for: file) {
            return (overrideDate, .manualOverride)
        }
        if let imageDate = imageCaptureDate(for: file) {
            return imageDate
        }
        if let date = dateFromFileName(file.lastPathComponent) {
            return (date, .fileName)
        }

        let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        if let creationDate = values?.creationDate {
            return (creationDate, .fileCreationDate)
        }
        if let modificationDate = values?.contentModificationDate {
            return (modificationDate, .fileModificationDate)
        }
        return (nil, .unavailable)
    }

    func fileDateRange(files: [URL]) -> String {
        let dates = files.compactMap { captureDate(for: $0).date }
        guard let minDate = dates.min(), let maxDate = dates.max() else {
            return "N/D"
        }
        let formatter = dayFormatter
        let start = formatter.string(from: minDate)
        let end = formatter.string(from: maxDate)
        return start == end ? start : "\(start) - \(end)"
    }

    private func imageCaptureDate(for file: URL) -> (date: Date, source: RenameDateSource)? {
        guard
            let source = CGImageSourceCreateWithURL(file as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }

        if
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
            let value = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
            let date = exifFormatter.date(from: value)
        {
            return (date, .exifDateTimeOriginal)
        }

        if
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
            let value = tiff[kCGImagePropertyTIFFDateTime] as? String,
            let date = exifFormatter.date(from: value)
        {
            return (date, .imageMetadata)
        }

        return nil
    }

    private func dateFromFileName(_ fileName: String) -> Date? {
        let name = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let pattern = #"^(IMG|VID)_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_\d{3}(?:_\d{3})?$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
            let range = Range(match.range(at: 2), in: name)
        else {
            return nil
        }
        return secondFormatter.date(from: String(name[range]))
    }

    private var secondFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }

    private var exifFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }
}
