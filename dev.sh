#!/usr/bin/env bash
# Fast build+run for iterative development.
# Uses pde2java.py to preprocess Processing syntax, targets Java 8,
# runs via PApplet.main. Requires a JDK 8+ on PATH and Python 3.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
LIB="$ROOT/lib"
JAVAC="javac"
JAVAW="java"
BUILD="$ROOT/build"
CP="$LIB/core.jar;$LIB/controlP5.jar;$LIB/GameControlPlus.jar;$LIB/serial.jar;$LIB/Sprites.jar;$LIB/jssc.jar"
MAIN="wheel_control_v3"

cd "$ROOT"
# kill any running instance so the build dir isn't locked
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='javaw.exe'\" | Where-Object { \$_.CommandLine -like '*wheel_control*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1 || true
sleep 1
rm -rf "$BUILD"; mkdir -p "$BUILD"

python pde2java.py "$ROOT" "wheel_control_v2.pde" "$MAIN.java" >/dev/null
cp "$ROOT/$MAIN.java" "$BUILD/$MAIN.java"

"$JAVAC" --release 8 -nowarn -cp "$CP" -d "$BUILD" "$BUILD/$MAIN.java" 2> "$BUILD/errors.txt" || { echo "=== COMPILE FAILED ==="; grep -E 'error:' "$BUILD/errors.txt" | head -40; exit 1; }
echo "=== COMPILE OK ==="
if [ "$1" = "run" ]; then
  "$JAVAW" -Djava.library.path="$LIB" -cp "$CP;$BUILD" processing.core.PApplet "$MAIN" &
  echo "launched pid $!"
fi
