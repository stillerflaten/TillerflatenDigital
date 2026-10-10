# Tillerflaten Digital

Enkeltpersonforetak for utvikling og salg av apper, og på sikt nettsider for bedrifter.

## Navn

**Tillerflaten Digital** – valgt 9. oktober 2026.

- Oppfyller kravet om at et ENK-navn skal inneholde innehaverens etternavn (foretaksnavneloven § 2-2).
- «Digital» dekker både apper og nettsider, så navnet fungerer også når tilbudet utvides.

## Sjekk gjort 9. oktober 2026

**Domener** (whois ga «No match», altså ledige da). Kjøpt 10. oktober 2026:
- [x] tillerflatendigital.no – hovedadresse for nettsiden, e-post post@tillerflatendigital.no
- [x] tillerflatendigital.com – videresendes til tillerflatendigital.no

**Brønnøysundregistrene:** Eneste andre treff på «Tillerflaten» er *Tillerflaten Bjørnetjenester* (ENK), som er en helt annen bransje. Ingen konflikt.

## Gjøremål

- [x] Kjøpe domener
- [ ] Registrere ENK i Enhetsregisteret via Altinn («Samordnet registermelding», gratis)
- [ ] Sikre brukernavn: Instagram, LinkedIn, GitHub (f.eks. @tillerflatendigital)
- [ ] Skaffe D-U-N-S-nummer (gratis via Apple) og registrere Apple Developer-konto som organisasjon
- [x] Lage enkel landingsside (https://tillerflatendigital.no)

## Landingsside

Ligger i `site/` (ren HTML/CSS, ingen byggesteg). Kjør lokalt:

```bash
python3 -m http.server 8420 --directory site
```

Publiseres automatisk til https://tillerflatendigital.no med GitHub Pages når `site/` endres på main. Org.nr. legges inn når foretaket er registrert (se `TODO` i `site/index.html`).

## Regnskapsapp

Ligger i `Regnskap/`. iPhone-app for kvitteringer, inntekter, skatteberegning, avskrivning og frister. Se [Regnskap/README.md](Regnskap/README.md).

## Andre navneforslag som ble vurdert

Pixelfjord, Lysning, Kodeklar, Nordbyte, Spire Digital, Fjellkode, Tindestudio, Lille Lab, Tillerflaten Studio.
