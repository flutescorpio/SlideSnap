import Foundation
import SlideSnapCore

let usage = """
usage: slidesnap <photos folder | file.pdf | photos…> -o <output folder>
                 [--transcript file.txt] [--start "2026-10-15 16:28:00"]
                 [--width 1600] [--aspect 16:9|4:3|0] [--pad-top 0.17] [--pad-bottom 0.11]
                 [--lang ru-RU,en-US]
"""

var inputs: [URL] = []
var out: URL?
var opt = Options()
var transcriptPath: String?
var start: Date?
var it = CommandLine.arguments.dropFirst().makeIterator()
let num = { (s: String?, d: CGFloat) in CGFloat(Double(s ?? "") ?? Double(d)) }
while let a = it.next() {
    switch a {
    case "-o", "--out": out = it.next().map { URL(fileURLWithPath: $0) }
    case "--transcript": transcriptPath = it.next()
    case "--start":
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        start = it.next().flatMap(f.date(from:))
    case "--width": opt.width = num(it.next(), 1600)
    case "--pad-top": opt.padTop = num(it.next(), 0.17)
    case "--pad-bottom": opt.padBottom = num(it.next(), 0.11)
    case "--aspect":
        let p = (it.next() ?? "").split(separator: ":").compactMap { Double($0) }
        opt.aspect = p.count == 2 ? CGFloat(p[0] / p[1]) : 0
    case "--lang": opt.languages = (it.next() ?? "").split(separator: ",").map(String.init)
    case "-h", "--help": print(usage); exit(0)
    default: inputs.append(URL(fileURLWithPath: a))
    }
}
guard !inputs.isEmpty, let out else {
    FileHandle.standardError.write((usage + "\n").data(using: .utf8)!)
    exit(2)
}
if let transcriptPath {
    guard let t = Transcript(url: URL(fileURLWithPath: transcriptPath), start: start) else {
        FileHandle.standardError.write("cannot read transcript: \(transcriptPath)\n".data(using: .utf8)!)
        exit(1)
    }
    opt.transcript = t
}

let report = try Pipeline.run(inputs: inputs, outDir: out, options: opt) { p in
    switch p {
    case .started(let total): print("\(total) pages")
    case .slide(let s, _, _, _): print("\(s.file) ← \(s.source)\(s.cropped ? "" : "  [slide not found, whole frame]")  \(s.title)")
    case .skipped(let name, _, _): print("repeat, skipped: \(name)")
    }
}
if let byTime = report.transcriptByTime {
    print("transcript matched \(byTime ? "by capture time" : "by text")")
}
print("done: \(report.slides.count) slides → \(report.markdown.path)")
