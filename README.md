# Planstratiq

Web aplikacija za planiranje kuće: iz nacrta (ili od nule) složiš tlocrt, a aplikacija
odmah generira 3D model kroz koji možeš **hodati u prvom licu**, pomicati zidove,
mijenjati mjere i opremati interijer i eksterijer namještajem.

## Pokretanje

Potrebno: Flutter SDK 3.24+ (Dart 3.5+) i Chrome.

```bash
cd planstratiq
flutter create . --platforms web --project-name planstratiq   # samo prvi put: doda ikone/manifest, NE dira lib/ i postojeće datoteke
flutter pub get
flutter run -d chrome
```

> Ako `flutter create` ponudi prepisivanje `web/index.html`, odgovori **ne** – naš index.html
> učitava 3D engine.

Build za produkciju: `flutter build web --release` → sadržaj `build/web/` ide na bilo koji
statički hosting (Firebase Hosting, Netlify, Vercel, Nginx…).

3D engine (Three.js 0.170) trenutno se učitava s CDN-a (jsdelivr). Za produkciju ga je
bolje preuzeti u `web/vendor/` i promijeniti putanje u `importmap` u `web/index.html`.

## Što radi (MVP)

| Funkcija | Kako |
|---|---|
| Učitavanje nacrta | „Učitaj nacrt” → slika (JPG/PNG) postaje podloga; alat **Mjerilo**: klikneš dvije točke poznate udaljenosti i upišeš stvarnu mjeru |
| Crtanje zidova | Alat **Zid**: klik-klik-klik; hvata se na postojeće točke i kutove 0/45/90°, korak 5 cm |
| Sobe | Alat **Soba**: povučeš pravokutnik, zidovi se kreiraju i spajaju sa susjednim sobama; prikaz površine m² |
| Pomicanje zida | U alatu Odabir povučeš zid – pomiče se okomito u koracima od 1 cm, spojeni zidovi prate. Duljina, debljina i visina mogu se upisati i brojčano |
| Vrata i prozori | Klik na zid; kasnije se povlače duž zida; širina, visina, parapet |
| Namještaj | Katalog interijera i eksterijera s realnim mjerama; postavljanje, pomicanje, rotacija (R), dupliciranje (Ctrl+D), boje |
| 3D pregled | Orbit kamera (rotacija/pomak/zoom), sjene, sunce, trava, nebo |
| Šetnja u prvom licu | „Šetnja” → klik u prikaz → WASD/strelice + miš, Shift trčanje, kolizija sa zidovima, prolaz kroz vrata, stropovi |
| Projekt | Undo/redo, automatsko spremanje u preglednik, izvoz/uvoz `.planstratiq.json`, demo kuća |
| Prikazi | 2D, 2D+3D uživo jedno uz drugo, 3D |

## Arhitektura

```
Flutter Web (Dart)                                   Three.js (JavaScript)
┌──────────────────────────────────────────┐         ┌──────────────────────────────┐
│ PlannerPage (UI, alati, paneli)          │         │ web/planstratiq3d.js         │
│   ├─ PlanEditor  (2D CustomPainter)      │  JSON   │  Engine                      │
│   ├─ Viewer3D    (HtmlElementView) ──────┼────────►│   ├─ zidovi s otvorima       │
│   ├─ CatalogPanel / PropertiesPanel      │ setPlan │   ├─ podovi / stropovi        │
│   └─ PlanController (stanje, undo/redo)  │ setMode │   ├─ proceduralni namještaj   │
│        └─ Plan (čvorovi, zidovi, otvori, │         │   │   + GLB modeli (GLTFLoader)│
│           sobe, objekti, slika nacrta)   │         │   ├─ OrbitControls            │
└──────────────────────────────────────────┘         │   └─ PointerLock + kolizija   │
                                                     └──────────────────────────────┘
```

* **Zašto Flutter + Three.js?** Flutter je odličan za sučelje i 2D uređivač, ali na webu
  nema zreo 3D engine sa sjenama, učitavanjem GLB modela i pointer-lock kontrolama.
  Three.js je standard za to; Dart s njim razgovara preko `dart:js_interop`.
* **Model podataka** (`lib/models/plan.dart`): zidovi dijele **čvorove** (točke spoja).
  Zato pomicanje jednog zida automatski produžuje/skraćuje susjedne. Sve mjere su u metrima.
* **Tok podataka**: svaka promjena povećava `revision` → `Viewer3D` šalje novi JSON enginu →
  engine ponovno gradi scenu (dovoljno brzo za stotine zidova/objekata).

```
lib/
  main.dart
  models/      plan.dart, catalog.dart, geometry.dart
  state/       plan_controller.dart
  editor/      plan_editor.dart, plan_painter.dart
  viewer/      viewer_3d.dart
  ui/          planner_page.dart, catalog_panel.dart, properties_panel.dart, web_files.dart
web/
  index.html, planstratiq3d.js
```

## Plan razvoja

1. **Automatsko prepoznavanje nacrta (AI)** – backend servis (Python/FastAPI) koji iz slike
   ili PDF-a prepoznaje zidove, vrata, prozore i prostorije (segmentacijski model treniran na
   skupovima poput CubiCasa5K + vektorizacija OpenCV-om) i vraća JSON u istom formatu kao
   `Plan.toJson()`. Korisnik zatim samo ispravlja. Do tada: precrtavanje preko podloge.
2. **Katalog trgovaca** – vidi dolje.
3. **Uređivanje u 3D-u** – odabir i povlačenje zidova/namještaja direktno u 3D prikazu
   (raycasting → poruka natrag u Dart).
4. **Više etaža, stubišta, krov** (dvostrešni/četverostrešni generator), balkoni, terasa.
5. **Materijali i teksture** – parket, pločice, fasada, crijep; PBR teksture.
6. **Teren i okućnica** – granica parcele, nagib, staze, ograde po rubu.
7. **Korisnički računi i oblak** – Firebase ili Supabase (auth + pohrana projekata + dijeljenje linkom).
8. **Izvoz** – PDF tlocrt s kotama, slike 3D prikaza, GLB/OBJ izvoz modela, popis namještaja s cijenama.
9. **Mobilno / VR** – Flutter omogućuje mobilnu aplikaciju; WebXR za VR šetnju.

## Namještaj trgovaca (IKEA, JYSK, Emmezeta…)

Katalog je trenutno generički (realne mjere + proceduralni 3D oblici). Za stvarne proizvode:

* Ovi trgovci **nemaju javni API** za preuzimanje 3D modela, a njihovi modeli i fotografije
  zaštićeni su autorskim pravom – scraping s njihovih stranica nije dopušten.
* Ispravan put je **partnerstvo / affiliate program**: trgovac daje produktni feed (naziv,
  šifra, mjere, cijena, link, slike) i, idealno, GLB modele. Alternativno, vlastiti 3D
  modeli izrađeni prema javno objavljenim mjerama, uz link na proizvod.
* Tehnički je sve spremno: `CatalogItem` ima `retailer`, `productUrl`, `price` i `modelUrl`
  (GLB). Kad `modelUrl` postoji, engine učita model i skalira ga na mjere proizvoda.
* Preporuka: katalog prebaciti na backend (npr. `GET /catalog?retailer=…&category=…`) kako bi
  se feedovi mogli osvježavati bez nove verzije aplikacije.

## Prečaci

| Tipka | Radnja |
|---|---|
| Ctrl+Z / Ctrl+Y | Poništi / ponovi |
| Ctrl+S | Spremi projekt (JSON) |
| Del / Backspace | Obriši odabrano |
| R / Shift+R | Rotiraj namještaj ±90° |
| Ctrl+D | Dupliciraj namještaj |
| Esc | Prekini alat / odznači |
| Kotačić / srednja tipka | Zoom / pomak 2D pogleda |
| W A S D, Shift, Esc | Šetnja u 3D-u |
