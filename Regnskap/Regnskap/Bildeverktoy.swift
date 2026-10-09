import SwiftUI
import PhotosUI
import VisionKit

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

/// Velg bilde fra biblioteket, eller skann kvitteringen med kameraet.
struct BildeVelger: View {
    @Binding var bildeData: Data?

    @State private var valgtFoto: PhotosPickerItem?
    @State private var visSkanner = false
    @State private var visStortBilde = false

    var body: some View {
        if let bildeData, let bilde = UIImage(data: bildeData) {
            Button {
                visStortBilde = true
            } label: {
                Image(uiImage: bilde)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $visStortBilde) {
                StortBildeView(bilder: [bilde])
            }
            Button("Fjern bilde", role: .destructive) {
                self.bildeData = nil
            }
        }

        if VNDocumentCameraViewController.isSupported {
            Button {
                visSkanner = true
            } label: {
                Label("Skann kvittering", systemImage: "doc.viewfinder")
            }
            .fullScreenCover(isPresented: $visSkanner) {
                DokumentSkanner { sider in
                    if let forste = sider.first {
                        bildeData = Bildeverktoy.komprimer(forste)
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
                    bildeData = Bildeverktoy.komprimer(bilde)
                }
                valgtFoto = nil
            }
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
