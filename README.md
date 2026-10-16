# EllesmereUI-Bag_Cleaner_Advanced
<img width="268" height="129" alt="{AB9B282F-F63D-4180-82B2-C477DA3AD887}" src="https://github.com/user-attachments/assets/e7ca8548-377c-4d51-93e6-94325f475068" />
<img width="1308" height="949" alt="{2427892A-BB00-4D18-BB48-AFFBDB3A6FB5}" src="https://github.com/user-attachments/assets/189e69af-b959-4c95-ad5b-1e53f48cfef0" />
<img width="1323" height="961" alt="{92152985-CB2E-4E3A-A6C6-98B1EDB49415}" src="https://github.com/user-attachments/assets/2871020f-e677-44d2-8e3d-0629a6c63729" />
<img width="1305" height="955" alt="{C6C8D678-7A81-4C92-A489-1D568C3681DA}" src="https://github.com/user-attachments/assets/297db9e4-7399-47ac-afc4-f680cb3ae54b" />
<img width="1315" height="954" alt="{17EB76E3-DDAE-4C27-8402-8A03EABDEF09}" src="https://github.com/user-attachments/assets/5a804b56-12fe-41d3-af72-8b1b8c970950" />


A small bar that shows the cheapest items in your bags, so you can make room in one click.
Built as a module for [EllesmereUI](https://github.com/EllesmereGaming/EllesmereUI): it looks,
saves and is configured exactly like the suite's own modules.

## Requirements

- **World of Warcraft: Forever** (Interface 16001). The TOC also lists the current Retail
  interface versions, but the module is developed and tested on Forever.
- **EllesmereUI** (tested with v9.5.4)
- **EllesmereUI Dworak** (`EllesmereUIDworak`): creates the "Dworak" section in the EllesmereUI
  panel that Bag Cleaner's settings live in.
- Optional: **Auctionator** or **TradeSkillMaster** for auction prices.

## Installation

1. Copy the `EllesmereUIBagCleaner` and `EllesmereUIDworak` folders into
   `World of Warcraft\_classic_beta_\Interface\AddOns\` (next to `EllesmereUI`).
2. Log in (or `/reload`).
3. Open the settings: EllesmereUI panel → **Dworak** → **Bag Cleaner**, or type `/bagcleaner`.

Do not rename the folders: the addons refer to each other by folder name.

## Using the bar

| Action | Result |
|---|---|
| **Left-click** | Delete the item. Poor and Common items are deleted at once; Uncommon and better go on the cursor and the game asks for confirmation. Items an unfinished quest still needs take a second click within 5 seconds. |
| **Left-click** at an open vendor | Sell the item (**Ctrl + left-click** deletes there). |
| **Right-click** (or middle-click) | Add the item to the Ignore List: it is never offered again. |
| **Shift + click** | Link the item in chat. |
| Hover the free-slot counter | Free slots per bag. |
| **Stack** button | Combines part-filled stacks of the same item to free slots. Nothing is deleted. |

The header shows how many bag slots are free. It turns orange below 10% and red when the bags are full.

### What gets offered

- Items are sorted by value, cheapest first. With **Count Auction Prices** on, an item worth more at
  the auction house is valued at its auction price instead of its vendor price.
- **Never offered** while *Protect Needed Items* is on: reagents, ammo, quivers, quest items, keys,
  items in an equipment set.
- Items an unfinished quest in your log still asks for go to the end of the list.
- The reagent bag is ignored: its items are not offered and its empty slots do not count as free
  (optional: *Count Reagent Bag*).

### Auction prices

Sources, first one that knows the item wins:

1. Bag Cleaner's own scan: a **Scan Prices** button on the auction house reads every listing and keeps
   the lowest buyout per item, per realm and faction (Blizzard allows one full scan every 15 minutes).
2. Auctionator
3. TradeSkillMaster (`dbminbuyout`)

## Settings

All settings are stored in the active EllesmereUI profile. The settings page has a live preview and
its own **Search Module Settings** box.

| Section | Settings |
|---|---|
| **Bag Cleaner** | Enable Bag Cleaner · Ignore List · Visibility (the shared EllesmereUI visibility checklist: Always, Never, Mouseover, In Combat, Out of Combat, group and instance conditions) · Show When Bags Are Full · Only With Free Slots Below · Pick Up Cheapest Item (key binding) |
| **Offered** | Items Shown · Highest Quality Offered · Grey Items First · Outlevelled Food & Potions First · Count Auction Prices · Protect Needed Items · Scan Prices Button |
| **Layout** | Icon Size · Icon Spacing · Highlight Cheapest · Cheapest Icon Size · Grow Direction · Text Size |
| **Display** | Show Free Slots · Show Stack Button · Count Reagent Bag · Show Prices · Quality Borders · Glow Cheapest · Glow Style · Flash When Full · Background (opacity + color) · Border Size (+ color) |
| **Tooltips** | Vendor Price · Auction Price · Delete Hint · Ignore Hint |

- **Move the bar** in EllesmereUI's Unlock Mode ("Dworak" group, "Bag Cleaner").
- **Fonts** follow EllesmereUI → Global Settings → Fonts.
- The glow, the Stack button and other highlights follow the **UI Accent Color**, live.
- **Key binding:** *Pick Up Cheapest Item* puts the cheapest item on your cursor. Set it on the
  settings page or under Key Bindings → EllesmereUI → Bag Cleaner.

## Slash commands

- `/bagcleaner` opens the settings page.

## Files

```
EllesmereUIBagCleaner/
  EllesmereUIBagCleaner.toc          load order
  Bindings.xml                       the Pick Up Cheapest Item key binding
  EllesmereUIBagCleaner.lua          profile database, defaults, helpers
  EllesmereUIBagCleaner_Prices.lua   auction prices (own scan, Auctionator, TSM)
  EllesmereUIBagCleaner_Bar.lua      scan, sorting, the bar, clicks, visibility, Unlock Mode, glow
  EllesmereUIBagCleaner_Ignore.lua   the Ignore List window
  EllesmereUIBagCleaner_Options.lua  the settings page and its entry in the Dworak section
```

The settings page is registered through EllesmereUI's official Plugin API
(`EllesmereUI\PLUGINS_API.md`), so EllesmereUI updates neither overwrite nor break it.

## Credits

- **EllesmereUI** by Ellesmere: the framework, widgets and look this module is built on.
