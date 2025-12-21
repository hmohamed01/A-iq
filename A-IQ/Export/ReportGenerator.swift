import AppKit
import CoreGraphics
import Foundation
import OSLog
import PDFKit
import UniformTypeIdentifiers

// MARK: - Logger

private let exportLogger = Logger(subsystem: "com.aiq.app", category: "Export")

// MARK: - Report Generator

/// Generates JSON and PDF reports from analysis results
/// Implements: Req 9.1, 9.2, 9.3, 9.4, 9.5
struct ReportGenerator {
    // MARK: JSON Export

    /// Generate JSON report for a single result
    /// Implements: Req 9.1
    func generateJSON(_ result: AggregatedResult) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(result)
    }

    /// Generate JSON report for batch results
    /// Implements: Req 9.4
    func generateBatchJSON(_ results: [AggregatedResult]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let report = BatchReport(
            generatedAt: Date(),
            totalImages: results.count,
            summary: generateBatchSummary(results),
            results: results
        )

        return try encoder.encode(report)
    }

    // MARK: PDF Export

    /// Generate PDF report for a single result
    /// Implements: Req 9.2
    func generatePDF(_ result: AggregatedResult) -> Data? {
        let pdfDocument = PDFDocument()

        // Create the main page
        if let page = createResultPage(result, pageNumber: 1, totalPages: 1) {
            pdfDocument.insert(page, at: 0)
        }

        return pdfDocument.dataRepresentation()
    }

    /// Generate PDF report for batch results
    /// Implements: Req 9.5
    func generateBatchPDF(_ results: [AggregatedResult]) -> Data? {
        let pdfDocument = PDFDocument()

        // Add summary page
        if let summaryPage = createSummaryPage(results) {
            pdfDocument.insert(summaryPage, at: 0)
        }

        // Add individual result pages
        for (index, result) in results.enumerated() {
            if let page = createResultPage(result, pageNumber: index + 2, totalPages: results.count + 1) {
                pdfDocument.insert(page, at: pdfDocument.pageCount)
            }
        }

        return pdfDocument.dataRepresentation()
    }

    // MARK: Export Dialog

    /// Export with save dialog
    /// Implements: Req 9.3
    @MainActor
    func exportWithDialog(
        _ result: AggregatedResult,
        format: ExportFormat,
        suggestedFilename: String
    ) async -> Bool {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename

        switch format {
        case .json:
            panel.allowedContentTypes = [.json]
        case .pdf:
            panel.allowedContentTypes = [.pdf]
        }

        let response = await panel.beginSheetModal(for: NSApp.keyWindow!)

        guard response == .OK, let url = panel.url else {
            return false
        }

        do {
            let data: Data?
            switch format {
            case .json:
                data = try generateJSON(result)
            case .pdf:
                data = generatePDF(result)
            }

            guard let exportData = data else {
                return false
            }

            try exportData.write(to: url)
            return true

        } catch {
            exportLogger.error("Export failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Export batch with save dialog
    @MainActor
    func exportBatchWithDialog(
        _ results: [AggregatedResult],
        format: ExportFormat,
        suggestedFilename: String
    ) async -> Bool {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename

        switch format {
        case .json:
            panel.allowedContentTypes = [.json]
        case .pdf:
            panel.allowedContentTypes = [.pdf]
        }

        let response = await panel.beginSheetModal(for: NSApp.keyWindow!)

        guard response == .OK, let url = panel.url else {
            return false
        }

        do {
            let data: Data?
            switch format {
            case .json:
                data = try generateBatchJSON(results)
            case .pdf:
                data = generateBatchPDF(results)
            }

            guard let exportData = data else {
                return false
            }

            try exportData.write(to: url)
            return true

        } catch {
            exportLogger.error("Batch export failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: PDF Page Creation

    private func createResultPage(
        _ result: AggregatedResult,
        pageNumber: Int,
        totalPages: Int
    ) -> PDFPage? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            return nil
        }

        context.beginPDFPage(nil)

        // Draw content
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        drawResultPage(result, in: pageRect, pageNumber: pageNumber, totalPages: totalPages)

        NSGraphicsContext.restoreGraphicsState()

        context.endPDFPage()
        context.closePDF()

        guard let document = PDFDocument(data: pdfData as Data),
              let page = document.page(at: 0)
        else {
            return nil
        }

        return page
    }

    private func createSummaryPage(_ results: [AggregatedResult]) -> PDFPage? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            return nil
        }

        context.beginPDFPage(nil)

        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        drawSummaryPage(results, in: pageRect)

        NSGraphicsContext.restoreGraphicsState()

        context.endPDFPage()
        context.closePDF()

        guard let document = PDFDocument(data: pdfData as Data),
              let page = document.page(at: 0)
        else {
            return nil
        }

        return page
    }

    // MARK: PDF Drawing

    private func drawResultPage(
        _ result: AggregatedResult,
        in rect: CGRect,
        pageNumber: Int,
        totalPages: Int
    ) {
        let margin: CGFloat = 50
        var yPosition = rect.height - margin

        // Header
        let titleFont = NSFont.boldSystemFont(ofSize: 24)
        let title = "A-IQ Analysis Report"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.black,
        ]
        title.draw(at: NSPoint(x: margin, y: yPosition - 24), withAttributes: titleAttrs)
        yPosition -= 40

        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let dateString = dateFormatter.string(from: result.timestamp)
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.gray,
        ]
        dateString.draw(at: NSPoint(x: margin, y: yPosition - 12), withAttributes: dateAttrs)
        yPosition -= 30

        // Divider
        NSColor.lightGray.setStroke()
        let dividerPath = NSBezierPath()
        dividerPath.move(to: NSPoint(x: margin, y: yPosition))
        dividerPath.line(to: NSPoint(x: rect.width - margin, y: yPosition))
        dividerPath.stroke()
        yPosition -= 20

        // Classification
        let classificationFont = NSFont.boldSystemFont(ofSize: 18)
        let classificationColor = colorForClassification(result.classification)
        let classificationAttrs: [NSAttributedString.Key: Any] = [
            .font: classificationFont,
            .foregroundColor: classificationColor,
        ]
        result.classification.displayName.draw(at: NSPoint(x: margin, y: yPosition - 18), withAttributes: classificationAttrs)
        yPosition -= 30

        // Score
        let scoreText = "Confidence Score: \(result.scorePercentage)%"
        let scoreAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.black,
        ]
        scoreText.draw(at: NSPoint(x: margin, y: yPosition - 14), withAttributes: scoreAttrs)
        yPosition -= 25

        // Summary
        let summaryAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.darkGray,
        ]
        result.summary.draw(at: NSPoint(x: margin, y: yPosition - 12), withAttributes: summaryAttrs)
        yPosition -= 40

        // Signal Breakdown Section
        let sectionFont = NSFont.boldSystemFont(ofSize: 14)
        let sectionAttrs: [NSAttributedString.Key: Any] = [
            .font: sectionFont,
            .foregroundColor: NSColor.black,
        ]
        "Signal Breakdown".draw(at: NSPoint(x: margin, y: yPosition - 14), withAttributes: sectionAttrs)
        yPosition -= 25

        // Draw breakdown bars
        for (name, contribution, _) in result.signalBreakdown.allContributions {
            drawSignalBar(
                name: name,
                contribution: contribution,
                at: NSPoint(x: margin, y: yPosition - 20),
                width: rect.width - 2 * margin
            )
            yPosition -= 30
        }

        yPosition -= 20

        // Evidence Section
        "Evidence".draw(at: NSPoint(x: margin, y: yPosition - 14), withAttributes: sectionAttrs)
        yPosition -= 25

        let evidenceAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.darkGray,
        ]

        for evidence in result.allEvidence.prefix(10) {
            let bullet = evidence.isPositiveIndicator ? "▲" : "▼"
            let text = "\(bullet) \(evidence.description)"
            text.draw(at: NSPoint(x: margin + 10, y: yPosition - 11), withAttributes: evidenceAttrs)
            yPosition -= 18
        }

        // Footer
        let footerText = "Page \(pageNumber) of \(totalPages) • Generated by A-IQ"
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.gray,
        ]
        footerText.draw(at: NSPoint(x: margin, y: margin - 10), withAttributes: footerAttrs)
    }

    private func drawSummaryPage(_ results: [AggregatedResult], in rect: CGRect) {
        let margin: CGFloat = 50
        var yPosition = rect.height - margin

        // Title
        let titleFont = NSFont.boldSystemFont(ofSize: 24)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.black,
        ]
        "A-IQ Batch Analysis Summary".draw(at: NSPoint(x: margin, y: yPosition - 24), withAttributes: titleAttrs)
        yPosition -= 50

        // Summary stats
        let summary = generateBatchSummary(results)
        let statsFont = NSFont.systemFont(ofSize: 14)
        let statsAttrs: [NSAttributedString.Key: Any] = [
            .font: statsFont,
            .foregroundColor: NSColor.black,
        ]

        "Total Images Analyzed: \(summary.totalImages)".draw(at: NSPoint(x: margin, y: yPosition - 14), withAttributes: statsAttrs)
        yPosition -= 25

        "Likely Authentic: \(summary.likelyAuthentic)".draw(at: NSPoint(x: margin, y: yPosition - 14), withAttributes: statsAttrs)
        yPosition -= 20

        "Uncertain: \(summary.uncertain)".draw(at: NSPoint(x: margin, y: yPosition - 14), withAttributes: statsAttrs)
        yPosition -= 20

        "Likely AI-Generated: \(summary.likelyAIGenerated)".draw(at: NSPoint(x: margin, y: yPosition - 14), withAttributes: statsAttrs)
        yPosition -= 20

        "Confirmed AI-Generated: \(summary.confirmedAIGenerated)".draw(at: NSPoint(x: margin, y: yPosition - 14), withAttributes: statsAttrs)
        yPosition -= 40

        // Results table header
        let headerFont = NSFont.boldSystemFont(ofSize: 12)
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: NSColor.black,
        ]

        "Filename".draw(at: NSPoint(x: margin, y: yPosition - 12), withAttributes: headerAttrs)
        "Classification".draw(at: NSPoint(x: 300, y: yPosition - 12), withAttributes: headerAttrs)
        "Score".draw(at: NSPoint(x: 450, y: yPosition - 12), withAttributes: headerAttrs)
        yPosition -= 20

        // Divider
        NSColor.lightGray.setStroke()
        let dividerPath = NSBezierPath()
        dividerPath.move(to: NSPoint(x: margin, y: yPosition))
        dividerPath.line(to: NSPoint(x: rect.width - margin, y: yPosition))
        dividerPath.stroke()
        yPosition -= 15

        // Results list
        let rowAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.darkGray,
        ]

        for result in results.prefix(25) {
            let filename = result.imageSource.displayName
            filename.draw(at: NSPoint(x: margin, y: yPosition - 11), withAttributes: rowAttrs)

            let classificationAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: colorForClassification(result.classification),
            ]
            result.classification.shortName.draw(at: NSPoint(x: 300, y: yPosition - 11), withAttributes: classificationAttrs)

            "\(result.scorePercentage)%".draw(at: NSPoint(x: 450, y: yPosition - 11), withAttributes: rowAttrs)
            yPosition -= 18
        }
    }

    private func drawSignalBar(
        name: String,
        contribution: SignalContribution,
        at point: NSPoint,
        width: CGFloat
    ) {
        let labelWidth: CGFloat = 100
        let barWidth = width - labelWidth - 60
        let barHeight: CGFloat = 16

        // Label
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.darkGray,
        ]
        name.draw(at: point, withAttributes: labelAttrs)

        // Background bar
        let barRect = NSRect(x: point.x + labelWidth, y: point.y, width: barWidth, height: barHeight)
        NSColor.lightGray.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 3, yRadius: 3).fill()

        // Fill bar
        if contribution.isAvailable {
            let fillWidth = barWidth * contribution.rawScore
            let fillRect = NSRect(x: point.x + labelWidth, y: point.y, width: fillWidth, height: barHeight)
            colorForScore(contribution.rawScore).setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 3, yRadius: 3).fill()
        }

        // Score text
        let scoreText = contribution.isAvailable ? "\(Int(contribution.rawScore * 100))%" : "N/A"
        let scoreAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.darkGray,
        ]
        scoreText.draw(at: NSPoint(x: point.x + labelWidth + barWidth + 10, y: point.y + 2), withAttributes: scoreAttrs)
    }

    // MARK: Helpers

    private func colorForClassification(_ classification: OverallClassification) -> NSColor {
        switch classification {
        case .likelyAuthentic: return .systemGreen
        case .uncertain: return .systemOrange
        case .likelyAIGenerated, .confirmedAIGenerated: return .systemRed
        }
    }

    private func colorForScore(_ score: Double) -> NSColor {
        if score < 0.3 {
            return .systemGreen
        } else if score < 0.7 {
            return .systemOrange
        } else {
            return .systemRed
        }
    }

    private func generateBatchSummary(_ results: [AggregatedResult]) -> BatchSummary {
        var likelyAuthentic = 0
        var uncertain = 0
        var likelyAIGenerated = 0
        var confirmedAIGenerated = 0

        for result in results {
            switch result.classification {
            case .likelyAuthentic: likelyAuthentic += 1
            case .uncertain: uncertain += 1
            case .likelyAIGenerated: likelyAIGenerated += 1
            case .confirmedAIGenerated: confirmedAIGenerated += 1
            }
        }

        return BatchSummary(
            totalImages: results.count,
            likelyAuthentic: likelyAuthentic,
            uncertain: uncertain,
            likelyAIGenerated: likelyAIGenerated,
            confirmedAIGenerated: confirmedAIGenerated
        )
    }
}

// MARK: - Supporting Types

struct BatchReport: Codable {
    let generatedAt: Date
    let totalImages: Int
    let summary: BatchSummary
    let results: [AggregatedResult]
}

struct BatchSummary: Codable {
    let totalImages: Int
    let likelyAuthentic: Int
    let uncertain: Int
    let likelyAIGenerated: Int
    let confirmedAIGenerated: Int
}
