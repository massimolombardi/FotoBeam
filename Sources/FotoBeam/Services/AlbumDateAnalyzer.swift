import Foundation

struct AlbumDateAnalyzer {
    private let dateReader = MediaDateReader()

    func analyze(files: [URL]) -> AlbumDateAnalysis {
        let calendar = Calendar.current
        let capturedItems = files.map { file -> (file: URL, date: Date?, source: RenameDateSource, year: Int?) in
            let captured = dateReader.captureDate(for: file)
            let year = captured.date.map { calendar.component(.year, from: $0) }
            return (file, captured.date, captured.source, year)
        }

        let yearCounts = Dictionary(grouping: capturedItems.compactMap(\.year), by: { $0 })
            .mapValues(\.count)
        let majorityYear = yearCounts.max { first, second in
            if first.value == second.value {
                return first.key > second.key
            }
            return first.value < second.value
        }?.key

        let items = capturedItems.map { entry -> AlbumDateItem in
            var issues: [AlbumDateIssue] = []
            if entry.date == nil {
                issues.append(.unavailable)
            }
            if entry.source == .fileCreationDate || entry.source == .fileModificationDate {
                issues.append(.weakDate)
            }
            if
                let majorityYear,
                let year = entry.year,
                year != majorityYear,
                (yearCounts[majorityYear] ?? 0) > 1
            {
                issues.append(.differentYear)
            }
            return AlbumDateItem(file: entry.file, date: entry.date, dateSource: entry.source, year: entry.year, issues: issues)
        }
        .sorted { first, second in
            switch (first.date, second.date) {
            case let (firstDate?, secondDate?):
                if firstDate == secondDate {
                    return first.file.path.localizedStandardCompare(second.file.path) == .orderedAscending
                }
                return firstDate < secondDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return first.file.path.localizedStandardCompare(second.file.path) == .orderedAscending
            }
        }

        let summary = AlbumDateSummary(
            fileCount: files.count,
            dateRange: dateReader.fileDateRange(files: files),
            years: yearCounts.keys.sorted(),
            majorityYear: majorityYear,
            suspiciousCount: items.filter { !$0.issues.isEmpty }.count,
            weakDateCount: items.filter { $0.issues.contains(.weakDate) }.count,
            unavailableCount: items.filter { $0.issues.contains(.unavailable) }.count
        )
        return AlbumDateAnalysis(items: items, summary: summary)
    }
}
