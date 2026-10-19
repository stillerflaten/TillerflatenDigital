import SwiftUI
import PhotosUI
import VisionKit
import PDFKit
import QuickLook
import UniformTypeIdentifiers

enum Bildeverktoy {
    /// Krymper bildet og lagrer det som JPEG, så kvitteringene ikke fyller opp telefonen.
    static func komprimer(_ bilde: UIImage, maksSide: CGFloat = 2000) -> Data? {
        let storst = max(bilde.size.width, bilde.size.height)
        let skala = min(1, maksSide / storst)
        let ny = CGSize(width: bilde.size.width * skala, height: bilde.size.height * skala)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let skalert = UIGraphicsImageRenderer(size: ny, format: format).image { _ in
            bilde.draw(in: CGRect(origin: .zero, size: ny))
        }
        return skalert.jpegData(compressionQuality: 0.7)
    }
}

/// Ett dokument (bilde eller PDF): skann, velg bilde eller velg en PDF fra Filer.
struct BildeVelger: View {
    @Binding var bildeData: Data?
    /// «jpg» eller «pdf».
    @Binding var filtype: String

    @State private var valgtFoto: PhotosPickerItem?
    @State private var visSkanner = false
    @State private var visStortBilde = false
    @State private var visFilvelger = false
    @State private var forhandsvis: URL?
    @State private var feil: String?

    private var erPdf: Bool { filtype.lowercased() == "pdf" }

    private var miniatyr: UIImage? {
        guard let bildeData else { return nil }
        if erPdf {
            return PDFDocument(data: bildeData)?.page(at: 0)?.thumbnail(of: CGSize(width: 340, height: 480), for: .mediaBox)
        }
        return UIImage(data: bildeData)
    }

    var body: some View {
        if let bilde = miniatyr {
            Button {
                if erPdf {
                    apnePdf()
                } else {
                    visStortBilde = true
                }
            } label: {
                Image(uiImage: bilde)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottomLeading) {
                        if erPdf {
                            Text("PDF")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.85), in: Capsule())
                                .padding(5)
                        }
                    }
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $visStortBilde) {
                StortBildeView(bilder: [bilde])
            }
            Button(erPdf ? "Fjern PDF" : "Fjern bilde", role: .destructive) {
                bildeData = nil
                filtype = "jpg"
            }
        }

        if VNDocumentCameraViewController.isSupported {
            Button {
                visSkanner = true
            } label: {
                Label("Skann dokument", systemImage: "doc.viewfinder")
            }
            .fullScreenCover(isPresented: $visSkanner) {
                DokumentSkanner { sider in
                    if let forste = sider.first {
                        sett(Bildeverktoy.komprimer(forste), filtype: "jpg")
                    }
                }
                .ignoresSafeArea()
            }
        }

        PhotosPicker(selection: $valgtFoto, matching: .images) {
            Label("Velg bilde eller skjermbilde", systemImage: "photo.on.rectangle")
        }
        .onChange(of: valgtFoto) { _, nytt in
            guard let nytt else { return }
            Task {
                if let data = try? await nytt.loadTransferable(type: Data.self),
                   let bilde = UIImage(data: data) {
                    sett(Bildeverktoy.komprimer(bilde), filtype: "jpg")
                }
                valgtFoto = nil
            }
        }

        Button {
            visFilvelger = true
        } label: {
            Label("Velg PDF eller fil", systemImage: "doc.richtext")
        }
        .quickLookPreview($forhandsvis)
        .fileImporter(isPresented: $visFilvelger, allowedContentTypes: [.pdf, .image]) { svar in
            guard case .success(let url) = svar else { return }
            let tilgang = url.startAccessingSecurityScopedResource()
            defer { if tilgang { url.stopAccessingSecurityScopedResource() } }
            if let raa = try? Data(contentsOf: url) {
                if PDFDocument(data: raa) != nil {
                    sett(raa, filtype: "pdf")
                    return
                }
                if let bilde = UIImage(data: raa) {
                    sett(Bildeverktoy.komprimer(bilde), filtype: "jpg")
                    return
                }
            }
            feil = "Kunne ikke lese «\(url.lastPathComponent)». Ligger filen i iCloud Drive, kan du åpne den i Filer-appen først så den lastes ned."
        }
        .alert("Dokumentasjon", isPresented: Binding(get: { feil != nil }, set: { if !$0 { feil = nil } })) {
            Button("OK") { feil = nil }
        } message: {
            Text(feil ?? "")
        }
    }

    private func sett(_ data: Data?, filtype: String) {
        guard let data else { return }
        bildeData = data
        self.filtype = filtype
    }

    private func apnePdf() {
        guard let bildeData else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dokumentasjon-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        if (try? bildeData.write(to: url, options: .atomic)) != nil {
            forhandsvis = url
        } else {
            feil = "Kunne ikke åpne PDF-en."
        }
    }
}

struct StortBildeView: View {
    let bilder: [UIImage]
    @State var valgt = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $valgt) {
                ForEach(bilder.indices, id: \.self) { i in
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: bilder[i])
                            .resizable()
                            .scaledToFit()
                            .containerRelativeFrame(.horizontal)
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: bilder.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .navigationTitle(bilder.count > 1 ? "Bilde \(valgt + 1) av \(bilder.count)" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lukk") { dismiss() }
                }
            }
        }
    }
}

/// Apples innebygde dokumentskanner (samme som i Notater-appen).
struct DokumentSkanner: UIViewControllerRepresentable {
    /// Får alle sidene som ble skannet.
    let ferdig: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let forelder: DokumentSkanner
        init(_ forelder: DokumentSkanner) { self.forelder = forelder }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            forelder.ferdig((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
            forelder.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            forelder.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            forelder.dismiss()
        }
    }
}

/// Legger en «Ferdig»-knapp over tallastaturet, som ellers mangler en måte å lukkes på.
struct TastaturFerdigKnapp: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Ferdig") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
    }
}

extension View {
    func tastaturFerdigKnapp() -> some View { modifier(TastaturFerdigKnapp()) }
}
