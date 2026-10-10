import AppKit
import PDFKit

/// What a file is to the line. Photos and videos hang as themselves — a
/// video as its first frame with a play button over it. Audio hangs as a
/// waveform card, text as its first lines, a PDF as its first page, and
/// everything else as its icon and name.
enum FileKind {
    case photo, video, audio, pdf, text, icon
}

func isImageFile(_ url: URL) -> Bool {
    ScreenshotWatcher.imageExtensions.contains(url.pathExtension.lowercased())
}

func fileKind(_ url: URL) -> FileKind {
    let ext = url.pathExtension.lowercased()
    if PaperCard.videoExtensions.contains(ext) { return .video }
    if isImageFile(url) { return .photo }
    if ext == "pdf" { return .pdf }
    if PaperCard.audioExtensions.contains(ext) { return .audio }
    if PaperCard.textExtensions.contains(ext) { return .text }
    return .icon
}

/// The card a file that is not a photo hangs as, drawn in code so it stays
/// sharp at any size.
enum PaperCard {
    /// Videos, screen recordings among them. `isRecording` in Line.swift
    /// keeps the ones macOS saves itself, for the trimming editor.
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]

    /// The extensions previewed as text. Anything else that is not an
    /// image, a video, an audio file or a PDF hangs as its icon and name.
    static let textExtensions: Set<String> = [
        "md", "markdown", "txt", "text", "json", "csv", "tsv", "log",
        "yaml", "yml", "toml", "xml", "html", "rtf",
    ]

    static let audioExtensions: Set<String> = [
        "mp3", "wav", "aac", "m4a", "flac", "ogg", "aiff", "aif",
    ]

    /// An index card in the proportions of the photos around it, so the
    /// line stays even.
    static var pageSize: CGSize {
        let maxW = Layout.cardWidth - 14, maxH = Layout.photoMaxHeight
        let w = min(maxW, maxH * 4 / 3)
        return CGSize(width: w, height: w * 3 / 4)
    }

    static func textCard(_ url: URL) -> NSImage {
        let preview = previewLines(url)
        guard !preview.isEmpty else { return iconCard(url) }
        let size = pageSize
        let s = Layout.size.scale
        let inset: CGFloat = 7 * s
        let leading: CGFloat = 10.5 * s
        let headerStyle = NSMutableParagraphStyle()
        headerStyle.lineBreakMode = .byTruncatingMiddle
        let header: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8 * s, weight: .semibold),
            .foregroundColor: NSColor(white: 0.12, alpha: 1),
            .paragraphStyle: headerStyle,
        ]
        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineBreakMode = .byTruncatingTail
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 7 * s, weight: .regular),
            .foregroundColor: NSColor(white: 0.34, alpha: 1),
            .paragraphStyle: bodyStyle,
        ]
        return NSImage(size: size, flipped: true) { rect in
            paper(rect)
            let width = rect.width - inset * 2
            (url.lastPathComponent as NSString).draw(
                in: NSRect(x: inset, y: inset, width: width, height: leading + 1),
                withAttributes: header)
            // A rule under the name, like on a real index card.
            let ruleY = inset + leading + 3 * s
            NSColor(white: 0.82, alpha: 1).setFill()
            NSRect(x: inset, y: ruleY, width: width, height: 0.5 * s).fill()
            var y = ruleY + 4 * s
            for line in preview {
                guard y + leading <= rect.height - 2 * s else { break }
                (line as NSString).draw(
                    in: NSRect(x: inset, y: y, width: width, height: leading),
                    withAttributes: body)
                y += leading
            }
            return true
        }
    }

    /// An audio file: nothing to show a frame of, so it hangs as a
    /// waveform on paper.
    static func audioCard(_ url: URL) -> NSImage {
        let tint = NSImage.SymbolConfiguration(paletteColors: [NSColor(white: 0.42, alpha: 1)])
        guard let waveform = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
            .withSymbolConfiguration(tint) else { return iconCard(url) }
        return iconLikeCard(url, top: waveform)
    }

    static func iconCard(_ url: URL) -> NSImage {
        iconLikeCard(url, top: NSWorkspace.shared.icon(forFile: url.path))
    }

    /// A paper card with a picture over the name, drawn in code so it stays
    /// sharp at any size.
    private static func iconLikeCard(_ url: URL, top picture: NSImage) -> NSImage {
        let size = pageSize
        let s = Layout.size.scale
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingMiddle
        let name: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8 * s, weight: .semibold),
            .foregroundColor: NSColor(white: 0.12, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        return NSImage(size: size, flipped: true) { rect in
            paper(rect)
            let side = min(rect.width, rect.height) * 0.44
            picture.draw(in: NSRect(x: (rect.width - side) / 2, y: rect.height * 0.10,
                                    width: side, height: side))
            let top = rect.height * 0.10 + side + 5 * s
            (url.lastPathComponent as NSString).draw(
                in: NSRect(x: 6 * s, y: top, width: rect.width - 12 * s,
                           height: rect.height - top - 5 * s),
                withAttributes: name)
            return true
        }
    }

    /// The first page of a PDF, hung like a photo of it.
    static func pdf(_ url: URL, maxPixels: Int) -> NSImage? {
        guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        let side = CGFloat(maxPixels)
        return page.thumbnail(of: CGSize(width: side, height: side), for: .mediaBox)
    }

    // MARK: Reading the preview

    /// The first few non-empty lines of a text file, none longer than a
    /// card can hold. RTF is read through AppKit so it shows words, not
    /// braces. Unreadable or binary content comes back empty, and the file
    /// hangs as its icon instead.
    private static func previewLines(_ url: URL) -> [String] {
        let head: String?
        if url.pathExtension.lowercased() == "rtf" {
            head = (try? NSAttributedString(
                url: url, options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil))?.string
        } else if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            head = String(data: data.prefix(64 * 1024), encoding: .utf8)
        } else {
            head = nil
        }
        guard let head else { return [] }
        return head.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(6)
            .map { String($0.prefix(64)) }
    }

    /// White paper with a hairline edge, so it reads over a light Desktop too.
    private static func paper(_ rect: CGRect) {
        NSColor.white.setFill()
        rect.fill()
        let edge = NSBezierPath(rect: rect.insetBy(dx: 0.25, dy: 0.25))
        edge.lineWidth = 0.5
        NSColor(white: 0, alpha: 0.10).setStroke()
        edge.stroke()
    }
}
