# Station spec (what Jamie has decided)

This file is the record of owner decisions for the warehouse PC build. Read it before changing SG-Setup.ps1. Add a dated line when a decision changes. No secrets here.

## Standing rules
- The goal is to manage the PCs from Google Workspace. Chrome settings belong in the Admin console; the script only carries what Google cannot do on Windows.
- Never block, remove or change something staff rely on without listing it for Jamie first.
- No questions during setup. Jamie only types the station name.
- Changes are published as soon as they are made. PCs pick them up at 3:30 AM or 10 minutes after a restart.

## Decisions 2026-11-17
- The script approach was wrong for the goal: Workspace is to manage the PCs. No new features go into the script. Handoff document written for moving management into the Admin console.
- Order of work: settle the hello@thinkliquor.com warehouse stations first. Engraving and design PCs go back to their original login and setup and are rebuilt later.
- v60 rolls back Engraving2 only (serial MJ0G44E0) on the nightly update: every hello* login that v39-v59 switched off is put back, every Chrome setting the script wrote on the PC is removed (enrollment and Chrome Remote Desktop stay), a roll-back report is left on the shared desktop, and the PC is put on hold (HKLM\SOFTWARE\SGSetup Hold=1) so later updates skip it. Not undone: uninstalled programs, taskbar and theme changes, SGAdmin.
- On every other PC the v60 nightly update records the version and changes nothing.
- Engraving1 is in use. Do not change it until Jamie decides, after Engraving2 is checked. Back up its current settings first.
- Design1 and Printing3 never ran the setup, so there is nothing to roll back. Printing2 ran only the Nov 4 build; if it does receive the update it records v60 and changes nothing.

- v61 (same evening): the Engraving2 roll-back is switched off. Jamie believes the Lenovo (MJ0G44E0) may be Engraving1, the PC in use. No PC is changed by the nightly update until the serial of the broken engraving PC is read from its sticker and confirmed.
- v62 (same evening): Jamie confirmed MJ0G44E0 (Lenovo ThinkCentre, info@) is Engraving2. The roll-back from v60 is switched back on for that one PC.
- CORRECTION Nov 20 2026: Num Lock must be ON at startup on every PC. Jamie documented this herself in 2023 ("number lock" doc in the shared Drive). Builds v1-v62 of this script wrote the opposite value and overrode her fix, so staff had to press Num Lock before typing a PIN. v63 sets it ON at the sign-in screen, for every account already on the PC, and for accounts added later. Caps Lock stays OFF (barcode scanners).

## Station groups
- Warehouse stations (sign in as hello@thinkliquor.com): Pack1-4, Basket1-2, Production2. All identical.
- Design stations (sign in as info@spiritedgifts.com): Engraving1 (Dell tower), Engraving2 (Lenovo ThinkCentre), Printing2, Printing3, Design1. Different rules: Edge stays, Dropbox and fonts needed, Corel licensing open. Do not touch Printing3 or Reyshine's PC.
- Admin stations: Admin1, Admin2. Looser rules.
- Scanners and tablets (Android): one shared account, devices@thinkliquor.com, OU "Scanners and Tablets", Gmail/Calendar/Drive off.

## Names
- Title Case, no leading zero. Assigned by serial number in names.txt. Pack3 serial still unknown (2026-11-10).

## Every warehouse station (2026-11-10)
- Keep: Chrome (default), ShipStation Connect, IPEVO Visualizer, Slack, Ditto, CCleaner, Xbox, Webroot, Chrome Remote Desktop.
- Remove: Edge browser (blocked), AnyDesk, OneDrive, Mail, Snip & Sketch, Firefox, OKIOCAM, manufacturer bloatware.
- Chrome: bookmarks, passwords, history and autofill sync from hello@. Extensions blocked except extensions-allow.txt; the junk set on Production2 must never be re-enabled. Jamie picks the keep list from the 12 in the hello@ account (label resizer is one).
- Look: light mode, night light off, Start in the middle with search box, same wallpaper and icons on every PC, Num Lock off, screen stays on 60 minutes.
- Printers: Gabriel (192.168.10.31) and Angelina (192.168.10.172) added by IP. Station printers are USB. No default printer is assigned yet. Arkscan label driver and a Canon driver are needed on all (models to be confirmed by Jamie).
- Card printer Chrome extension: left alone, not relied on. Order flow and kiosk printing are undecided.
- ShipStation Connect: installed, nobody signs in until Jamie decides new vs existing account.

## Decisions 2026-11-10 (late)
- Extensions allowed: Tampermonkey, Tango, Imageye, Save Image As PNG, and two unknown delisted ones kept as label-resizer candidates. NOT allowed: Linnworks Gift Automation, QR Code Maker, Office Editing, Google Docs Offline. Junk set on Production2 stays blocked; remove it for good once the allow list is confirmed working.
- AntiMicro: on every PC, left as is. Whether it stays as the method is undecided; do not block or promote it.
- ActivTrak: not wanted. Removed if found.
- Webroot and CCleaner: on all stations.
- Canon PIXMA by station: TS302 = Pack3, Production2. TS302a = Printing2, Basket1. TS202 = Pack1, Pack2. Drivers go on all.
- Label printers: Arkscan 2054A. Driver: https://www.arkscan.com/images/products/2054A/2054A_Seagull_Printer_Driver_4BARCODE_7.4.3_M-1.exe (download page https://www.arkscan.com/technical-support/download).
- Barcode scanners: one or two on every PC, typing as a keyboard. SKUs are case-sensitive and leading zeros must survive. Caps Lock is forced off at sign-in. Scanner-side settings need the scanner models.
- Print routing wanted (not built): cards and Drive documents to the Canon, shipping labels to the label printer, Finale product labels to the barcode printer, without staff switching printers. One PC also prints Avery labels on its own Zebra. The old method was the card extension plus Chrome kiosk printing; Jamie says it has not worked for 8 months and needs a proper kiosk setup, undecided until order flow is decided.

## Decisions 2026-11-10 (morning)
- Chrome settings now live in the Google Admin console for Warehouse Devices (20 settings plus the extension block and allow list), and Policy precedence there is set so the console overrules what this script writes. The script still writes its Chrome settings; removing them is the next build.
- Webroot: 5 more seats bought on a second keycode. v58 installs Webroot with it on any PC that has none. Owner approved keeping that keycode in the script.
- Status report (v59): each run writes one line (build, PC name, serial, Webroot yes/no, SGAdmin yes/no, remote access yes/no, time) where the Admin console shows it per PC: Chrome browser > Managed browsers > the PC > Applied browser policies > SGStationStatus.
- Gift-card printing (Ctrl+M) has not worked for 8 months; rebuild waits on the order-flow decision. Not a test step.

## Open
- Arkscan driver staging is in v57 but untested on a PC (unpack switch /x and pnputil staging come from Seagull docs and research, medium confidence). Canon PIXMA: no script step; Windows Update is expected to install on USB plug-in; Canon does not support silent installs.
- Page resizer found: "Page Sizer by Adam Natad", a Google Docs add-on on the hello@ account (also "Labelmaker"). It lives in Docs > Extensions, not in Chrome, and was never removed.
- Speed check per PC, and a way to report results back.
- Webroot seat count.
- Why bookmarks do not show on the PCs although the account still holds them.
