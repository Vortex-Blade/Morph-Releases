import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

private enum CompressionError: LocalizedError {
    case unsupported, image, encoder, missingFFmpeg, missingQPDF, noReduction
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Alleen JPG, PNG, HEIC, TIFF, WEBP, MP4, MOV, MKV en PDF worden ondersteund."
        case .image: return "Afbeelding kon niet worden gelezen."
        case .encoder: return "Afbeelding kon niet worden opgeslagen."
        case .missingFFmpeg: return "FFmpeg ontbreekt in deze Morph-build."
        case .missingQPDF: return "qpdf ontbreekt in deze Morph-build."
        case .noReduction: return "Het resultaat was niet kleiner; het origineel is behouden."
        }
    }
}

private struct CompressionItem: Identifiable {
    let id = UUID()
    let url: URL
    var status = "Klaar om te comprimeren"
    var output: URL?
}

private enum CompressionEngine {
    static func compress(_ input: URL, quality: Double) throws -> URL {
        let ext = input.pathExtension.lowercased()
        let fileManager = FileManager.default
        let targetExt = ["png", "tif", "tiff", "heic", "webp"].contains(ext) ? "jpg" : ext
        let output = Engine.destination(input, ext: targetExt)
        do {
            switch ext {
            case "jpg", "jpeg", "png", "tif", "tiff", "heic", "webp":
                try compressImage(input, output, quality: quality)
            case "mp4", "mov", "mkv":
                guard let ffmpeg = Engine.tool("ffmpeg") else { throw CompressionError.missingFFmpeg }
                let crf = Int(18 + (1 - quality) * 18)
                try Engine.process(ffmpeg, ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", input.path,
                    "-map", "0:v:0", "-map", "0:a?", "-c:v", "libx264", "-preset", "medium", "-crf", String(crf),
                    "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", "-y", output.path])
            case "pdf":
                guard let qpdf = Engine.tool("qpdf") else { throw CompressionError.missingQPDF }
                try Engine.process(qpdf, ["--object-streams=generate", "--stream-data=compress", input.path, output.path])
            default: throw CompressionError.unsupported
            }
            let originalBytes = (try fileManager.attributesOfItem(atPath: input.path)[.size] as? NSNumber)?.int64Value ?? 0
            let resultBytes = (try fileManager.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard resultBytes > 0, resultBytes < originalBytes else { throw CompressionError.noReduction }
            return output
        } catch {
            try? fileManager.removeItem(at: output)
            throw error
        }
    }

    private static func compressImage(_ input: URL, _ output: URL, quality: Double) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { throw CompressionError.image }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let longest = max(width, height)
        guard longest > 0 else { throw CompressionError.image }
        let maxPixel = quality < 0.5 ? 1600 : quality < 0.75 ? 2560 : longest
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: min(longest, maxPixel)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.jpeg" as CFString, 1, nil) else { throw CompressionError.encoder }
        // JPEG is opaque: transparency is flattened to white rather than black.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CompressionError.encoder }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flattened = context.makeImage() else { throw CompressionError.encoder }
        CGImageDestinationAddImage(destination, flattened,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CompressionError.encoder }
    }
}

@MainActor private final class CompressionStore: ObservableObject {
    @Published var items: [CompressionItem] = []
    @Published var quality: Double = 0.70
    @Published var running = false
    @Published var notice = ""

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            if !items.contains(where: { $0.url == url }) { items.append(CompressionItem(url: url)) }
        }
    }
    func run() {
        guard !running else { return }
        running = true
        notice = ""
        Task {
            for index in items.indices where items[index].output == nil {
                items[index].status = "Comprimeren..."
                let input = items[index].url
                let quality = quality
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try CompressionEngine.compress(input, quality: quality) }
                }.value
                switch result {
                case .success(let url):
                    items[index].output = url
                    let original = ((try? FileManager.default.attributesOfItem(atPath: input.path)[.size]) as? NSNumber)?.doubleValue ?? 0
                    let compressed = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.doubleValue ?? 0
                    let percent = original > 0 ? Int((1 - compressed / original) * 100) : 0
                    items[index].status = "Klaar · \(percent)% kleiner"
                case .failure(let error):
                    items[index].status = "Niet gecomprimeerd: \(error.localizedDescription)"
                }
            }
            running = false
        }
    }
}

struct CompressionView: View {
    @StateObject private var model = CompressionStore()
    @State private var importer = false
    @State private var hovering = false
    private let accent = Color(red: 0.63, green: 0.39, blue: 1)
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Verklein je bestanden zonder ze te uploaden.")
                .font(.headline).foregroundStyle(.secondary)
            Button { importer = true } label: {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 45)).foregroundStyle(accent)
                    Text("Sleep bestanden hiernaartoe").font(.title2.bold())
                    Text("of klik om bestanden te kiezen").foregroundStyle(.secondary)
                    Text("JPG · PNG · HEIC · TIFF · WEBP · MP4 · MOV · MKV · PDF")
                        .font(.caption).foregroundStyle(accent)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(accent.opacity(hovering ? 0.20 : 0.08), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(accent.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [7, 5])))
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Kwaliteit").font(.headline)
                    Spacer()
                    Text("\(Int(model.quality * 100))%").foregroundStyle(accent)
                }
                Slider(value: $model.quality, in: 0.3...0.95).tint(accent)
                Text("Lager = kleinere bestanden, maar mogelijk zichtbaar kwaliteitsverlies. Afbeeldingen worden als JPG opgeslagen. PDF behoudt tekst en pagina's; besparing kan beperkt zijn.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            HStack {
                Text("Bestanden (\(model.items.count))").font(.title3.bold())
                Spacer()
                Button("Toevoegen") { importer = true }
                Button("Wissen") { model.items.removeAll() }.disabled(model.running)
            }
            ForEach(model.items) { item in
                HStack(spacing: 12) {
                    Image(systemName: "doc.zipper").foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.url.lastPathComponent).lineLimit(1)
                        Text(item.status).font(.caption).foregroundStyle(item.output == nil ? Color.secondary : Color.green)
                    }
                    Spacer()
                    if let output = item.output {
                        Button("Toon in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                    }
                }.padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Text("Het origineel wordt nooit overschreven.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.run() } label: {
                    Label(model.running ? "Bezig..." : "Comprimeren", systemImage: "archivebox.fill")
                        .padding(8)
                }.buttonStyle(.borderedProminent).tint(accent).disabled(model.running || model.items.isEmpty)
            }
            Text("Video- en PDF-tools worden meegeleverd in de All-in-One-build.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.add(urls) }
        }
        .onDrop(of: [.fileURL], isTargeted: $hovering) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { model.add([url]) } }
                }
            }
            return true
        }
    }
}
