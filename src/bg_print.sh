#!/bin/bash
# Called by the app: print in the background, then tell the user how it went. Usage: bg_print.sh file.pdf pages
DIR="$(cd "$(dirname "$0")" && pwd)"
if defaults read -g AppleLanguages 2>/dev/null | sed -n 2p | grep -q ko; then KO=1; else KO=0; fi
t() { if [ "$KO" = 1 ]; then echo "$1"; else echo "$2"; fi; }
# Text goes in as an argument, never spliced into the script, so odd characters in file names can't break it.
say() { /usr/bin/osascript -e 'on run a' -e "$1" -e 'end run' "$2"; }

if out=$("$DIR/print_pdf.sh" "$1" "$2" 2>&1); then
  n=$(echo "$out" | tail -1)
  say 'display notification (item 1 of a) with title "MEEMO Print"' "$(t "${n}장 인쇄 완료" "Printed ${n} sheet(s)")"
else
  say 'display dialog (item 1 of a) buttons {"OK"} default button 1 with title "MEEMO Print"' \
    "$(t "인쇄 실패" "Printing failed"): $(echo "$out" | tail -1)"
fi
