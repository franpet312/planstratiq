# Planstratiq

Web aplikacija za planiranje kuće ili stana: nacrtaj tlocrt (ili ga precrtaj sa slike nacrta),
pomiči zidove dok mjere ne sjednu, opremi prostorije namještajem stvarnih dimenzija i prošeći
kroz svoj budući dom u 3D-u. Radi u pregledniku, bez instalacije.

**Otvori aplikaciju:** https://franpet312.github.io/planstratiq/

## Što sve radi

**Projekti**
- Početni ekran s projektima (spremaju se automatski u preglednik), predlošcima kuće i stana i praznim papirom.
- Kopiranje, preimenovanje, brisanje, spremanje projekta kao datoteke i otvaranje na drugom računalu.

**Tlocrt (2D)**
- Izgled pravog arhitektonskog nacrta: šrafirani nosivi zidovi, kote s kosinama, natpisi prostorija s neto površinom i vrstom poda, simboli namještaja.
- *Prostorija:* povuci pravokutnik, zidovi se sami spajaju sa susjednima.
- *Zidovi:* klik po klik, hvatanje na kutove 0/45/90° i postojeće točke; upiši duljinu (npr. `4,25`) i Enter za točnu mjeru.
- Prostorije se **prepoznaju same** iz zatvorenih zidova (i nepravilnih oblika); zidovi se dijele na T-spojevima i križanjima.
- Pomicanje zida povlačenjem (spojeni zidovi prate), pomicanje kuta, pomicanje cijele prostorije.
- Vrata, prozori, balkonska vrata i prolazi; šarke i smjer otvaranja vrata.
- Alat za mjerenje, mjerilo, zoom, pinch-zoom na dodir.
- Učitavanje slike nacrta kao podloge i kalibracija mjerila (dvije točke + stvarna udaljenost).
- **Automatsko prepoznavanje nacrta**: iz slike se prepoznaju zidovi (s debljinom), vrata i prozori i ucrtaju u tlocrt; mjerilo se procijeni iz širine vrata ili upiše ukupna širina zgrade s kote. Radi u pregledniku (`web/psqdetect.js`), najbolje za nacrte s vodoravnim i okomitim, ispunjenim ili šrafiranim zidovima.
- **PDF nacrti i nagnuti skenovi**: nacrt se može učitati i kao PDF (prva stranica se iscrta u visokoj rezoluciji), a nagnut sken ili fotografija automatski se izravna (do ±6°).

**Etaže**
- Podrum, prizemlje i katovi: svaka etaža ima svoje zidove, prostorije i namještaj; kota poda računa se sama (svijetla visina + 25 cm ploče).
- Novi kat preuzima vanjske zidove etaže ispod; na tlocrtu se etaža ispod vidi prozirno (plavo), a kutovi joj služe za hvatanje.
- Stubište postavljeno u prizemlju automatski probija otvor u ploči kata; u 3D šetnji (prvo i treće lice) stubama se hoda gore-dolje između etaža.
- U 3D-u izvana prikazuju se etaže do odabrane (presjek), ili sve etaže s krovom na najvišoj.

**Namještaj i okućnica**
- **Stvarni proizvodi trgovina**: ~680 proizvoda IKEA, JYSK i Emmezeta (naziv, mjere, cijena, poveznica na proizvod), filtar po trgovini; boje istog proizvoda grupirane su u jedan model. Kod dijela IKEA proizvoda dubina ili visina su procijenjene (oznaka „mjere okvirne”). Podaci: `web/retail/products.csv`.
- Katalog s **~24.600 varijanti u 464 modela**: ~90 vrsta namještaja i opreme × 8 stilova (skandinavski, moderni, klasični, industrijski, rustikalni, minimalistički, boho, retro) × veličine × boje × izvedbe nogu. Realne mjere, okvirne cijene, 3D sličice.
- Pretraga, filtri po prostoriji i stilu, poredak po cijeni; detalj modela s odabirom veličine, boje i nogu.
- **Uvoz kataloga trgovine** (CSV ili JSON): naziv, mjere, cijena, boja, link na proizvod i GLB 3D model. Vrsta namještaja se prepoznaje iz naziva. Predložak CSV-a preuzima se iz kataloga.
- Povuci objekt na tlocrt ili u 3D; uz zid se sam okrene leđima prema zidu.
- Rotacija ručicom (korak 15°), strelice za pomak 1 cm, dupliciranje, promjena mjera i boje.

**3D**
- Zidovi s otvorima, fasada, podovi s teksturama (parket, laminat, pločice, kamen, beton, tepison), nebo, sjene.
- Doba dana (položaj sunca), krov, snimka prikaza kao slika.
- Odabir i povlačenje namještaja izravno u 3D-u.
- Tri načina pogleda: **izvana** (orbit), **treće lice** (animirani lik hoda kućom, kamera ga prati i ne prolazi kroz zidove; povlačenje mišem okreće kameru, kotačić mijenja udaljenost) i **prvo lice**.
- **Šetnja u prvom licu**: W A S D + miš, ili na mobitelu lijevi palac za hodanje i desni za gledanje; ne prolazi se kroz zidove, kroz vrata da. Položaj osobe vidi se uživo na tlocrtu. Brzi skok u prostoriju.

**Pregled i cijene**
- Neto površina (po licima zidova) i bruto tlocrtna površina, popis prostorija.
- Okvirni troškovnik: podovi po materijalu, bojanje zidova (m² i litre), namještaj.
- Izvoz: tlocrt kao PNG s natpisnim poljem, troškovnik kao CSV (Excel), projekt kao datoteka.

## Prečaci

| Tipka | Radnja |
|---|---|
| V / W / R | Odabir / zidovi / prostorija |
| D / P / M | Vrata / prozor / mjerenje |
| brojke + Enter | Točna duljina zida dok crtaš |
| Ctrl+Z / Ctrl+Y | Poništi / ponovi |
| Delete | Obriši odabrano |
| R / Shift+R | Okreni namještaj ±90° |
| Ctrl+D | Dupliciraj namještaj |
| strelice (Shift) | Pomakni namještaj 1 cm (10 cm) |
| + / − / 0 | Zoom / cijeli tlocrt |
| Esc | Prekini alat |

## Razvoj

Potrebno: Flutter SDK (stable) i Chrome.

```bash
git clone https://github.com/franpet312/planstratiq
cd planstratiq
flutter create . --platforms web --project-name planstratiq   # samo prvi put; NE prepisuj web/index.html
flutter pub get
flutter run -d chrome
```

Svaki push na `main` automatski se gradi i objavljuje na GitHub Pages (`.github/workflows/deploy.yml`).

## Arhitektura

```
Flutter Web (Dart)                                        Three.js (web/planstratiq3d.js)
┌──────────────────────────────────────────────┐          ┌──────────────────────────────────┐
│ HomePage – projekti, predlošci               │          │ Engine                           │
│ EditorPage                                   │  JSON    │  zidovi s otvorima, fasada       │
│   PlanEditor + PlanPainter (2D nacrt)        │ ───────► │  podovi s teksturama, krov       │
│   Viewer3D (HtmlElementView) ────────────────┼─ setPlan │  proceduralni namještaj / GLB    │
│   Katalog / Svojstva / Pregled i cijene      │ ◄─────── │  orbit + odabir/povlačenje       │
│ PlanController – stanje, povijest, topologija│  događaji│  šetnja (PointerLock, dodir)     │
│ ProjectStore – localStorage                  │ select,  │  nebo, sunce, sjene, snimka      │
│ Plan – čvorovi, zidovi, otvori, prostorije,  │ move,    │  sličice kataloga                │
│        namještaj, slika nacrta               │ pose     └──────────────────────────────────┘
└──────────────────────────────────────────────┘
```

- **Model** (`lib/models/plan.dart`): zidovi dijele čvorove, pa pomicanje zida pomiče i spojene zidove. Mjere su u metrima.
- **Topologija** (`lib/models/topology.dart`): prostorije su lica planarnog grafa zidova; prepoznaju se nakon svake promjene, a postojeće zadržavaju naziv i pod. Neto/bruto površina računa se pomakom poligona za pola debljine zida.
- **3D** komunicira s Dartom preko `dart:js_interop` (`lib/viewer/engine_bridge.dart`).

```
lib/
  app/theme.dart                 paleta, tipografija (Archivo, Archivo Narrow)
  models/                        plan, katalog, materijali, topologija, predlošci, geometrija
  state/                         PlanController, ProjectStore
  editor/                        PlanEditor, PlanPainter (nacrt + simboli), izvoz PNG
  viewer/                        Viewer3D, most prema engineu, sličice
  ui/                            početni ekran, uređivač, paneli, zajedničke komponente
web/
  index.html, planstratiq3d.js
```

## Plan razvoja

1. **Bolje prepoznavanje nacrta**: kosi zidovi, ispravljanje perspektive fotografija, izbor stranice PDF-a, prepoznavanje naziva prostorija (OCR).
2. **Veći katalog trgovaca**: puni asortiman i 3D modeli traže partnerski/affiliate feed (naziv, šifra, mjere, cijena, link, GLB model); aplikacija je spremna (`retailer`, `productUrl`, `price`, `modelUrl`).
3. **Korisnički računi** i projekti u oblaku (npr. Supabase/Firebase).
4. Složeniji krovovi, teren i nagib parcele, ograda po rubu parcele.
5. PDF izvoz s presjecima i specifikacijom; WebXR za VR šetnju.
