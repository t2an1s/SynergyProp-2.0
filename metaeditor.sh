#!/usr/bin/env bash
set -euo pipefail

# MetaEditor path inside the working bottle
METAEDITOR="$HOME/Library/Application Support/CrossOver/Bottles/MetaTrader 5/drive_c/Program Files/MetaTrader 5/metaeditor64.exe"
WINE="/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"
WINEPREFIX="$HOME/Library/Application Support/CrossOver/Bottles/MetaTrader 5"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
shopt -s nullglob
mq5_files=("$PROJECT_DIR"/*.mq5)

[[ ${#mq5_files[@]} -gt 0 ]] || { echo "❌ No .mq5 files found in $PROJECT_DIR"; exit 1; }

for mq5 in "${mq5_files[@]}"; do
  log="${mq5%.mq5}.log"
  echo "→ Compiling $(basename "$mq5")"
  WINEPREFIX="$WINEPREFIX" "$WINE" "$METAEDITOR" /compile:"$mq5" /log:"$log"
  grep -q "0 error" "$log" || { echo "❌ Errors in $(basename "$mq5") (see $log)"; exit 2; }
done

echo "✅ All MQ5 sources compiled successfully."
