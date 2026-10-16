import AppKit
import SlideSnapCore
import SwiftUI

private let accent = Color(red: 0.36, green: 0.30, blue: 0.85)

struct ContentView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 340)
                .background(.regularMaterial)
            Divider()
            Results()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 940, minHeight: 640)
        .tint(accent)
    }
}

// MARK: - Left panel: inputs, settings, run

private struct Sidebar: View {
    @EnvironmentObject var model: Model
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SlideSnap").font(.title2.bold())
                    Text(L10n.t("subtitle")).font(.caption).foregroundStyle(.secondary)
                }
            }

            DropZone()

            Section(title: L10n.t("transcript"), detail: L10n.t("transcript.optional")) {
                HStack {
                    Image(systemName: "waveform").foregroundStyle(.secondary)
                    Text(model.transcriptURL?.lastPathComponent ?? L10n.t("transcript.none"))
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(model.transcriptURL == nil ? .secondary : .primary)
                    Spacer()
                    if model.transcriptURL != nil {
                        Button { model.setTranscript(nil) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                    Button(L10n.t("choose")) {
                        model.setTranscript(model.choose(files: true, directories: false, multiple: false).first)
                    }
                }
                if let err = model.transcriptError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                model.setTranscript(urls.first)
                return true
            }

            Section(title: L10n.t("output")) {
                HStack {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(model.outputDir.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
                         ?? L10n.t("output.auto"))
                        .lineLimit(2).truncationMode(.middle)
                        .font(.callout)
                        .foregroundStyle(model.outputDir == nil ? .secondary : .primary)
                    Spacer()
                    Button(L10n.t("change")) {
                        if let dir = model.choose(files: false, directories: true, multiple: false).first {
                            model.customOutput = dir
                        }
                    }
                }
            }

            DisclosureGroup(isExpanded: $showSettings) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(L10n.t("aspect"), selection: $model.aspect) {
                        ForEach(AspectChoice.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle(L10n.t("header"), isOn: $model.hasHeader)
                        .help(L10n.t("header.help"))
                    Picker(L10n.t("language"), selection: $model.language) {
                        ForEach(LanguageChoice.allCases) { Text($0.label).tag($0) }
                    }
                    Picker(L10n.t("width"), selection: $model.width) {
                        ForEach([1280, 1600, 2000, 2560], id: \.self) { Text(verbatim: "\($0) px").tag($0) }
                    }
                }
                .padding(.top, 8)
            } label: {
                Label(L10n.t("settings"), systemImage: "slider.horizontal.3").font(.headline)
            }

            Spacer(minLength: 0)

            RunPanel()
        }
        .padding(20)
    }
}

private struct Section<Content: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            content
        }
    }
}

private struct DropZone: View {
    @EnvironmentObject var model: Model
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 10) {
            if model.inputs.isEmpty {
                Image(systemName: "photo.stack")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(targeted ? accent : .secondary)
                Text(L10n.t("drop.title")).font(.callout.weight(.medium)).multilineTextAlignment(.center)
                Text(L10n.t("drop.hint")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(L10n.t("choose")) {
                    model.addInputs(model.choose(files: true, directories: true, multiple: true))
                }
                .padding(.top, 2)
            } else {
                HStack(alignment: .top) {
                    Image(systemName: "photo.stack.fill").font(.title2).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("inputs.summary", model.pageCount)).font(.callout.weight(.semibold))
                        ForEach(model.inputs.prefix(3), id: \.self) {
                            Text($0.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        if model.inputs.count > 3 {
                            Text("+\(model.inputs.count - 3)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(L10n.t("clear")) { model.inputs = []; model.customOutput = nil }
                        .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: model.inputs.isEmpty ? 150 : 0)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(targeted ? accent.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(targeted ? accent : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: model.inputs.isEmpty ? [6, 5] : []))
        )
        .dropDestination(for: URL.self) { urls, _ in
            model.addInputs(urls)
            return true
        } isTargeted: { targeted = $0 }
        .animation(.easeOut(duration: 0.15), value: targeted)
    }
}

private struct RunPanel: View {
    @EnvironmentObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.phase {
            case .running(let done, let total):
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                HStack {
                    Text(done == 0 ? L10n.t("starting") : L10n.t("progress", done, total))
                        .font(.callout).monospacedDigit()
                    Spacer()
                    Button(L10n.t("cancel")) { model.stop() }
                }
            case .failed(let msg):
                Text(L10n.t("failed", msg)).font(.callout).foregroundStyle(.red)
                runButton
            default:
                runButton
            }
        }
    }

    private var runButton: some View {
        Button { model.run() } label: {
            Label(L10n.t("run"), systemImage: "wand.and.stars")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(model.inputs.isEmpty)
    }
}

// MARK: - Right panel: slides

private struct Results: View {
    @EnvironmentObject var model: Model
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            if model.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                    Text(L10n.t("empty.title")).font(.title3).foregroundStyle(.secondary)
                    Text(L10n.t("empty.hint")).font(.callout).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center).frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 18) {
                        ForEach(model.items) { SlideCard(item: $0) }
                    }
                    .padding(20)
                }
            }

            if model.phase == .finished {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(model.summary).font(.callout).lineLimit(1).truncationMode(.tail)
                        .help(model.summary)
                        .layoutPriority(-1)
                    Spacer(minLength: 8)
                    Button(L10n.t("finder")) {
                        if let url = model.markdownURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Button(L10n.t("openMd")) {
                        if let url = model.markdownURL { NSWorkspace.shared.open(url) }
                    }
                    Button {
                        copied = model.copyMarkdown()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    } label: {
                        Label(copied ? L10n.t("copied") : L10n.t("copy"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .help(L10n.t("copy.help"))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SlideCard: View {
    var item: SlideItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let img = item.thumbnail {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle().fill(.quaternary).aspectRatio(16 / 9, contentMode: .fit)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                Text("\(item.slide.number)")
                    .font(.caption.bold()).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
            }
            .onTapGesture(count: 2) { NSWorkspace.shared.open(item.imageURL) }

            Text(item.slide.title.isEmpty ? "—" : item.slide.title)
                .font(.callout.weight(.medium)).lineLimit(2)
            HStack(spacing: 6) {
                if !item.slide.time.isEmpty {
                    Label(String(item.slide.time.prefix(5)), systemImage: "clock")
                }
                if item.slide.speech != nil {
                    Label("", systemImage: "waveform").labelStyle(.iconOnly)
                }
                if !item.slide.cropped {
                    Label(L10n.t("notFound"), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .help(item.slide.text.joined(separator: "\n"))
    }
}
