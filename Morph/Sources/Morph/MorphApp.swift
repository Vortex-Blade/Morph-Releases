import SwiftUI
import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Carbon

@main struct MorphApp: App {
    @StateObject private var store = MorphStore()
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(MorphDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup(id: "main") { MorphView().environmentObject(store).frame(minWidth: 980, minHeight: 650).preferredColorScheme(.dark)
                .onAppear {
                    appDelegate.quick.attach(store: store)
                    appDelegate.reopenMainWindow = { openWindow(id: "main") }
                } }
            .windowStyle(.hiddenTitleBar)
    }
}

enum Kind: String { case image = "Afbeelding", media = "Video & Audio", document = "Document", pdf = "PDF", archive = "Archief", other = "Overig" }
struct Job: Identifiable {
    let id = UUID()
    let url: URL
    let kind: Kind
    var target: String
    var status = "Wacht op conversie"
    var output: URL? = nil
}

enum Engine {
    static let imageTypes = ["jpg", "png", "tiff", "gif", "heic", "webp", "bmp"]
    static let mediaTypes = ["mp4", "mov", "mkv", "webm", "avi", "mp3", "wav", "flac", "m4a", "aac", "ogg"]
    static let documentTypes = ["docx", "doc", "odt", "rtf", "txt", "pptx", "ppt", "xlsx", "xls", "csv"]
    static func kind(_ url: URL) -> Kind {
        let ext = url.pathExtension.lowercased()
        if imageTypes.contains(ext) { return .image }
        if mediaTypes.contains(ext) { return .media }
        if ext == "pdf" { return .pdf }
        if documentTypes.contains(ext) { return .document }
        if ["zip", "tar", "7z"].contains(ext) { return .archive }
        return .other
    }
    static func targets(for kind: Kind) -> [String] {
        switch kind {
        case .image: return ["jpg", "png", "tiff", "gif", "heic"]
        case .media: return ["mp4", "mov", "mkv", "webm", "mp3", "wav", "flac", "m4a"]
        case .document: return ["pdf", "docx", "odt", "txt", "html"]
        case .pdf: return ["png", "jpg"]
        case .archive: return ["zip"]
        case .other: return []
        }
    }
    static func destination(_ source: URL, ext: String) -> URL {
        let parent = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent + "_morph"
        var result = parent.appendingPathComponent(base).appendingPathExtension(ext)
        var i = 2
        while FileManager.default.fileExists(atPath: result.path) {
            result = parent.appendingPathComponent("\(base)_\(i)").appendingPathExtension(ext)
            i += 1
        }
        return result
    }
    static func tool(_ name: String) -> String? {
        let appContents = Bundle.main.bundleURL.appendingPathComponent("Contents")
        let bundled: URL = name == "soffice"
            ? appContents.appendingPathComponent("Helpers/LibreOffice.app/Contents/MacOS/soffice")
            : appContents.appendingPathComponent("Helpers/\(name)")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled.path }
        // Development fallback; distributed builds should bundle all tools.
        let candidates = name == "soffice"
            ? ["/Applications/LibreOffice.app/Contents/MacOS/soffice"]
            : ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }
    static func process(_ executable: String, _ args: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = args
        let stderr = Pipe(); p.standardError = stderr
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Onbekende fout"
            throw MorphError.message(String(message.suffix(400)))
        }
    }
    static func image(_ source: URL, _ output: URL, quality: Double) throws {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil), let frame = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw MorphError.message("Afbeelding kan niet worden gelezen") }
        let utis: [String: String] = ["jpg":"public.jpeg", "png":"public.png", "tiff":"public.tiff", "gif":"com.compuserve.gif", "heic":"public.heic"]
        guard let uti = utis[output.pathExtension], let dest = CGImageDestinationCreateWithURL(output as CFURL, uti as CFString, 1, nil) else { throw MorphError.message("Uitvoerformaat niet ondersteund") }
        CGImageDestinationAddImage(dest, frame, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw MorphError.message("Opslaan mislukt") }
    }
    static func convert(_ job: Job, quality: Double) throws -> URL {
        let out = destination(job.url, ext: job.target)
        switch job.kind {
        case .image:
            try image(job.url, out, quality: quality)
        case .media:
            guard let ffmpeg = tool("ffmpeg") else { throw MorphError.message("FFmpeg ontbreekt in deze Morph-build. Bouw met ./build-all-in-one.sh") }
            try process(ffmpeg, ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", job.url.path, "-y", out.path])
        case .document:
            guard let soffice = tool("soffice") else { throw MorphError.message("LibreOffice ontbreekt in deze Morph-build. Bouw met ./build-all-in-one.sh") }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try process(soffice, ["--headless", "--convert-to", job.target, "--outdir", temporary.path, job.url.path])
            let generated = temporary.appendingPathComponent(job.url.deletingPathExtension().lastPathComponent).appendingPathExtension(job.target)
            guard FileManager.default.fileExists(atPath: generated.path) else { throw MorphError.message("LibreOffice kon dit formaat niet converteren") }
            try FileManager.default.moveItem(at: generated, to: out)
        case .pdf:
            guard let pdf = PDFDocument(url: job.url), let first = pdf.page(at: 0) else { throw MorphError.message("PDF kan niet worden geopend") }
            let image = first.thumbnail(of: CGSize(width: 1800, height: 2400), for: .mediaBox)
            guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let cg = bitmap.cgImage else { throw MorphError.message("PDF renderen mislukt") }
            guard let destination = CGImageDestinationCreateWithURL(out as CFURL, (job.target == "jpg" ? "public.jpeg" : "public.png") as CFString, 1, nil) else { throw MorphError.message("Bestand maken mislukt") }
            CGImageDestinationAddImage(destination, cg, nil)
            guard CGImageDestinationFinalize(destination) else { throw MorphError.message("Opslaan mislukt") }
        case .archive:
            guard let ditto = tool("ditto") else { throw MorphError.message("ditto ontbreekt") }
            guard job.target == "zip" else { throw MorphError.message("TAR-uitvoer is nog niet ondersteund") }
            try process(ditto, ["-c", "-k", "--sequesterRsrc", "--keepParent", job.url.path, out.path])
        case .other: throw MorphError.message("Bestandstype nog niet ondersteund")
        }
        return out
    }
    // Split a PDF into individual one-page PDF files, preserving the original.
    static func splitPDF(_ source: URL) throws -> [URL] {
        guard let document = PDFDocument(url: source), document.pageCount > 0 else {
            throw MorphError.message("PDF kan niet worden geopend of bevat geen pagina's")
        }
        var created: [URL] = []
        do {
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else {
                    throw MorphError.message("Pagina \(index + 1) kan niet worden gelezen")
                }
                let part = PDFDocument()
                part.insert(page, at: 0)
                let folder = source.deletingLastPathComponent()
                let name = source.deletingPathExtension().lastPathComponent
                let base = folder.appendingPathComponent("\(name)_pagina_\(index + 1).pdf")
                var output = base
                var counter = 2
                while FileManager.default.fileExists(atPath: output.path) {
                    output = folder.appendingPathComponent("\(name)_pagina_\(index + 1)_\(counter).pdf")
                    counter += 1
                }
                guard part.write(to: output) else {
                    throw MorphError.message("Pagina \(index + 1) opslaan mislukt")
                }
                created.append(output)
            }
        } catch {
            // Avoid leaving a partial split if an error occurs.
            for url in created { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        return created
    }

    static func rotatePDF(_ source: URL) throws -> URL {
        guard let pdf = PDFDocument(url: source), pdf.pageCount > 0 else { throw MorphError.message("PDF kan niet worden geopend") }
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            page.rotation = (page.rotation + 90) % 360
        }
        let out = destination(source, ext: "pdf")
        guard pdf.write(to: out) else { throw MorphError.message("Roteren mislukt") }
        return out
    }
    static func removePDFPage(_ source: URL, pageNumber: Int) throws -> URL {
        guard let pdf = PDFDocument(url: source), pdf.pageCount > 1 else { throw MorphError.message("PDF moet minimaal twee pagina's bevatten") }
        guard pageNumber >= 1 && pageNumber <= pdf.pageCount else { throw MorphError.message("Ongeldig paginanummer") }
        pdf.removePage(at: pageNumber - 1)
        let out = destination(source, ext: "pdf")
        guard pdf.write(to: out) else { throw MorphError.message("Opslaan mislukt") }
        return out
    }
    static func stripMetadata(_ source: URL) throws -> URL {
        guard kind(source) == .image else { throw MorphError.message("Metadata verwijderen ondersteunt momenteel alleen stilstaande afbeeldingen") }
        let ext = source.pathExtension.lowercased()
        let supported = ["jpg", "png", "tiff", "heic", "gif"]
        guard supported.contains(ext) else { throw MorphError.message("Dit afbeeldingsformaat wordt niet ondersteund") }
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(input) == 1,
              let frame = CGImageSourceCreateImageAtIndex(input, 0, nil),
              let type = CGImageSourceGetType(input) else { throw MorphError.message("Alleen stilstaande, leesbare afbeeldingen worden ondersteund") }
        let out = destination(source, ext: ext)
        guard let writer = CGImageDestinationCreateWithURL(out as CFURL, type, 1, nil) else { throw MorphError.message("Formaat kan niet worden opgeslagen") }
        CGImageDestinationAddImage(writer, frame, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw MorphError.message("Metadata verwijderen mislukt") }
        return out
    }
    static func trimVideo(_ source: URL, start: Double, duration: Double) throws -> URL {
        guard start >= 0 && duration > 0 else { throw MorphError.message("Gebruik een positieve starttijd en duur") }
        guard ["mp4", "mov", "mkv", "webm", "avi"].contains(source.pathExtension.lowercased()) else { throw MorphError.message("Selecteer een videobestand") }
        guard let ffmpeg = tool("ffmpeg") else { throw MorphError.message("FFmpeg ontbreekt in deze Morph-build.") }
        let out = destination(source, ext: "mp4")
        do {
            try process(ffmpeg, ["-nostdin", "-hide_banner", "-loglevel", "error", "-ss", String(start), "-i", source.path, "-t", String(duration), "-c:v", "libx264", "-crf", "21", "-preset", "medium", "-c:a", "aac", "-movflags", "+faststart", "-n", out.path])
            return out
        } catch { try? FileManager.default.removeItem(at: out); throw error }
    }
    static func extractZIP(_ source: URL) throws -> URL {
        guard source.pathExtension.lowercased() == "zip" else { throw MorphError.message("Uitpakken ondersteunt momenteel ZIP") }
        guard let ditto = tool("ditto") else { throw MorphError.message("ditto ontbreekt") }
        let parent = source.deletingLastPathComponent()
        var folder = parent.appendingPathComponent(source.deletingPathExtension().lastPathComponent + "_uitgepakt")
        var i = 2
        while FileManager.default.fileExists(atPath: folder.path) { folder = parent.appendingPathComponent(source.deletingPathExtension().lastPathComponent + "_uitgepakt_\(i)"); i += 1 }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do { try process(ditto, ["-x", "-k", source.path, folder.path]); return folder }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
    }

    static func mergePDF(_ urls: [URL]) throws -> URL {
        guard urls.count >= 2, let first = urls.first else { throw MorphError.message("Selecteer minimaal twee PDF's") }
        let merged = PDFDocument()
        for url in urls {
            guard let pdf = PDFDocument(url: url) else { throw MorphError.message("PDF niet leesbaar: \(url.lastPathComponent)") }
            for index in 0..<pdf.pageCount { if let page = pdf.page(at: index) { merged.insert(page, at: merged.pageCount) } }
        }
        let out = destination(first, ext: "pdf")
        guard merged.write(to: out) else { throw MorphError.message("Samenvoegen mislukt") }
        return out
    }
}
enum MorphError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let text) = self { return text }; return nil } }

@MainActor final class MorphStore: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var section = "Home"
    @Published var quality = 0.9
    @Published var running = false
    @Published var notification = ""
    @Published var history: [URL] = [] {
        didSet { UserDefaults.standard.set(Array(history.prefix(300)).map(\.path), forKey: "morph.history") }
    }
    init() {
        history = (UserDefaults.standard.stringArray(forKey: "morph.history") ?? []).map { URL(fileURLWithPath: $0) }
    }
    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            let kind = Engine.kind(url)
            if let first = Engine.targets(for: kind).first { jobs.append(Job(url: url, kind: kind, target: first)) }
            else { notification = "Niet ondersteund: \(url.lastPathComponent)" }
        }
    }
    func convert() {
        guard !running else { return }
        running = true
        Task {
            for i in jobs.indices where jobs[i].output == nil {
                jobs[i].status = "Converteren..."
                let job = jobs[i]; let q = quality
                let result = await Task.detached { Result { try Engine.convert(job, quality: q) } }.value
                switch result {
                case .success(let url): jobs[i].output = url; jobs[i].status = "Voltooid"; history.insert(url, at: 0)
                case .failure(let error): jobs[i].status = "Fout: \(error.localizedDescription)"
                }
            }
            running = false
        }
    }
    func split() {
        guard !running else { return }
        let pdfs = jobs.filter { $0.kind == .pdf }.map(\.url)
        guard !pdfs.isEmpty else {
            notification = "Voeg eerst minimaal één PDF toe."
            return
        }
        running = true
        notification = "PDF's splitsen..."
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try pdfs.flatMap { try Engine.splitPDF($0) } }
            }.value
            switch result {
            case .success(let urls):
                history.insert(contentsOf: urls, at: 0)
                notification = "Klaar! \(urls.count) losse PDF-pagina's opgeslagen naast de originele bestanden."
                if let first = urls.first { NSWorkspace.shared.activateFileViewerSelecting([first]) }
            case .failure(let error):
                notification = "Splitsen mislukt: \(error.localizedDescription)"
            }
            running = false
        }
    }
    func runTool(_ action: String, page: Int = 1, start: Double = 0, duration: Double = 10) {
        guard !running else { return }
        let sources = jobs.map(\.url).filter { url in
            switch action {
            case "metadata": return Engine.kind(url) == .image
            case "rotate", "remove": return Engine.kind(url) == .pdf
            case "trim": return ["mp4", "mov", "mkv", "webm", "avi"].contains(url.pathExtension.lowercased())
            case "extract": return url.pathExtension.lowercased() == "zip"
            default: return false
            }
        }
        guard !sources.isEmpty else { notification = "Voeg eerst geschikte bestanden toe."; return }
        running = true
        notification = "Bezig met verwerken..."
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[URL], Error> in
                Result {
                    try sources.map { url in
                        switch action {
                        case "metadata": return try Engine.stripMetadata(url)
                        case "rotate": return try Engine.rotatePDF(url)
                        case "remove": return try Engine.removePDFPage(url, pageNumber: page)
                        case "trim": return try Engine.trimVideo(url, start: start, duration: duration)
                        case "extract": return try Engine.extractZIP(url)
                        default: throw MorphError.message("Onbekende actie")
                        }
                    }
                }
            }.value
            switch result {
            case .success(let outputs):
                history.insert(contentsOf: outputs, at: 0)
                notification = "Klaar: \(outputs.count) bestand(en) verwerkt."
                if let first = outputs.first { NSWorkspace.shared.activateFileViewerSelecting([first]) }
            case .failure(let error): notification = "Fout: \(error.localizedDescription)"
            }
            running = false
        }
    }
    func merge() {
        let urls = jobs.filter { $0.kind == .pdf }.map(\.url)
        do { let out = try Engine.mergePDF(urls); history.insert(out, at: 0); notification = "Samengevoegd: \(out.lastPathComponent)" }
        catch { notification = error.localizedDescription }
    }
}

struct MorphView: View {
    @EnvironmentObject var store: MorphStore
    @StateObject private var updates = MorphUpdateChecker()
    @State private var importer = false
    @State private var hovering = false
    @State private var pageToRemove = 1
    @State private var trimStart = 0.0
    @State private var trimDuration = 10.0
    private let accent = Color(red: 0.63, green: 0.39, blue: 1)
    private let sections = ["Home", "Converteren", "Afbeeldingen", "Video & Audio", "Documenten", "PDF-tools", "Compressie", "Archieven", "Metadata verwijderen", "Geschiedenis", "Instellingen"]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "m.circle.fill").font(.system(size: 38)).foregroundStyle(accent)
                    VStack(alignment: .leading) { Text("Morph").font(.title2.bold()); Text("Transform Anything.").font(.caption).foregroundStyle(.secondary) }
                }.padding(.bottom, 25)
                ForEach(sections, id: \.self) { name in
                    Button { store.section = name } label: {
                        HStack { Image(systemName: symbol(name)).frame(width: 24); Text(name); Spacer() }
                            .padding(11)
                            .background(store.section == name ? accent.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button("Controleer updates") { Task { await updates.check() } }
                    .buttonStyle(.bordered).font(.caption)
                    .alert("Morph-updates", isPresented: $updates.showAlert) {
                        if let url = updates.releaseURL {
                            Button("Open GitHub-release") { NSWorkspace.shared.open(url) }
                        }
                        Button("Sluiten", role: .cancel) { }
                    } message: { Text(updates.message) }
                Label("100% lokale verwerking", systemImage: "checkmark.shield.fill").font(.caption).foregroundStyle(.green)
            }
            .padding(20).frame(width: 245)
            .background(Color(red: 0.07, green: 0.06, blue: 0.12))
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.section == "Home" ? "Morph Studio" : store.section).font(.system(size: 32, weight: .bold))
                            Text("Slimme bestandstools, helemaal offline.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("Offline", systemImage: "circle.fill").foregroundStyle(.green).font(.caption)
                    }
                    if store.section == "Compressie" { CompressionView() }
                    else if store.section == "Geschiedenis" { historyPanel }
                    else if store.section == "Instellingen" { settingsPanel }
                    else {
                        dropPanel
                        if store.section == "PDF-tools" {
                            HStack(spacing: 12) {
                                Button("Geselecteerde PDF's samenvoegen") { store.merge() }
                                    .buttonStyle(.borderedProminent).tint(accent)
                                    .disabled(store.running || store.jobs.filter { $0.kind == .pdf }.count < 2)
                                Button { store.split() } label: {
                                    Label("PDF splitsen per pagina", systemImage: "square.on.square")
                                }
                                .buttonStyle(.borderedProminent).tint(accent)
                                .disabled(store.running || !store.jobs.contains(where: { $0.kind == .pdf }))
                                Button("Roteer PDF's 90°") { store.runTool("rotate") }
                                    .disabled(store.running)
                            }
                            HStack {
                                Stepper("Verwijder pagina \(pageToRemove)", value: $pageToRemove, in: 1...9999)
                                Button("Pagina verwijderen") { store.runTool("remove", page: pageToRemove) }
                                    .disabled(store.running)
                            }
                            Text("Splitsen maakt voor iedere pagina een aparte PDF naast het origineel. Het oorspronkelijke bestand blijft behouden.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("PDF naar afbeelding converteert momenteel alleen de eerste pagina.").font(.caption).foregroundStyle(.secondary)
                        }
                        if store.section == "Metadata verwijderen" {
                            Text("Verwijder EXIF, GPS en andere ingesloten metadata uit stilstaande afbeeldingen. Nieuwe kopie, origineel blijft behouden.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Metadata verwijderen") { store.runTool("metadata") }
                                .buttonStyle(.borderedProminent).tint(accent).disabled(store.running)
                        }
                        if store.section == "Archieven" {
                            Text("ZIP-bestanden uitpakken in een nieuwe map. ZIP maken kan via de converter.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("ZIP uitpakken") { store.runTool("extract") }
                                .buttonStyle(.borderedProminent).tint(accent).disabled(store.running)
                        }
                        if store.section == "Video & Audio" {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Video inkorten").font(.headline)
                                    HStack {
                                        Text("Start (sec)")
                                        TextField("Start", value: $trimStart, format: .number).frame(width: 75)
                                        Text("Duur (sec)")
                                        TextField("Duur", value: $trimDuration, format: .number).frame(width: 75)
                                    }
                                }
                                Spacer()
                                Button("Video inkorten") { store.runTool("trim", start: trimStart, duration: trimDuration) }
                                    .buttonStyle(.borderedProminent).tint(accent).disabled(store.running)
                            }
                        }
                        HStack {
                            Text("Bestanden in wachtrij").font(.title2.bold())
                            Text("\(store.jobs.count)").foregroundStyle(.secondary)
                            Spacer()
                            Button("Toevoegen") { importer = true }
                            Button("Wissen") { store.jobs.removeAll() }.disabled(store.running)
                        }
                        if store.jobs.isEmpty {
                            Text("Nog geen bestanden toegevoegd.").foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 90)
                                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                        }
                        ForEach($store.jobs) { $job in
                            HStack(spacing: 12) {
                                Image(systemName: symbolForKind(job.kind)).font(.title2).foregroundStyle(accent).frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(job.url.lastPathComponent).lineLimit(1)
                                    Text(job.status).font(.caption).foregroundColor(job.output == nil ? Color.secondary : Color.green).lineLimit(2)
                                }
                                Spacer(minLength: 8)
                                Text(job.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                                Picker("Uitvoer", selection: $job.target) {
                                    ForEach(Engine.targets(for: job.kind), id: \.self) { format in Text(format.uppercased()).tag(format) }
                                }.labelsHidden().frame(width: 105).disabled(store.running || job.output != nil)
                                if let out = job.output {
                                    Button { NSWorkspace.shared.activateFileViewerSelecting([out]) } label: { Image(systemName: "folder") }.help("Toon in Finder")
                                }
                            }
                            .padding(13).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
                        }
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Kwaliteit (afbeeldingen)").font(.headline)
                                Slider(value: $store.quality, in: 0.2...1).tint(accent)
                            }.frame(maxWidth: 280)
                            Spacer()
                            Button { store.convert() } label: {
                                Label(store.running ? "Bezig..." : "Converteren", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.headline).padding(11)
                            }.buttonStyle(.borderedProminent).tint(accent).disabled(store.jobs.isEmpty || store.running)
                        }
                    }
                    if !store.notification.isEmpty { Text(store.notification).font(.callout).foregroundStyle(.orange) }
                    Text("Morph v0.6 · Offline tools · Morph Quick · PDF · compressie · metadata · video · ZIP.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(30)
            }.background(Color(red: 0.045, green: 0.045, blue: 0.09))
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { store.add(urls) }
        }
        .onDrop(of: [.fileURL], isTargeted: $hovering) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url { DispatchQueue.main.async { store.add([url]) } }
                }
            }
            return true
        }
    }
    private var dropPanel: some View {
        Button { importer = true } label: {
            VStack(spacing: 14) {
                Image(systemName: "folder.badge.plus").font(.system(size: 58, weight: .ultraLight)).foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.8), radius: 18)
                Text("Sleep bestanden hiernaartoe").font(.title2.bold())
                Text("of klik om bestanden te kiezen").foregroundStyle(.secondary)
                Text("Afbeeldingen · Video · Audio · Documenten · PDF")
                    .font(.caption).foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, minHeight: 225)
            .background(accent.opacity(hovering ? 0.2 : 0.07), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(accent.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [7, 5])))
        }.buttonStyle(.plain)
    }
    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.history.isEmpty { Text("Nog geen opgeslagen conversies.").foregroundStyle(.secondary) }
            ForEach(store.history, id: \.self) { url in
                HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(url.lastPathComponent); Spacer()
                    Button("Toon in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }.padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Afbeeldingskwaliteit").font(.headline)
            Slider(value: $store.quality, in: 0.2...1).tint(accent)
            Text("\(Int(store.quality * 100))%").foregroundStyle(.secondary)
            Text("Bestanden worden naast het origineel opgeslagen met _morph in de naam.")
            Text("Video en audio vereisen FFmpeg; documentconversie vereist LibreOffice.")
            Text("Er worden geen bestanden geüpload.")
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }
    private func symbolForKind(_ kind: Kind) -> String {
        switch kind { case .image: return "photo"; case .media: return "play.rectangle"; case .document: return "doc.text"; case .pdf: return "doc.richtext"; case .archive: return "archivebox"; case .other: return "questionmark.square" }
    }
    private func symbol(_ name: String) -> String {
        switch name {
        case "Home": return "house"
        case "Converteren": return "arrow.triangle.2.circlepath"
        case "Afbeeldingen": return "photo"
        case "Video & Audio": return "play.rectangle"
        case "Documenten": return "doc.text"
        case "PDF-tools": return "doc.richtext"
        case "Compressie": return "archivebox"
        case "Archieven": return "shippingbox"
        case "Metadata verwijderen": return "hand.raised"
        case "Geschiedenis": return "clock.arrow.circlepath"
        default: return "gearshape"
        }
    }
}


// GitHub Releases check: never silently installs unsigned software.
// Replace repository if you publish releases under a different name.
@MainActor final class MorphUpdateChecker: ObservableObject {
    @Published var showAlert = false
    @Published var message = ""
    var releaseURL: URL?
    private let endpoint = URL(string: "https://api.github.com/repos/Vortex-Blade/Morph-Releases/releases/latest")!

    func check() async {
        releaseURL = nil
        do {
            var request = URLRequest(url: endpoint)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 404 {
                message = "Er is nog geen publieke Morph-release gepubliceerd op GitHub."
            } else if http.statusCode != 200 {
                message = "Updatecontrole mislukt (HTTP \(http.statusCode))."
            } else {
                struct Release: Decodable { let tag_name: String; let html_url: String }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
                let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if latest.compare(current, options: .numeric) == .orderedDescending {
                    message = "Morph \(latest) is beschikbaar (huidig: \(current)). Open de release om de update te downloaden."
                    releaseURL = URL(string: release.html_url)
                } else {
                    message = "Je gebruikt de nieuwste versie van Morph (\(current))."
                }
            }
        } catch {
            message = "Kon GitHub niet bereiken: \(error.localizedDescription)"
        }
        showAlert = true
    }
}
