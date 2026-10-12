import SwiftUI
import SwiftData
import PhotosUI
import VisionKit
import UniformTypeIdentifiers
import QuickLook

/// En fil som hører til en kunde eller en avtale, f.eks. en signert kontrakt.
@Model
final class Dokument {
    var uuid: UUID = UUID()
    var navn: String = ""
    /// Filendelsen, f.eks. «pdf», «jpg» eller «docx».
    var filtype: String = "pdf"
    var opprettet: Date = Date.now
    @Attribute(.externalStorage) var data: Data? = nil
    var kunde: Kunde?
    var avtale: Avtale?

    init(navn: String, filtype: String, data: Data) {
        self.navn = navn
        self.filtype = filtype
        self.data = data
    }

    var ikon: String {
        switch filtype.lowercased() {
        case "pdf": "doc.richtext"
        case "jpg", "jpeg", "png", "heic": "photo"
        default: "doc"
        }
    }

    /// Lagrer filen midlertidig, så den kan vises og deles.
    func midlertidigFil() -> URL? {
        guard let data else { return nil }
        let trygtNavn = navn.trimmet.isEmpty ? "Dokument" : navn.replacingOccurrences(of: "/", with: "-")
        let mappe = FileManager.default.temporaryDirectory.appendingPathComponent(uuid.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: mappe, withIntermediateDirectories: true)
        let url = mappe.appendingPathComponent(trygtNavn).appendingPathExtension(filtype)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

enum Dokumenter {
    /// Skannede sider samlet til én PDF.
    static func pdf(av sider: [UIImage]) -> Data {
        let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: a4).pdfData { ctx in
            for side in sider {
                ctx.beginPage()
                let skala = min(a4.width / side.size.width, a4.height / side.size.height)
                let str = CGSize(width: side.size.width * skala, height: side.size.height * skala)
                side.draw(in: CGRect(x: (a4.width - str.width) / 2, y: (a4.height - str.height) / 2,
                                     width: str.width, height: str.height))
            }
        }
    }
}

/// Seksjon med dokumenter: se, del, legg til og slett.
struct DokumentSeksjon: View {
    @Environment(\.modelContext) private var context

    let dokumenter: [Dokument]
    var forklaring: String = "F.eks. signert avtale, tilbud eller vilkår."
    let leggTil: (Dokument) -> Void
    let fjern: (Dokument) -> Void

    @State private var visFilvelger = false
    @State private var visSkanner = false
    @State private var valgteFoto: [PhotosPickerItem] = []
    @State private var forhandsvis: URL?
    @State private var feil: String?

    private var sortert: [Dokument] { dokumenter.sorted { $0.opprettet > $1.opprettet } }

    var body: some View {
        Section {
            ForEach(sortert) { d in
                Button {
                    if let url = d.midlertidigFil() {
                        forhandsvis = url
                    } else {
                        feil = "Fant ikke filen. Den er kanskje ikke ferdig synkronisert fra iCloud ennå."
                    }
                } label: {
                    HStack {
                        Label(d.navn, systemImage: d.ikon)
                        Spacer()
                        Text(d.opprettet.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
                .swipeActions {
                    Button(role: .destructive) {
                        slett(d)
                    } label: {
                        Label("Slett", systemImage: "trash")
                    }
                }
            }

            Menu {
                Button("Velg fil", systemImage: "folder") { visFilvelger = true }
                if VNDocumentCameraViewController.isSupported {
                    Button("Skann dokument", systemImage: "doc.viewfinder") { visSkanner = true }
                }
                PhotosPicker(selection: $valgteFoto, maxSelectionCount: 10, matching: .images) {
                    Label("Velg bilde", systemImage: "photo.on.rectangle")
                }
            } label: {
                Label("Legg til dokument", systemImage: "paperclip")
            }
            .quickLookPreview($forhandsvis)
            .fileImporter(isPresented: $visFilvelger, allowedContentTypes: [.item], allowsMultipleSelection: true) { svar in
                guard case .success(let urler) = svar else { return }
                var feilet: [String] = []
                for url in urler {
                    let tilgang = url.startAccessingSecurityScopedResource()
                    defer { if tilgang { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url) else {
                        feilet.append(url.lastPathComponent)
                        continue
                    }
                    let filtype = url.pathExtension.isEmpty ? "pdf" : url.pathExtension.lowercased()
                    legg(Dokument(navn: url.deletingPathExtension().lastPathComponent, filtype: filtype, data: data))
                }
                if !feilet.isEmpty {
                    feil = "Kunne ikke lese \(feilet.map { "«\($0)»" }.joined(separator: ", ")). Ligger filen i iCloud Drive, kan du åpne den i Filer-appen først så den lastes ned."
                }
            }
            .fullScreenCover(isPresented: $visSkanner) {
                DokumentSkanner { sider in
                    guard !sider.isEmpty else { return }
                    legg(Dokument(navn: "Skannet \(Date.now.formatted(date: .abbreviated, time: .omitted))",
                                  filtype: "pdf", data: Dokumenter.pdf(av: sider)))
                }
                .ignoresSafeArea()
            }
            .onChange(of: valgteFoto) { _, nye in
                guard !nye.isEmpty else { return }
                Task {
                    for (i, item) in nye.enumerated() {
                        if let raa = try? await item.loadTransferable(type: Data.self),
                           let bilde = UIImage(data: raa),
                           let jpg = Bildeverktoy.komprimer(bilde, maksSide: 3000) {
                            legg(Dokument(navn: nye.count == 1 ? "Bilde" : "Bilde \(i + 1)", filtype: "jpg", data: jpg))
                        }
                    }
                    valgteFoto = []
                }
            }
            .alert("Dokument", isPresented: Binding(get: { feil != nil }, set: { if !$0 { feil = nil } })) {
                Button("OK") { feil = nil }
            } message: {
                Text(feil ?? "")
            }
        } header: {
            Text("Dokumenter")
        } footer: {
            Text(dokumenter.isEmpty
                 ? "\(forklaring) Dokumentene synkes og er med i sikkerhetskopien."
                 : "Trykk for å åpne og dele. Sveip for å slette.")
        }
    }

    private func legg(_ d: Dokument) {
        context.insert(d)
        leggTil(d)
        try? context.save()
    }

    private func slett(_ d: Dokument) {
        fjern(d)
        context.delete(d)
        try? context.save()
    }
}
