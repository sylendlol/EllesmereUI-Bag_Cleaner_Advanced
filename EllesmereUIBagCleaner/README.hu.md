# EllesmereUI Bag Cleaner

Az EllesmereUI-hoz készült, a suite saját moduljai mintájára felépített modul. A Naowh
Forever "Bag Space" funkciójának átirata: a táska legolcsóbb tárgyai egy kis sávon.

Korábbi neve **Bag Slots** (`EllesmereUIBagSlots`). Az első betöltéskor átveszi a régi
beállításokat, az Ignore Listet, a sáv helyét, az aukciós árakat és a gyorsbillentyűt; utána a
régi `EllesmereUIBagSlots` mappa törölhető. A `/bagslots` parancs továbbra is működik.

Telepítés: másold az `EllesmereUIBagCleaner` mappát az `Interface\AddOns` mappába. Kell hozzá az
**EllesmereUI** és az **EllesmereUIDworak** (ez hozza létre a "Dworak" szekciót). Beállítások: EllesmereUI panel → **Dworak** → **Bag Cleaner**,
vagy `/bagcleaner`.

| Kattintás | Hatás |
|---|---|
| Bal klikk | törlés (szürke/fehér azonnal; zöldtől felfelé kurzorra kerül, a játék rákérdez; quest tárgynál kétszer) |
| Bal klikk nyitott vendornál | eladás (vendornál a törlés Ctrl + bal klikk) |
| Jobb klikk | Ignore List (soha többé nem ajánlja fel; a középső klikk is ezt csinálja) |
| Shift + klikk | link a chatbe |

## Ahogy az EllesmereUI-t követi

- **Mappa és fájlnevek:** `EllesmereUI<Modul>` mappa, `EllesmereUI<Modul>_<Rész>.lua` fájlok,
  a TOC fejléce (`Group: EllesmereUI`, `Category`, ikon, verzió) a suite moduljaival egyezik.
- **Beállítások:** `EllesmereUI.Lite.NewDB` → az EllesmereUI profiljában tárolódnak
  (`EllesmereUIDB.profiles[<profil>].addons.EllesmereUIBagCleaner`), a profillal együtt mozognak.
- **Kinézet:** a szövegek az EllesmereUI globális fontját és outline-ját használják
  (Global Settings → Fonts). A háttér és a keret ugyanaz a csúszka + színválasztó minta, mint
  a Loot Feednél, a keretek pixel-pontosak (`EllesmereUI.PP`), a gombok és ablakok az
  EllesmereUI popup elemeit használják, a kiemelés a téma accent színe.
- **Láthatóság:** a közös EllesmereUI Visibility checklist (Always, Never, Mouseover, In Combat,
  Out of Combat, csoport és instance feltételek).
- **Mozgatás:** EllesmereUI Unlock Mode, "Dworak" csoport, "Bag Cleaner" elem.
- **Gyorsbillentyű:** a suite saját keybind gombja a beállításoldalon, és a Key Bindings
  menü **EllesmereUI** kategóriájában ("Bag Cleaner" → "Pick Up Cheapest Item").
- **Beállításoldal:** az EllesmereUI widget factory-ja (section header, DualRow, tooltipek,
  letiltott állapot "Requires ..." tooltippel), élő előnézet a fejlécben, Reset gomb a láblécben.
- **Regisztráció:** a "Dworak" szekciót az **EllesmereUIDworak** regisztrálja az EllesmereUI
  hivatalos Plugin API-jával (`EllesmereUI\PLUGINS_API.md`); a Bag Cleaner ebbe adja a sorát
  (`EllesmereUIDworak.AddModule`). Ezért egy EllesmereUI frissítés nem írja felül és nem töri el.

## Fájlok

```
EllesmereUIBagCleaner/
  EllesmereUIBagCleaner.toc          betöltési sorrend
  Bindings.xml                     a gyorsbillentyű (a WoW automatikusan betölti)
  EllesmereUIBagCleaner.lua          profil adatbázis, alapértékek, közös segédek
  EllesmereUIBagCleaner_Prices.lua   aukciós árak: saját Scan Prices, Auctionator, TSM
  EllesmereUIBagCleaner_Bar.lua      scan, rendezés, a sáv, kattintások, láthatóság, Unlock Mode
  EllesmereUIBagCleaner_Ignore.lua   az Ignore List ablak
  EllesmereUIBagCleaner_Options.lua  a beállításoldal és a "Bag Cleaner" sor a "Dworak" szekcióban
```

Új beállítás hozzáadása: alapérték az `EllesmereUIBagCleaner.lua` `profile` táblájába, egy sor
az `_Options.lua` megfelelő szekciójába (`Toggle`, `Slider`, `Bind`), a használat a `_Bar.lua`-ban
`Get("kulcs")`. A szekció helye (`"top"` / `"bottom"`) és neve az `EllesmereUIDworak.lua`
elején állítható.

Ami a Naowh-hoz képest kimaradt: a Scrap Marker "+N" számláló (a Naowh egy másik funkciója).
A BiS-védelem csak akkor működik, ha a Naowh Forever is fut.
