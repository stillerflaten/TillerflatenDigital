# Regnskap – Tillerflaten Digital

En iPhone-app (SwiftUI + SwiftData) som hjelper med regnskapet i enkeltpersonforetaket ved siden av fast jobb.

All data lagres på telefonen og synkroniseres til din private iCloud (CloudKit). I tillegg kan du lage en sikkerhetskopi-fil med alt innhold under Innstillinger (tannhjulet) og gjenopprette fra den.

## Hva appen gjør

| Fane | Innhold |
|---|---|
| **Oversikt** | Årets inntekter, fradrag og overskudd, og hvor mye du bør sette av til skatt. Viser også hvor nær du er mva-grensen, ubetalte regninger og neste frist. Eksport til regneark (CSV). |
| **Bilag** | Kvitteringer og regninger med ett eller flere bilder (skann flere sider med kameraet eller velg flere bilder), kategori, mva og hvor stor del som brukes i foretaket. Regninger får varsel dagen før forfall. |
| **Inntekter** | Utbetalinger fra App Store (og andre inntekter), med anslag på hvor mye av hver utbetaling du bør sette av. |
| **Kalkulatorer** | Skatt på overskuddet oppå lønn, avskrivning av utstyr (direkte fradrag eller saldogruppe a/d), kjørelogg, forklaring av mva for App Store-utviklere og en sjekkliste for nytt ENK. |
| **Frister** | Forskuddsskatt, skattemelding og (hvis mva-registrert) mva-terminer, med varsler. Fristene og forfall på regninger kan legges i en egen kalender, «Tillerflaten Digital». |

## Satser

Alle satser ligger i `Regnskap/Satser.swift`. De er hentet fra
[Skattesatser 2026 (regjeringen.no)](https://www.regjeringen.no/no/tema/okonomi-og-budsjett/skatter-og-avgifter/skattesatser-2026/id3121978/)
og [Skatteetaten](https://www.skatteetaten.no/person/skatt/skattekort/forskuddsskatt/) i oktober 2026.

Kilometersatsen (3,50 kr/km) og hjemmekontor-sjablongen (1 850 kr) bør dobbeltsjekkes hos Skatteetaten.

Når 2027-satsene er vedtatt (desember), legges de inn som `aar2027` i samme fil.

Tallene er estimater og erstatter ikke Skatteetaten eller en regnskapsfører.

## Slik åpner og kjører du appen

1. Åpne **GitHub Desktop**.
2. Velg repoet **TillerflatenDigital** øverst til venstre.
3. Klikk **Fetch origin**.
4. Klikk på **Current Branch** og velg `main`, og klikk **Pull origin**.
5. Velg **Repository → Show in Finder**.
6. Gå inn i mappen `Regnskap` og dobbeltklikk på `Regnskap.xcodeproj`. Xcode åpner seg.
7. Klikk på det blå **Regnskap**-ikonet øverst i venstre kolonne, velg target **Regnskap**, fanen **Signing & Capabilities**, og sjekk at **Team** er ditt (samme som i HockeySub).
8. Velg iPhone-en din (eller en simulator) øverst i Xcode, og trykk **▶︎** (eller ⌘R).

### Skru på iCloud (én gang)

1. I Xcode: klikk det blå **Regnskap**-ikonet → target **Regnskap** → **Signing & Capabilities**.
2. Du skal se **iCloud** med **CloudKit** krysset av. Under **Containers**, sjekk at `iCloud.Silje.Regnskap` er krysset av. Er den rød eller mangler, trykk **+** og skriv `iCloud.Silje.Regnskap`, og trykk deretter på det lille oppdateringsikonet.
3. Du skal også se **Push Notifications** og **Background Modes** med **Remote notifications** krysset av.
4. Kjør appen. Under tannhjulet → Sikkerhetskopi skal det stå «iCloud-synk: På».

### Kjør appen på Macen

Appen kjører på Mac med Apple-chip (M1 eller nyere) som «Designed for iPad». Den bruker samme iCloud-data som telefonen, så alt du legger inn ett sted, dukker opp det andre.

1. Velg **My Mac (Designed for iPad)** i enhetsvelgeren øverst i Xcode (der du ellers velger iPhone-en).
2. Trykk **▶︎**. Første gang kan Xcode spørre om å registrere Macen i utviklerkontoen. Svar ja.
3. Appen ligger etterpå i Programmer-mappen og kan åpnes derfra eller festes i Dock.

Skanneren finnes ikke på Mac. Der legger du til bilder fra Bilder-appen, og iCloud-bilder tatt med telefonen dukker opp der.

Før appen sendes til TestFlight eller App Store, må databasestrukturen publiseres: gå til [CloudKit Console](https://icloud.developer.apple.com), velg containeren og trykk **Deploy Schema Changes…** til Production.

Testene kjører du med **⌘U**. De sjekker at skatte-, avskrivnings- og fristberegningene gir riktige tall.
