import Foundation

enum UploadReportStore {
    static var url: URL {
        projectRoot.appendingPathComponent(AppConfig.reportFileName)
    }

    static func load() -> UploadReport {
        guard let data = try? Data(contentsOf: url) else {
            return UploadReport()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(UploadReport.self, from: data)) ?? UploadReport()
    }

    static func save(_ report: UploadReport) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(report) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
