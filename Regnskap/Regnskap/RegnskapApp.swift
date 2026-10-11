import SwiftUI
import SwiftData

@main
struct RegnskapApp: App {
    let container = Lagring.lagContainer()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Tema.konfigurer()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: "nb_NO"))
                .task { Lagring.flyttGamleBilder(container.mainContext) }
        }
        .onChange(of: scenePhase, initial: true) { _, fase in
            if fase == .active {
                AutoKopi.kjorHvisNodvendig(container.mainContext)
            }
        }
        .modelContainer(container)
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Oversikt", systemImage: "chart.bar.doc.horizontal") {
                OversiktView()
            }
            Tab("Bilag", systemImage: "doc.text.viewfinder") {
                BilagListeView()
            }
            Tab("Inntekter", systemImage: "banknote") {
                InntekterView()
            }
            Tab("Kalkulatorer", systemImage: "function") {
                KalkulatorerView()
            }
            Tab("Frister", systemImage: "calendar.badge.clock") {
                FristerView()
            }
        }
        // Faner nederst på iPhone, sidemeny på iPad og Mac.
        .tabViewStyle(.sidebarAdaptable)
    }
}
