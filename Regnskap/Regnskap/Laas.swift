import SwiftUI
import LocalAuthentication

/// Låser appen med Face ID, Touch ID eller koden på enheten.
///
/// Låseskjermen ligger i et eget vindu over alt annet, så den dekker også skjemaer som er åpne.
@MainActor
enum Laas {
    static var erPaa: Bool { UserDefaults.standard.bool(forKey: Innstilling.laas) }

    private static var vinduer: [UIWindow] = []
    private static var skalSporre = true
    private static var sporNaa = false

    /// Om enheten kan låses (har Face ID, Touch ID eller kode).
    static var stottes: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var metode: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "koden"
        }
    }

    /// Kalles når appen går i bakgrunnen.
    static func appenErBorte() {
        guard erPaa else { return }
        visLaaseskjerm()
        skalSporre = true
    }

    /// Kalles når appen blir aktiv. Spør bare én gang per gang appen åpnes,
    /// så du ikke får Face ID-spørsmålet om og om igjen hvis du avbryter.
    static func appenErAktiv() {
        guard erPaa, stottes else { skjul(); return }
        guard skalSporre else { return }
        skalSporre = false
        visLaaseskjerm()
        laasOpp()
    }

    static func laasOpp() {
        guard !sporNaa else { return }
        sporNaa = true
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Avbryt"
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Lås opp regnskapet") { ok, feil in
            // Har enheten ikke lenger kode, kan den ikke låses opp. Da slipper vi deg inn i stedet for å stenge deg ute.
            let ingenKode = (feil as? LAError)?.code == .passcodeNotSet
            Task { @MainActor in
                sporNaa = false
                if ok || ingenKode { skjul() }
            }
        }
    }

    /// Legger låseskjermen over hvert vindu appen har åpent (iPad og Mac kan ha flere).
    private static func visLaaseskjerm() {
        guard vinduer.isEmpty else { return }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            let v = UIWindow(windowScene: scene)
            v.windowLevel = .alert + 1
            v.rootViewController = UIHostingController(rootView: LaaseskjermView())
            v.makeKeyAndVisible()
            vinduer.append(v)
        }
    }

    private static func skjul() {
        for v in vinduer { v.isHidden = true }
        vinduer = []
        // Gi tastaturet og fokuset tilbake til appens egne vinduer.
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.windows.first { $0.windowLevel == .normal }?.makeKey()
        }
    }
}

private struct LaaseskjermView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Logomerke()
                .fill(Color.temaFjell)
                .frame(width: 56, height: 56)
            Text("Regnskapet er låst")
                .font(.title2.weight(.semibold))
            Button {
                Laas.laasOpp()
            } label: {
                Label("Lås opp", systemImage: "lock.open")
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .temaBakgrunn()
    }
}
