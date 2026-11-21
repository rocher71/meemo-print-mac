#!/bin/bash
# Print a PDF on a MEEMO HTP-431 over Bluetooth, one page at a time.
# Usage: print_pdf.sh file.pdf [pages: all | 3 | 1-3 | 1,4,6-8]
# Env:   VALIDATE=1  check everything and print the sheet count, send nothing
#        DRY=1       build the print data but do not send it
#        MEEMO_ADDR  Bluetooth address (78-6a-...) to use instead of auto-detecting the paired "HTP-..." device
# Exit:  2 bad page spec · 3 driver missing · 4 Rosetta missing · 5 printer not paired
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
H="$DIR/helper"
# The app bundles the two vendor driver files it needs; a source checkout falls back to an installed QY Printer driver.
PPD="$DIR/driver/M832.ppd"   # 300dpi. M08F.ppd is 203dpi and prints too small.
FILTER="$DIR/driver/rastertoM08F"
[ -x "$FILTER" ] || { PPD=/Library/Printers/PPDs/Contents/Resources/M832.ppd; FILTER=/usr/libexec/cups/filter/rastertoM08F; }
LOG="$HOME/Library/Logs/MEEMOPrint.log"

if defaults read -g AppleLanguages 2>/dev/null | sed -n 2p | grep -q ko; then KO=1; else KO=0; fi
t() { if [ "$KO" = 1 ]; then echo "$1"; else echo "$2"; fi; }
fail() { t "$2" "$3" >&2; exit "$1"; }

[ -f "$PPD" ] && [ -x "$FILTER" ] || fail 3 "프린터 드라이버(QY Printer)가 설치되어 있지 않아요." "The printer driver (QY Printer) is not installed."
# The vendor driver is Intel-only, so Apple Silicon Macs need Rosetta.
arch -x86_64 /usr/bin/true 2>/dev/null || fail 4 "Rosetta가 설치되어 있지 않아요." "Rosetta is not installed."

PDF="$1"; SPEC="${2:-all}"
PAGES=$("$H" pages "$PDF")
LIST=()
if [ -z "${SPEC// /}" ] || [ "$SPEC" = "all" ]; then
  for ((i=1; i<=PAGES; i++)); do LIST+=("$i"); done
else
  IFS=',' read -ra PARTS <<< "${SPEC// /}"
  for part in "${PARTS[@]}"; do
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then a=$((10#${BASH_REMATCH[1]})); b=$((10#${BASH_REMATCH[2]}))
    elif [[ "$part" =~ ^[0-9]+$ ]]; then a=$((10#$part)); b=$a
    else fail 2 "쪽 지정 형식이 이상해요: '$part' (예: 3, 1-3, 1,4,6-8)" "Can't read the page range '$part' (examples: 3, 1-3, 1,4,6-8)"; fi
    if (( a < 1 || b > PAGES || a > b )); then fail 2 "1~${PAGES}쪽 사이로 지정해 주세요: '$part'" "Pages must be between 1 and ${PAGES}: '$part'"; fi
    for ((i=a; i<=b; i++)); do LIST+=("$i"); done
  done
fi
N=${#LIST[@]}

# ponytail: picks the first paired device named "HTP-...". Add a chooser if people own two, or other models get support.
ADDR="${MEEMO_ADDR:-$("$H" devices | awk -F'\t' '!f && $2 ~ /^HTP-/ {print $1; f=1}')}"
[ -n "$ADDR" ] || fail 5 "페어링된 프린터를 찾지 못했어요. 시스템 설정 > 블루투스에서 HTP-431을 먼저 연결해 주세요." "No paired printer found. Connect the HTP-431 in System Settings > Bluetooth first."

[ "${VALIDATE:-}" = 1 ] && { echo "$N"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "$(date '+%F %T') start: $PDF ($SPEC) -> $ADDR" >> "$LOG"
k=0
for i in "${LIST[@]}"; do k=$((k+1))
  /usr/sbin/cupsfilter -p "$PPD" -m application/vnd.cups-raster -o PageSize=A4 -o page-ranges="$i" "$PDF" > "$TMP/p.ras" 2>/dev/null
  "$H" job "$FILTER" "$PPD" "$TMP/p.ras" "$TMP/p.bin" 2>>"$LOG"
  [ "${DRY:-}" = 1 ] && { echo "dry page $i: $(wc -c < "$TMP/p.bin") bytes"; continue; }
  # HOLD: seconds to keep the Bluetooth link open after the last byte. Raise it if pages come out cut off.
  HOLD="${HOLD:-6}" "$H" send "$ADDR" < "$TMP/p.bin" >/dev/null 2>>"$LOG" \
    || fail 1 "프린터에 연결하지 못했어요. 프린터 전원을 껐다 켜고 다시 해 보세요." "Couldn't reach the printer. Turn it off and on, then try again."
  echo "$(date '+%T') ${k}/${N} (page ${i}) sent" >> "$LOG"
done
echo "$(date '+%F %T') done (${N} sheets)" >> "$LOG"
echo "$N"
