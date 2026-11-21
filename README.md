# MEEMO Print for Mac

Print PDFs from a Mac to a **MEEMO HTP-431** A4 thermal printer over Bluetooth.

The printer's official Mac driver installs fine, but printing with ⌘P over Bluetooth never finishes: the job sits in the queue and the printer does nothing. MEEMO Print is a small drag-and-drop app that works around that.

**[Download and setup guide (English / 한국어)](https://rocher71.github.io/meemo-print-mac/)**

## Use it

1. Install the official Mac driver that came with your printer (QY Printer).
2. Pair the printer in System Settings > Bluetooth. It shows up as `HTP-431`.
3. Download [MEEMO-Print.zip](https://github.com/rocher71/meemo-print-mac/releases/latest/download/MEEMO-Print.zip), unzip it, and move **MEEMO Print** to Applications.
4. Drag a PDF onto the app icon. Print everything or pick pages (`3`, `1-3`, `1,4,6-8`).

The app is not notarized by Apple, so the first launch needs one extra step: open it once, then go to System Settings > Privacy & Security and click **Open Anyway**. The [setup guide](https://rocher71.github.io/meemo-print-mac/) walks through this.

Each page takes about a minute. The app's messages are in Korean when the Mac's language is Korean and in English otherwise.

## Requirements

- macOS 12 or later, Apple Silicon or Intel
- MEEMO HTP-431. Other models are untested.
- The vendor driver, QY Printer 1.6.2. It is not included here.
- Rosetta on Apple Silicon Macs, because the vendor driver is Intel-only. The app offers to install it.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Blank page comes out | The thermal paper is upside down. Flip it. |
| "Couldn't reach the printer" | Turn the printer off and on, then try again. |
| "No paired printer found" | Pair `HTP-431` in System Settings > Bluetooth. |
| A stuck ⌘P job is holding the printer | Delete the job, remove the printer from Printers & Scanners, and power-cycle the printer. |

The log is at `~/Library/Logs/MEEMOPrint.log`.

## How it works

The vendor's CUPS filter (`rastertoM08F`) asks the printer for its status (firmware, paper, battery) before it sends a page and waits for the answers. The macOS Bluetooth print backend never delivers those answers, so the filter waits forever.

MEEMO Print runs the same filter itself and supplies the answers a healthy HTP-431 gives, then sends the finished data straight to the printer:

1. `cupsfilter` turns one PDF page into a 300 dpi CUPS raster, using the driver's `M832.ppd`.
2. `helper job` runs `rastertoM08F` with the CUPS back-channel and side-channel connected to itself, and replies to the status queries.
3. `helper send` writes the result to the printer over Bluetooth RFCOMM channel 1.

Because the status replies are canned, the app cannot tell you when the printer is out of paper or low on battery.

| File | Role |
| --- | --- |
| `src/droplet.applescript` | The app: drag-and-drop and dialogs |
| `src/print_pdf.sh` | The pipeline, one page at a time |
| `src/bg_print.sh` | Runs the pipeline in the background and reports the result |
| `src/helper.swift` | Page count, paired devices, driver runner, Bluetooth sender |

## Command line

```sh
R="/Applications/MEEMO Print.app/Contents/Resources"
"$R/print_pdf.sh" file.pdf            # all pages
"$R/print_pdf.sh" file.pdf 1,4,6-8    # some pages
DRY=1 "$R/print_pdf.sh" file.pdf      # build the print data without sending it
```

`MEEMO_ADDR=78-6a-...` picks a specific printer instead of the first paired `HTP-` device. `HOLD=10` keeps the Bluetooth link open longer after each page; raise it if pages come out cut off.

## Build

Needs the Xcode command line tools.

```sh
./build.sh    # -> build/MEEMO Print.app and build/MEEMO-Print.zip
```

To sign and notarize, set `SIGN_ID` and `NOTARY_PROFILE`; see the top of `build.sh`.

## License

[MIT](LICENSE). Not affiliated with MEEMO or the driver's vendor. The vendor driver is their property and is not distributed here.
