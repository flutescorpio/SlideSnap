import CoreImage
import Foundation
import ImageIO

/// One page to process: a photo, or a page of a PDF made of photos.
public struct InputPage {
    public var name: String
    public var date: Date?
    var load: () -> CIImage?
}

public enum Inputs {
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff"]

    /// Folders are expanded, PDFs split into pages, images taken as is.
    /// Photos are ordered by capture time (EXIF), then by name; PDF pages keep their order.
    public static func pages(from urls: [URL]) -> [InputPage] {
        var photos: [URL] = []
        var pdfPages: [InputPage] = []
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                photos += items.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            } else if url.pathExtension.lowercased() == "pdf" {
                pdfPages += pdf(url)
            } else if imageExtensions.contains(url.pathExtension.lowercased()) {
                photos.append(url)
            }
        }
        let dated: [(URL, Date?)] = photos.map { (u: URL) -> (URL, Date?) in (u, shotDate(u)) }
        let sorted = dated.sorted { (a: (URL, Date?), b: (URL, Date?)) -> Bool in
            let (da, db) = (a.1 ?? .distantPast, b.1 ?? .distantPast)
            return da == db ? a.0.lastPathComponent < b.0.lastPathComponent : da < db
        }
        let photoPages = sorted.map { (u, d) in
            InputPage(name: u.lastPathComponent, date: d) { CIImage(contentsOf: u, options: [.applyOrientationProperty: true]) }
        }
        return photoPages + pdfPages
    }

    static func shotDate(_ url: URL) -> Date? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.date(from: s)
    }

    /// Each page rendered with its long side at 4000 px. A PDF has no capture time,
    /// so a transcript is matched to its slides by text.
    static func pdf(_ url: URL) -> [InputPage] {
        guard let doc = CGPDFDocument(url as CFURL), doc.numberOfPages > 0 else { return [] }
        let base = url.deletingPathExtension().lastPathComponent
        return (1...doc.numberOfPages).map { n in
            InputPage(name: "\(base) p.\(n)", date: nil) {
                guard let page = doc.page(at: n) else { return nil }
                let box = page.getBoxRect(.mediaBox)
                let k = 4000 / max(box.width, box.height)
                let (w, h) = (Int(box.width * k), Int(box.height * k))
                guard let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
                cg.setFillColor(gray: 1, alpha: 1)
                cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
                cg.scaleBy(x: k, y: k)
                cg.translateBy(x: -box.minX, y: -box.minY)
                cg.drawPDFPage(page)
                return cg.makeImage().map { CIImage(cgImage: $0) }
            }
        }
    }
}
