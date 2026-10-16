import AppKit
import Foundation
import SlideSnapCore

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

struct SlideItem: Identifiable {
    var slide: Slide
    var imageURL: URL
    var thumbnail: NSImage?
    var id: Int { slide.number }
}

enum AspectChoice: String, CaseIterable, Identifiable {
    case wide = "16:9", classic = "4:3", asIs = "0"
    var id: String { rawValue }
    var value: CGFloat { self == .wide ? 16.0 / 9.0 : self == .classic ? 4.0 / 3.0 : 0 }
    var label: String { self == .asIs ? L10n.t("aspect.asis") : rawValue }
}

enum LanguageChoice: String, CaseIterable, Identifiable {
    case ru, en, uk, de, fr, es
    var id: String { rawValue }
    var label: String { L10n.t("lang.\(rawValue)") }
    var codes: [String] {
        switch self {
        case .ru: ["ru-RU", "en-US"]
        case .en: ["en-US"]
        case .uk: ["uk-UA", "en-US"]
        case .de: ["de-DE", "en-US"]
        case .fr: ["fr-FR", "en-US"]
        case .es: ["es-ES", "en-US"]
        }
    }
}

@MainActor
final class Model: ObservableObject {
    enum Phase: Equatable { case idle, running(done: Int, total: Int), finished, failed(String) }

    @Published var inputs: [URL] = [] { didSet { pageCount = Inputs.pages(from: inputs).count } }
    @Published private(set) var pageCount = 0
    @Published var transcriptURL: URL?
    @Published var transcriptError: String?
    @Published var customOutput: URL?
    @Published var aspect: AspectChoice = .wide
    @Published var hasHeader = true
    @Published var language: LanguageChoice = L10n.isRussian ? .ru : .en
    @Published var width = 1600
    @Published var phase: Phase = .idle
    @Published var items: [SlideItem] = []
    @Published var summary = ""
    @Published var markdownURL: URL?

    private var cancel = CancelFlag()

    var isRunning: Bool { if case .running = phase { return true } else { return false } }

    /// Default: a "<name> SlideSnap" folder next to the first input.
    var outputDir: URL? {
        if let customOutput { return customOutput }
        guard let first = inputs.first else { return nil }
        let name = first.deletingPathExtension().lastPathComponent
        return first.deletingLastPathComponent().appendingPathComponent("\(name) SlideSnap")
    }

    func addInputs(_ urls: [URL]) {
        let usable = urls.filter { url in
            var dir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &dir)
            let ext = url.pathExtension.lowercased()
            return dir.boolValue || ext == "pdf" || Inputs.imageExtensions.contains(ext)
        }
        let txt = urls.first { ["txt", "md"].contains($0.pathExtension.lowercased()) }
        if let txt { setTranscript(txt) }
        guard !usable.isEmpty else { return }
        inputs = Array(Set(inputs + usable)).sorted { $0.path < $1.path }
        phase = .idle
    }

    func setTranscript(_ url: URL?) {
        transcriptURL = url
        transcriptError = url.flatMap { Transcript(url: $0) == nil ? L10n.t("transcript.bad") : nil }
    }

    func choose(files: Bool, directories: Bool, types: [String]? = nil, multiple: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = files
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = multiple
        panel.canCreateDirectories = directories && !files
        return panel.runModal() == .OK ? panel.urls : []
    }

    func run() {
        guard let out = outputDir, !inputs.isEmpty else { return }
        var opt = Options()
        opt.width = CGFloat(width)
        opt.aspect = aspect.value
        opt.padTop = hasHeader ? 0.17 : 0
        opt.padBottom = hasHeader ? 0.11 : 0
        opt.languages = language.codes
        opt.labels = L10n.isRussian ? .ru : .en
        if let transcriptURL { opt.transcript = Transcript(url: transcriptURL) }

        items = []
        summary = ""
        markdownURL = nil
        phase = .running(done: 0, total: pageCount)
        let flag = CancelFlag()
        cancel = flag
        let inputs = self.inputs

        Task.detached(priority: .userInitiated) {
            do {
                let report = try Pipeline.run(inputs: inputs, outDir: out, options: opt,
                                              isCancelled: { flag.isSet }) { p in
                    // Thumbnail decoded off the main thread.
                    var thumb: NSImage?
                    if case .slide(_, let url, _, _) = p { thumb = Self.thumbnail(url) }
                    Task { @MainActor [weak self] in self?.apply(p, thumb) }
                }
                await MainActor.run { self.finish(report) }
            } catch is CancellationError {
                await MainActor.run { self.phase = .idle }
            } catch {
                await MainActor.run { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    func stop() { cancel.set() }

    private func apply(_ p: SlideSnapCore.Progress, _ thumb: NSImage?) {
        guard isRunning else { return }
        switch p {
        case .started(let total):
            phase = .running(done: 0, total: total)
        case .slide(let s, let url, let done, let total):
            items.append(SlideItem(slide: s, imageURL: url, thumbnail: thumb))
            phase = .running(done: done, total: total)
        case .skipped(_, let done, let total):
            phase = .running(done: done, total: total)
        }
    }

    private func finish(_ r: Report) {
        // Numbers / files may have shifted after dropping repeats.
        let dir = r.markdown.deletingLastPathComponent()
        items = r.slides.map { s in
            let url = dir.appendingPathComponent(s.file)
            let old = items.first { $0.slide.source == s.source }
            return SlideItem(slide: s, imageURL: url, thumbnail: old?.thumbnail ?? Self.thumbnail(url))
        }
        var parts = [L10n.t("done", r.slides.count)]
        if !r.skipped.isEmpty { parts.append(L10n.t("done.skipped", r.skipped.count)) }
        if let t = r.transcriptByTime { parts.append(L10n.t(t ? "done.byTime" : "done.byText")) }
        summary = parts.joined(separator: " · ")
        markdownURL = r.markdown
        phase = .finished
    }

    nonisolated static func thumbnail(_ url: URL) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 640,
              ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func copyMarkdown() -> Bool {
        guard let url = markdownURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
}
