import CoreImage
import Foundation

public struct Options {
    /// Width of the saved slide images.
    public var width: CGFloat = 1600
    /// Slide proportions (width / height); 0 keeps what the correction produced.
    public var aspect: CGFloat = 16.0 / 9.0
    /// How far to extend the detected light body of the slide to include a coloured
    /// header / footer, as a share of its height. 0 for slides without one.
    public var padTop: CGFloat = 0.17
    public var padBottom: CGFloat = 0.11
    /// OCR languages, most important first (BCP 47, e.g. "ru-RU", "en-US").
    public var languages: [String] = ["ru-RU", "en-US"]
    public var jpegQuality: Double = 0.82
    public var transcript: Transcript?
    /// Language of the headings in slides.md.
    public var labels: Labels = .current

    public init() {}
}

public struct Slide: Codable, Identifiable {
    public var id: Int { number }
    public var number: Int
    public var file: String
    public var source: String
    public var time: String
    public var title: String
    public var text: [String]
    public var confidence: Float
    public var cropped: Bool
    public var speech: String?
}

public struct Report {
    public var slides: [Slide]
    /// Repeated shots of the same slide that were dropped.
    public var skipped: [String]
    /// Speech was matched by capture time (true) or by text (false); nil — no transcript.
    public var transcriptByTime: Bool?
    public var markdown: URL
}

public enum Progress {
    case started(total: Int)
    case slide(Slide, imageURL: URL, done: Int, total: Int)
    case skipped(String, done: Int, total: Int)
}

public struct Labels {
    public var slide, untitled, slideText, lecturer, draft, slidesCount, skipped: String

    public static let en = Labels(slide: "Slide", untitled: "untitled", slideText: "Slide text",
                                  lecturer: "Lecturer", draft: "Draft by SlideSnap", slidesCount: "slides",
                                  skipped: "repeated shots dropped")
    public static let ru = Labels(slide: "Слайд", untitled: "без заголовка", slideText: "Текст слайда",
                                  lecturer: "Лектор", draft: "Черновик SlideSnap", slidesCount: "слайдов",
                                  skipped: "повторные снимки пропущены")
    public static var current: Labels {
        Locale.preferredLanguages.first?.hasPrefix("ru") == true ? .ru : .en
    }
}

public enum Pipeline {
    /// Processes `inputs` into `outDir`: slide-01.jpg …, slides.md, slides.json.
    /// `isCancelled` is checked between slides.
    public static func run(inputs: [URL], outDir: URL, options opt: Options,
                           isCancelled: () -> Bool = { false },
                           progress: (Progress) -> Void = { _ in }) throws -> Report {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let pages = Inputs.pages(from: inputs)
        progress(.started(total: pages.count))

        let ctx = CIContext()
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss"
        var slides: [Slide] = [], dates: [Date?] = [], skipped: [String] = []
        var lastWords: Set<String> = []

        for (n, page) in pages.enumerated() {
            if isCancelled() { throw CancellationError() }
            guard let img = page.load() else { continue }
            let rect = Imaging.detectSlide(Imaging.scaled(img, width: 1200))
            let slideImg = rect.map { Imaging.corrected(img, $0, opt) } ?? img
            let ocr = Imaging.recognize(Imaging.scaled(slideImg, width: 2400), languages: opt.languages,
                                        hasHeader: rect != nil && opt.padTop > 0)

            // Same slide shot again: keep the shot with the more confident OCR.
            let w = Imaging.words(ocr.lines)
            if w.count >= 3, !lastWords.isEmpty,
               Double(w.intersection(lastWords).count) / Double(w.union(lastWords).count) > 0.85 {
                if ocr.confidence <= slides[slides.count - 1].confidence {
                    skipped.append(page.name)
                    progress(.skipped(page.name, done: n + 1, total: pages.count))
                    continue
                }
                skipped.append(slides.removeLast().source)
                dates.removeLast()
            }
            lastWords = w

            let number = slides.count + 1
            let file = String(format: "slide-%02d.jpg", number)
            let url = outDir.appendingPathComponent(file)
            // No photo metadata in the output (phone model, location).
            let out = Imaging.scaled(Imaging.enhanced(slideImg), width: opt.width).settingProperties([:])
            try ctx.writeJPEGRepresentation(
                of: out, to: url, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): opt.jpegQuality])
            let slide = Slide(number: number, file: file, source: page.name,
                              time: page.date.map(clock.string(from:)) ?? "", title: ocr.title,
                              text: ocr.lines, confidence: ocr.confidence, cropped: rect != nil, speech: nil)
            slides.append(slide)
            dates.append(page.date)
            progress(.slide(slide, imageURL: url, done: n + 1, total: pages.count))
        }

        // A dropped duplicate shifts numbering: rename files to stay sequential.
        for i in slides.indices {
            let want = String(format: "slide-%02d.jpg", i + 1)
            if slides[i].file != want {
                let dst = outDir.appendingPathComponent(want)
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.moveItem(at: outDir.appendingPathComponent(slides[i].file), to: dst)
                slides[i].file = want
            }
            slides[i].number = i + 1
        }
        // Leftovers of an earlier, longer run into the same folder.
        var extra = slides.count + 1
        while FileManager.default.fileExists(atPath: outDir.appendingPathComponent(String(format: "slide-%02d.jpg", extra)).path) {
            try? FileManager.default.removeItem(at: outDir.appendingPathComponent(String(format: "slide-%02d.jpg", extra)))
            extra += 1
        }

        var byTime: Bool?
        if let t = opt.transcript {
            let (parts, time) = t.split(over: slides, dates: dates)
            for i in slides.indices where !parts[i].isEmpty { slides[i].speech = parts[i].joined(separator: " ") }
            byTime = time
        }

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try enc.encode(slides).write(to: outDir.appendingPathComponent("slides.json"))
        let md = outDir.appendingPathComponent("slides.md")
        try markdown(slides, skipped: skipped, outDir: outDir, labels: opt.labels)
            .write(to: md, atomically: true, encoding: .utf8)
        return Report(slides: slides, skipped: skipped, transcriptByTime: byTime, markdown: md)
    }

    /// Inside an Obsidian vault images are embedded as ![[path/from/vault/root]],
    /// elsewhere as plain relative Markdown links.
    static func markdown(_ slides: [Slide], skipped: [String], outDir: URL, labels L: Labels) -> String {
        let vaultPath = obsidianPath(of: outDir)
        var md = "# \(outDir.lastPathComponent)\n\n\(L.draft): \(slides.count) \(L.slidesCount)"
        md += skipped.isEmpty ? ".\n" : "; \(L.skipped): \(skipped.joined(separator: ", ")).\n"
        for s in slides {
            let when = s.time.isEmpty ? "" : " · \(s.time.prefix(5))"
            md += "\n## \(L.slide) \(s.number)\(when) — \(s.title.isEmpty ? L.untitled : s.title)\n\n"
            md += vaultPath.map { "![[\($0)/\(s.file)]]\n" } ?? "![\(L.slide) \(s.number)](\(s.file))\n"
            if !s.text.isEmpty {
                md += "\n> [!note]- \(L.slideText)\n" + s.text.map { "> \($0)\n" }.joined()
            }
            if let sp = s.speech {
                md += "\n> [!quote]- \(L.lecturer)\n> \(sp)\n"
            }
        }
        return md
    }

    static func obsidianPath(of dir: URL) -> String? {
        var cur = dir.standardizedFileURL
        let parts = cur.pathComponents
        for depth in 0..<parts.count {
            if FileManager.default.fileExists(atPath: cur.appendingPathComponent(".obsidian").path) {
                return parts.suffix(depth).joined(separator: "/")
            }
            cur.deleteLastPathComponent()
        }
        return nil
    }
}
