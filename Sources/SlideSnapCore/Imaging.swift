import CoreImage
import Foundation
import Vision

/// Image steps: find the slide on a photo, undo the perspective, clean it up, read the text.
enum Imaging {
    /// The slide is a wide rectangle (at least 60 % of the frame width). When both the
    /// projector screen and the slide on it are found, the inner (smaller) one wins.
    /// Aspect limits are loose: a 16:9 slide shot from below looks even wider.
    static func detectSlide(_ img: CIImage) -> VNRectangleObservation? {
        let req = VNDetectRectanglesRequest()
        req.minimumAspectRatio = 0.3
        req.maximumAspectRatio = 0.9
        req.minimumSize = 0.3
        req.maximumObservations = 20
        req.minimumConfidence = 0.5
        req.quadratureTolerance = 30
        try? VNImageRequestHandler(ciImage: img).perform([req])
        let area = { (o: VNRectangleObservation) in o.boundingBox.width * o.boundingBox.height }
        return (req.results ?? [])
            .filter { $0.boundingBox.width >= 0.6 && area($0) < 0.95 }
            .min { area($0) < area($1) }
    }

    /// Vision finds the light body of the slide; the coloured header (with the title) and
    /// footer of a template stay outside. The quad is stretched along its sides by
    /// `padTop` / `padBottom` of its height, corrected, then forced to `aspect`.
    static func corrected(_ img: CIImage, _ o: VNRectangleObservation, _ opt: Options) -> CIImage {
        let w = img.extent.width, h = img.extent.height
        let px = { (n: CGPoint) in CGPoint(x: n.x * w, y: n.y * h) }
        let (tl, tr, bl, br) = (px(o.topLeft), px(o.topRight), px(o.bottomLeft), px(o.bottomRight))
        let clamp = { (p: CGPoint) in CGPoint(x: min(max(p.x, 0), w), y: min(max(p.y, 0), h)) }
        let ext = { (from: CGPoint, to: CGPoint, k: CGFloat) in
            clamp(CGPoint(x: to.x + (to.x - from.x) * k, y: to.y + (to.y - from.y) * k))
        }
        let f = CIFilter(name: "CIPerspectiveCorrection")!
        f.setValue(img, forKey: kCIInputImageKey)
        f.setValue(CIVector(cgPoint: ext(bl, tl, opt.padTop)), forKey: "inputTopLeft")
        f.setValue(CIVector(cgPoint: ext(br, tr, opt.padTop)), forKey: "inputTopRight")
        f.setValue(CIVector(cgPoint: ext(tl, bl, opt.padBottom)), forKey: "inputBottomLeft")
        f.setValue(CIVector(cgPoint: ext(tr, br, opt.padBottom)), forKey: "inputBottomRight")
        let out = f.outputImage!
        guard opt.aspect > 0 else { return out }
        let sy = out.extent.width / opt.aspect / out.extent.height
        return out.transformed(by: CGAffineTransform(scaleX: 1, y: sy))
    }

    static func enhanced(_ img: CIImage) -> CIImage {
        var out = img
        for f in img.autoAdjustmentFilters(options: [.redEye: false]) {
            f.setValue(out, forKey: kCIInputImageKey)
            out = f.outputImage ?? out
        }
        return out
    }

    static func scaled(_ img: CIImage, width: CGFloat) -> CIImage {
        let s = min(1, width / img.extent.width)
        let f = CIFilter(name: "CILanczosScaleTransform")!
        f.setValue(img, forKey: kCIInputImageKey)
        f.setValue(s, forKey: kCIInputScaleKey)
        f.setValue(1.0, forKey: kCIInputAspectRatioKey)
        return f.outputImage!
    }

    struct OCR { var title: String; var lines: [String]; var confidence: Float }

    static func recognize(_ img: CIImage, languages: [String], hasHeader: Bool) -> OCR {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = languages
        req.usesLanguageCorrection = true
        try? VNImageRequestHandler(ciImage: img).perform([req])
        let obs = (req.results ?? []).filter { ($0.topCandidates(1).first?.confidence ?? 0) > 0.3 }
        // Top to bottom; left to right within a line.
        let sorted = obs.sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.015
                ? $0.boundingBox.midY > $1.boundingBox.midY : $0.boundingBox.minX < $1.boundingBox.minX
        }
        let text = { (o: VNRecognizedTextObservation) in o.topCandidates(1).first?.string ?? "" }
        var lines = sorted.map(text)
        let conf = obs.isEmpty ? 0 : obs.map { $0.topCandidates(1).first?.confidence ?? 0 }.reduce(0, +) / Float(obs.count)
        // Title = lines in the header band (top 13 %). Light text on a dark header is
        // sometimes missed on the whole slide, so the band is read again, inverted.
        var top = sorted.filter { $0.boundingBox.minY > 0.87 }.map(text)
        if top.isEmpty, hasHeader {
            let e = img.extent
            let band = img.cropped(to: CGRect(x: e.minX, y: e.maxY - e.height * 0.13, width: e.width, height: e.height * 0.13))
                .applyingFilter("CIColorInvert")
            let hreq = VNRecognizeTextRequest()
            hreq.recognitionLevel = .accurate
            hreq.recognitionLanguages = Array(languages.prefix(1))  // short caps titles: Latin look-alikes otherwise
            try? VNImageRequestHandler(ciImage: band).perform([hreq])
            top = (hreq.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }.map(text)
            if !top.isEmpty { lines.insert(top.joined(separator: " "), at: 0) }
        }
        if languages.first?.hasPrefix("ru") == true || languages.first?.hasPrefix("uk") == true {
            lines = lines.map(cyrillicHomoglyphs)
            top = top.map(cyrillicHomoglyphs)
        }
        return OCR(title: (top.isEmpty ? Array(lines.prefix(1)) : top).joined(separator: " "),
                   lines: lines, confidence: conf)
    }

    /// All-caps words made only of letters shared by Latin and Cyrillic ("KOMA") are
    /// sometimes returned in Latin; for Cyrillic slides turn them back.
    static func cyrillicHomoglyphs(_ s: String) -> String {
        let map: [Character: Character] = ["A": "А", "B": "В", "C": "С", "E": "Е", "H": "Н", "K": "К",
                                           "M": "М", "O": "О", "P": "Р", "T": "Т", "X": "Х", "Y": "У"]
        return s.split(separator: " ", omittingEmptySubsequences: false).map { w -> String in
            let letters = w.filter(\.isLetter)
            guard letters.count >= 3, letters.allSatisfy({ map[$0] != nil }) else { return String(w) }
            return String(w.map { map[$0] ?? $0 })
        }.joined(separator: " ")
    }

    static func words(_ lines: [String]) -> Set<String> {
        Set(lines.joined(separator: " ").lowercased()
            .components(separatedBy: CharacterSet.letters.inverted).filter { $0.count > 2 })
    }
}
