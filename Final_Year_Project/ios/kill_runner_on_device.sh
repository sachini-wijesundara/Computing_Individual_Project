#!/usr/bin/env bash
# Best-effort: stop Runner so Xcode / flutter run won't show "Replace 'Runner'?" when a
# previous debug session left the app (or debugger) attached. Safe to run when nothing is running.
# Usage: ./kill_runner_on_device.sh [device_udid]
# Env: IOS_DEVICE_ID (default UDID if arg omitted), IOS_RUNNER_BUNDLE_ID (default below).

set -u
BUNDLE_ID="${IOS_RUNNER_BUNDLE_ID:-com.example.virtualTryonMakeup}"
DEVICE="${1:-${IOS_DEVICE_ID:-}}"

terminate_pids_on_device() {
  local dev="$1"
  local tmp
  tmp="$(mktemp)"
  if ! xcrun devicectl device info processes --device "$dev" --json-output "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 0
  fi
  python3 - "$tmp" "$dev" "$BUNDLE_ID" <<'PY'
import json, subprocess, sys
path, dev, bundle = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

def walk(o, out):
    if isinstance(o, dict):
        bid = o.get("bundleIdentifier") or o.get("bundleID")
        if bid == bundle:
            pid = o.get("processIdentifier")
            if pid is None:
                pid = o.get("pid")
            if isinstance(pid, int):
                out.add(pid)
        for v in o.values():
            walk(v, out)
    elif isinstance(o, list):
        for x in o:
            walk(x, out)

pids = set()
walk(data, pids)
for pid in sorted(pids):
    subprocess.run(
        [
            "xcrun",
            "devicectl",
            "device",
            "process",
            "terminate",
            "--device",
            dev,
            "--pid",
            str(pid),
        ],
        capture_output=True,
    )
PY
  rm -f "$tmp"
}

pick_connected_device() {
  local tmp out
  tmp="$(mktemp)"
  if ! xcrun devicectl list devices --json-output "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    echo ""
    return 0
  fi
  out="$(python3 <<PY
import json, re, sys

with open("$tmp", "r", encoding="utf-8") as f:
    data = json.load(f)

uuid_re = re.compile(r"^[0-9A-F]{8}-[0-9A-F]{16}$|^[0-9]{25}$", re.I)

def walk_devices(o, found):
    if isinstance(o, dict):
        ident = o.get("identifier") or o.get("deviceIdentifier")
        conn = o.get("connectionProperties") or {}
        hw = o.get("hardwareProperties") or {}
        state = str(
            conn.get("tunnelState")
            or conn.get("pairingState")
            or ""
        ).lower()
        dtype = str(hw.get("deviceType") or hw.get("platform") or "").lower()
        if isinstance(ident, str) and uuid_re.match(ident):
            ok = "connected" in state or state in ("paired", "available")
            is_ios = "iphone" in dtype or "ipad" in dtype or "ipod" in dtype
            if ok and is_ios:
                found.append(ident)
        for v in o.values():
            walk_devices(v, found)
    elif isinstance(o, list):
        for x in o:
            walk_devices(x, found)

found = []
walk_devices(data, found)
if found:
    print(found[0])
else:
    def walk_fallback(o, found):
        if isinstance(o, dict):
            for k, v in o.items():
                if k in ("identifier", "deviceIdentifier") and isinstance(v, str) and uuid_re.match(v):
                    cp = o.get("connectionProperties") or {}
                    if str(cp.get("tunnelState", "")).lower() == "connected":
                        found.append(v)
                walk_fallback(v, found)
        elif isinstance(o, list):
            for x in o:
                walk_fallback(x, found)

    found2 = []
    walk_fallback(data, found2)
    print(found2[0] if found2 else "")
PY
)"
  rm -f "$tmp"
  echo "$out"
}

# Simulator: if a Simulator is booted with our app, stop it (no-op otherwise).
xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true

if [[ -z "$DEVICE" ]]; then
  DEVICE="$(pick_connected_device)"
fi

if [[ -n "$DEVICE" ]]; then
  terminate_pids_on_device "$DEVICE"
fi

exit 0
