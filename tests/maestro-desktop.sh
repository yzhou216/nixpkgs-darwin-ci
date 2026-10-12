#!/usr/bin/env bash
# Smoke tests for maestro-desktop.  The first argument is the package output
# and the second is a directory that receives logs and screenshots.

set -euo pipefail

out=$1
artifacts=$2
app=$out/Applications/Maestro.app
status=0

echo "::group::Code signatures"
codesign --display --verbose=2 "$app" 2>&1 || true
codesign --verify --deep --strict --verbose=2 "$app" 2>&1 || echo "Bundle signature does not verify"
find "$app" -name '*.node' -exec file {} +
echo "::endgroup::"

echo "::group::maestro-cli"
"$out/bin/maestro-cli" --version || status=1
echo "::endgroup::"

echo "::group::Native modules"
script=$(mktemp -d)/native-modules.js
cat >"$script" <<'EOF'
const path = require('path');
const modules = path.join(process.argv[2], 'node_modules');

const Database = require(path.join(modules, 'better-sqlite3'));
const db = new Database(':memory:');
console.log('better-sqlite3: SQLite', db.prepare('select sqlite_version() as v').get().v);
db.close();

const { Entry } = require(path.join(modules, '@napi-rs/keyring'));
console.log('@napi-rs/keyring: Entry is a', typeof Entry);

const pty = require(path.join(modules, 'node-pty'));
const term = pty.spawn('/bin/sh', ['-c', 'echo "node-pty: spawned $0"', 'sh'], {});
let output = '';
term.onData((data) => {
  output += data;
});
term.onExit(({ exitCode }) => {
  process.stdout.write(output);
  process.exit(exitCode);
});
EOF
ELECTRON_RUN_AS_NODE=1 "$app/Contents/MacOS/Maestro" "$script" "$app/Contents/Resources/app.asar" || status=1
echo "::endgroup::"

# Stops every process running from the app bundle, including helpers.
stop_app() {
  pkill -f "$app/Contents" || true
  for _ in $(seq 30); do
    pgrep -f "$app/Contents" >/dev/null || return 0
    sleep 1
  done
  pkill -9 -f "$app/Contents" || true
}

# Takes a screenshot after the app has had time to settle, checks that the
# given process is still alive, and then stops the app.
check_running() {
  local name=$1
  local pid=$2

  sleep 45
  screencapture -x "$artifacts/$name.png" || echo "screencapture failed"
  if kill -0 "$pid" 2>/dev/null; then
    echo "Maestro is still running after 45 seconds"
  else
    echo "Maestro exited early"
    status=1
  fi
  stop_app
}

echo "::group::Launch through the wrapper"
"$out/bin/maestro-desktop" >"$artifacts/wrapper.log" 2>&1 &
check_running wrapper $!
cat "$artifacts/wrapper.log"
echo "::endgroup::"

echo "::group::Launch through LaunchServices"
open -W --stdout "$artifacts/open.stdout.log" --stderr "$artifacts/open.stderr.log" "$app" &
check_running launchservices $!
cat "$artifacts/open.stdout.log" "$artifacts/open.stderr.log" 2>/dev/null || true
echo "::endgroup::"

cp -R "$HOME/Library/Application Support/Maestro/logs" "$artifacts/maestro-logs" 2>/dev/null || true
find "$HOME/Library/Logs/DiagnosticReports" -name 'Maestro*' -exec cp {} "$artifacts/" \; 2>/dev/null || true

exit "$status"
