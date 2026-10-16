import Foundation

/// A lecture transcript: pieces of speech with their offset from the start of the recording.
public struct Transcript {
    public struct Segment { public var at: TimeInterval; public var text: String }

    public var segments: [Segment]
    /// When the recording started, if known (from the file name or given explicitly).
    public var start: Date?

    /// Accepts "Speaker 1 (12:34)" / "Спикер 1 (1:02:03)" headers followed by text,
    /// and plain "[00:12:34] text" / "00:12:34 text" lines. UTF-8, UTF-16 or CP1251.
    public init?(url: URL, start: Date? = nil) {
        guard let text = [String.Encoding.utf8, .utf16, .windowsCP1251]
            .lazy.compactMap({ try? String(contentsOf: url, encoding: $0) }).first
        else { return nil }
        segments = Transcript.parse(text)
        self.start = start ?? Transcript.startFromName(url.lastPathComponent)
        if segments.isEmpty { return nil }
    }

    static func parse(_ s: String) -> [Segment] {
        let time = #"(\d{1,2}(?::\d{2}){1,2})"#
        let header = try! NSRegularExpression(pattern: #"^\s*\S[^()\[\]]{0,40}?\(\s*"# + time + #"\s*\)\s*:?\s*$"#)
        let inline = try! NSRegularExpression(pattern: #"^\s*\[?"# + time + #"\]?\s+(.+)$"#)
        var segs: [Segment] = []
        let seconds = { (t: Substring) in t.split(separator: ":").compactMap { Double($0) }.reduce(0) { $0 * 60 + $1 } }
        for raw in s.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let range = NSRange(line.startIndex..., in: line)
            if let m = header.firstMatch(in: line, range: range), let r = Range(m.range(at: 1), in: line) {
                segs.append(Segment(at: seconds(line[r]), text: ""))
            } else if let m = inline.firstMatch(in: line, range: range),
                      let r = Range(m.range(at: 1), in: line), let t = Range(m.range(at: 2), in: line) {
                segs.append(Segment(at: seconds(line[r]), text: String(line[t])))
            } else if !line.isEmpty, !segs.isEmpty {
                segs[segs.count - 1].text += (segs[segs.count - 1].text.isEmpty ? "" : " ") + line
            }
        }
        return segs.filter { !$0.text.isEmpty }
    }

    /// Voice recorders name files like "Voice 261015_162800" (yyMMdd_HHmmss)
    /// or "2026-10-15 16.28.00".
    static func startFromName(_ name: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for (pattern, format) in [(#"\d{6}_\d{6}"#, "yyMMdd_HHmmss"),
                                  (#"\d{8}_\d{6}"#, "yyyyMMdd_HHmmss"),
                                  (#"\d{4}-\d{2}-\d{2}[ _]\d{2}[.:-]\d{2}[.:-]\d{2}"#, "")] {
            guard let r = name.range(of: pattern, options: .regularExpression) else { continue }
            var s = String(name[r])
            if format.isEmpty {
                s = s.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: ":")
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                s = String(s.prefix(10)) + " " + s.dropFirst(11).replacingOccurrences(of: "-", with: ":")
            } else {
                f.dateFormat = format
            }
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// Speech per slide. With capture times: from 20 s before a photo until 20 s before
    /// the next one. Without (PDF): by shared words, slides only moving forward.
    func split(over slides: [Slide], dates: [Date?]) -> (parts: [[String]], byTime: Bool) {
        var parts = [[String]](repeating: [], count: slides.count)
        guard !slides.isEmpty else { return (parts, false) }
        if let start, !dates.contains(where: { $0 == nil }) {
            let lead: TimeInterval = 20
            for i in slides.indices {
                let from = i == 0 ? -.infinity : dates[i]!.timeIntervalSince(start) - lead
                let to = i + 1 < slides.count ? dates[i + 1]!.timeIntervalSince(start) - lead : .infinity
                parts[i] = segments.filter { $0.at >= from && $0.at < to }.map(\.text)
            }
            return (parts, true)
        }
        for (seg, i) in zip(segments, alignByText(slides)) { parts[i].append(seg.text) }
        return (parts, false)
    }

    func alignByText(_ slides: [Slide]) -> [Int] {
        let stems = { (s: String) -> Set<String> in
            Set(s.lowercased().components(separatedBy: CharacterSet.letters.inverted)
                .filter { $0.count >= 4 }.map { String($0.prefix(5)) })
        }
        let slideStems = slides.map { stems($0.text.joined(separator: " ")) }
        let n = slides.count, jump = 0.5
        var prev = (0..<n).map { $0 == 0 ? 0 : -jump }
        var back: [[Int]] = []
        for seg in segments {
            let w = stems(seg.text)
            var cur = [Double](repeating: 0, count: n), bk = [Int](repeating: 0, count: n)
            var best = -Double.infinity, arg = 0
            for i in 0..<n {
                if i > 0, prev[i - 1] > best { best = prev[i - 1]; arg = i - 1 }
                (cur[i], bk[i]) = prev[i] >= best - jump ? (prev[i], i) : (best - jump, arg)
                cur[i] += Double(w.intersection(slideStems[i]).count)
            }
            back.append(bk)
            prev = cur
        }
        var i = prev.indices.max { prev[$0] < prev[$1] } ?? 0
        var path = [Int](repeating: 0, count: segments.count)
        for j in stride(from: segments.count - 1, through: 0, by: -1) {
            path[j] = i
            i = back[j][i]
        }
        return path
    }
}
