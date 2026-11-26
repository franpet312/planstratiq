# Planstratiq

Web aplikacija za planiranje kuće ili stana: nacrtaj tlocrt (ili ga precrtaj sa slike nacrta),
pomiči zidove dok mjere ne sjednu, opremi prostorije namještajem stvarnih dimenzija i prošeći
kroz svoj budući dom u 3D-u. Radi u pregledniku, bez instalacije.

**Otvori aplikaciju:** https://franpet312.github.io/planstratiq/

## Što sve radi

**Projekti**
- Početni ekran s projektima (spremaju se automatski u preglednik; slike nacrta u IndexedDB, pa se ne gube ni kod velikih skenova), predlošcima kuće i stana i praznim papirom.
- Kopiranje, preimenovanje, brisanje, spremanje projekta kao datoteke i otvaranje na drugom računalu.

**Tlocrt (2D)**
- Izgled pravog arhitektonskog nacrta: šrafirani nosivi zidovi, kote s kosinama, natpisi prostorija s neto površinom i vrstom poda, simboli namještaja.
- *Prostorija:* povuci pravokutnik, zidovi se sami spajaju sa susjednima.
- *Zidovi:* klik po klik, hvatanje na kutove 0/45/90° i postojeće točke; upiši duljinu (npr. `4,25`) i Enter za točnu mjeru.
- Prostorije se **prepoznaju same** iz zatvorenih zidova (i nepravilnih oblika); zidovi se dijele na T-spojevima i križanjima.
- Pomicanje zida povlačenjem (spojeni zidovi prate), pomicanje kuta, pomicanje cijele prostorije.
- Vrata, prozori, balkonska vrata i prolazi; šarke i smjer otvaranja vrata.
- **Izvedbe otvora**: vrata krilna, dvokrilna, klizna (po zidu, s vodilicom), klizna u zid i harmonika; prozori krilni, klizni i fiksni; balkonska vrata krilna ili klizna stijena – s pravim simbolima na tlocrtu i otvaranjem u 3D-u.
- Alat za mjerenje, mjerilo, zoom, pinch-zoom na dodir.
- Učitavanje slike nacrta kao podloge i kalibracija mjerila (dvije točke + stvarna udaljenost).
- **Automatsko prepoznavanje nacrta**: iz slike se prepoznaju zidovi (s debljinom), vrata i prozori i ucrtaju u tlocrt; mjerilo se procijeni iz širine vrata ili upiše ukupna širina zgrade s kote. Radi u pregledniku (`web/psqdetect.js`), najbolje za nacrte s vodoravnim i okomitim, ispunjenim ili šrafiranim zidovima.
- **PDF nacrti i nagnuti skenovi**: nacrt se može učitati i kao PDF (prva stranica se iscrta u visokoj rezoluciji), a nagnut sken ili fotografija automatski se izravna (do ±6°).

**Etaže**
- Podrum, prizemlje i katovi: svaka etaža ima svoje zidove, prostorije i namještaj; kota poda računa se sama (svijetla visina + 25 cm ploče).
- Novi kat preuzima vanjske zidove etaže ispod; na tlocrtu se etaža ispod vidi prozirno (plavo), a kutovi joj služe za hvatanje.
- Stubište (ravno, L s podestom ili zavojito) postavljeno u prizemlju automatski probija otvor u ploči kata u obliku stubišta; u 3D šetnji (prvo i treće lice) stubama se hoda gore-dolje između etaža.
- U 3D-u izvana prikazuju se etaže do odabrane (presjek), ili sve etaže s krovom na najvišoj.

**Namještaj i okućnica**
- **Stvarni proizvodi trgovina**: ~680 proizvoda IKEA, JYSK i Emmezeta (naziv, mjere, cijena, poveznica na proizvod), filtar po trgovini; boje istog proizvoda grupirane su u jedan model. Kod dijela IKEA proizvoda dubina ili visina su procijenjene (oznaka „mjere okvirne”). Podaci: `web/retail/products.csv`.
- Katalog s **~24.600 varijanti u 464 modela**: ~90 vrsta namještaja i opreme × 8 stilova (skandinavski, moderni, klasični, industrijski, rustikalni, minimalistički, boho, retro) × veličine × boje × izvedbe nogu. Realne mjere, okvirne cijene, 3D sličice.
- **Izbornik kataloga**: početna stranica s trgovinama (IKEA, JYSK, Emmezeta, Planstratiq katalog i uvezene trgovine – broj proizvoda i brzi ulaz u kategorije), prostorijama i nedavno korištenim. U popisu se kombiniraju trgovina i kategorija (s brojem proizvoda), pretraga traži unutar odabrane trgovine, a detalj proizvoda nudi „Slično u drugim trgovinama” po cijeni.
- Filtri po stilu, poredak po cijeni; detalj modela s odabirom veličine, boje i nogu.
- **Uvoz kataloga trgovine** (CSV ili JSON): naziv, mjere, cijena, boja, link na proizvod i GLB 3D model. Vrsta namještaja se prepoznaje iz naziva. Predložak CSV-a preuzima se iz kataloga.
- Povuci objekt na tlocrt ili u 3D; uz zid se sam okrene leđima prema zidu.
- Rotacija ručicom (korak 15°), strelice za pomak 1 cm, dupliciranje, promjena mjera i boje.
- **Razmaci**: odabranom namještaju na tlocrtu se vide udaljenosti (cm) do zidova i drugog namještaja na sve četiri strane; u svojstvima se upiše željeni razmak i objekt se pomakne točno toliko.
- **Provjera prolaza i otvaranja**: upozorenje (crveno područje i znak na tlocrtu, popis u „Pregled i cijene”) kad namještaj stoji ispred vrata, kad se ladice, ormari, hladnjak, perilice ili pećnica ne mogu otvoriti, kad krevet nema 60 cm ni s jedne strane te za prolaze uže od 60 cm.
- **Rasvjeta** (kategorija „Rasvjeta”): klasični luster s kristalima, LED prsten, viseće lampe (pojedinačne i niz od tri iznad stola), plafonjera, zidna, stolna, podna i lučna podna lampa. Sve svijetle u 3D-u i pale se/gase (E, klik, dvoklik). Stropna rasvjeta visi s pravog stropa etaže, zidna se sama prisloni uz zid, a stolna lampa stoji na stolu ili komodi ispod sebe.
- **Sudaranje**: namještaj ne ulazi u zidove ni u drugi namještaj – pri povlačenju klizi uz prepreku (stolice se smiju podvući pod stol, tepisi i terase leže ispod svega, lusteri vise iznad stola, stolna lampa smije na stol ili komodu, ali ne u kauč, a lučnoj lampi smeta samo baza). Isključuje se u svojstvima objekta.
- **Balkoni**: ploča s ogradom (staklena, metalna ili zidana) uz vanjski zid. Dodaje se iz kataloga (sama se prisloni uz zid s vanjske strane) ili jednim klikom iz svojstava vanjskog zida / balkonskih vrata – ako zid nema balkonska vrata, dodaju se.

**3D**
- Zidovi s otvorima, fasada, podovi s teksturama (parket, laminat, pločice, kamen, beton, tepison), nebo, sjene.
- Doba dana (položaj sunca), snimka prikaza kao slika.
- **Krov koji prati obris kuće** (i L, T, U tlocrte): dvostrešni, četverostrešni, jednostrešni ili ravni s atikom; nagib, prepust, boja pokrova i smjer sljemena. Zabati se sami zatvaraju zidom.
- Odabir i povlačenje namještaja izravno u 3D-u.
- **Otvaranje i paljenje**: vrata, prozori i balkonska vrata, ormari, ladice, hladnjak, perilice i pećnica otvaraju se, a lampe, TV i kamin pale. U šetnji tipka E ili klik (na mobitelu dodir), izvana dvoklik. Zatvorena vrata ne propuštaju, a u šetnji se ne prolazi ni kroz namještaj ni kroz ogradu balkona.
- Tri načina pogleda: **izvana** (orbit), **treće lice** (animirani lik hoda kućom, kamera ga prati i ne prolazi kroz zidove; povlačenje mišem okreće kameru, kotačić mijenja udaljenost) i **prvo lice**.
- **Šetnja u prvom licu**: W A S D + miš, ili na mobitelu lijevi palac za hodanje i desni za gledanje; ne prolazi se kroz zidove, kroz vrata da. Položaj osobe vidi se uživo na tlocrtu. Brzi skok u prostoriju.

**Zidovi prostorija**
- Svaka prostorija ima svoju boju zidova i oblogu: pločice (bijele, metro, sive 30×60, zelene), drvena obloga, cigla, dekorativni beton ili tapeta – do 1,2 / 1,5 / 2,1 m ili cijeli zid, iznad obloge boja. Obloge ulaze u troškovnik.

**Parcela i okolina**
- Kuća stoji na parceli (automatski oko kuće ili zadane širine i dubine) s ograđenim travnjakom: drvena, metalna, žičana ograda, živica ili zid, s ulazom i prilazom do ulaznih vrata.
- Ispred je ulica s pločnicima, rubnjacima, uličnom rasvjetom i drvoredom.
- Okolina po izboru: **susjedstvo** (susjedne kuće sa svojim vrtovima), **selo** (polja, rijetke kuće, puno drveća) ili **grad** (stambene zgrade); u daljini brežuljci.
- Na tlocrtu se vidi rub parcele, ulica i površina parcele.

**Noć**
- Doba dana ide od 0 do 24 h: noću je nebo tamno sa zvijezdama i mjesecom, svijetle lampe i lusteri, prozori kuće, susjeda i ulična rasvjeta.

**Pregled i cijene**
- Neto površina (po licima zidova) i bruto tlocrtna površina, popis prostorija.
- Okvirni troškovnik: podovi po materijalu, bojanje zidova (m² i litre), namještaj.
- **Izvoz u PDF za ispis** (A4/A3): naslovnica s 3D prikazom i ključnim površinama, tlocrt svake etaže u mjerilu (automatski ili 1:50/1:100/1:200) s kotama, grafičkim mjerilom i natpisnim poljem, popis prostorija i okvirni troškovnik. Prečac Ctrl+P.
- Izvoz: tlocrt kao PNG s natpisnim poljem, troškovnik kao CSV (Excel), projekt kao datoteka.

## Prečaci

| Tipka | Radnja |
|---|---|
| V / W / R | Odabir / zidovi / prostorija |
| D / P / M | Vrata / prozor / mjerenje |
| brojke + Enter | Točna duljina zida dok crtaš |
| Ctrl+Z / Ctrl+Y | Poništi / ponovi |
| Ctrl+P | Izvoz u PDF |
| Ctrl+C / Ctrl+X / Ctrl+V | Kopiraj / izreži / zalijepi namještaj ili cijelu prostoriju (i na drugu etažu) |
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
