#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage:
  start_rpc_bridge_local.sh

What this does:
  - Runs the PhoneAgent UI-test RPC server.
  - For physical devices (USB or Xcode "Connect via network"), starts a localhost-only forwarder
    so you can always connect to 127.0.0.1:45678 and the RPC port is not exposed to the LAN.
    It prefers the CoreDevice tunnel (*.coredevice.local) and falls back to USB via usbmux when available.

Requirements (physical device):
  - python3
  - An Apple Development signing certificate. Set PHONEAGENT_DEVELOPMENT_TEAM when
    certificates from multiple teams are installed.
  - (USB only) pip package: pymobiledevice3 (install into repo-root ./.venv)

Interactive selection:
  - This script is intentionally interactive. It will list iOS devices and simulators
    and prompt you to pick one by number.
  - Set PHONEAGENT_DEVICE_DISCOVERY_TIMEOUT to allow extra time for network devices.
USAGE
}

UDID=""
RPC_PORT="45678"
IS_SIMULATOR=0

pick_destination_interactive() {
  if [[ ! -e /dev/tty ]]; then
    echo "No TTY available for interactive selection (missing /dev/tty)." >&2
    exit 1
  fi

  local destinations
  if ! destinations="$(python3 - <<'PY'
import json
import os
import subprocess
import sys

try:
    timeout = int(os.environ.get("PHONEAGENT_DEVICE_DISCOVERY_TIMEOUT", "5"))
    if timeout < 1:
        raise ValueError("PHONEAGENT_DEVICE_DISCOVERY_TIMEOUT must be at least 1")

    output = subprocess.check_output(
        ["xcrun", "xcdevice", "list", "--timeout", str(timeout)],
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout + 5,
    )
    devices = json.loads(output)
    if not isinstance(devices, list):
        raise ValueError("xcdevice returned an unexpected device list")
except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, ValueError) as error:
    detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
    print(f"Unable to list available iOS devices and simulators: {detail}", file=sys.stderr)
    raise SystemExit(1)

physical_devices = []
simulators = []
seen_identifiers = set()

for device in devices:
    if not isinstance(device, dict) or device.get("available") is not True:
        continue

    platform = device.get("platform")
    is_simulator = device.get("simulator")
    if platform == "com.apple.platform.iphoneos" and is_simulator is False:
        destinations = physical_devices
        kind = "device"
    elif platform == "com.apple.platform.iphonesimulator" and is_simulator is True:
        destinations = simulators
        kind = "sim"
    else:
        continue

    name = device.get("name")
    identifier = device.get("identifier")
    if not isinstance(name, str) or not isinstance(identifier, str) or not name or not identifier:
        continue

    normalized_identifier = identifier.lower()
    if normalized_identifier in seen_identifiers or any(character.isspace() for character in identifier):
        continue
    seen_identifiers.add(normalized_identifier)

    display_name = "".join(character if character.isprintable() else " " for character in name)
    version = device.get("operatingSystemVersion")
    version = version.split(" ", 1)[0] if isinstance(version, str) and version else ""
    label = f"{display_name} ({version})" if version else display_name
    destinations.append((identifier, kind, label))

for identifier, kind, label in physical_devices + simulators:
    print(f"{identifier}\t{kind}\t{label}")
PY
)"; then
    exit 1
  fi

  local -a labels
  local -a ids
  local -a kinds
  local id kind label

  while IFS=$'\t' read -r id kind label; do
    [[ -n "$id" && -n "$kind" && -n "$label" ]] || continue
    labels+=("$label [$kind]")
    ids+=("$id")
    kinds+=("$kind")
  done <<<"$destinations"

  if ((${#ids[@]} == 0)); then
    echo "No available physical iOS devices or simulators found." >&2
    exit 1
  fi

  echo "Select destination:" >&2
  local i
  for i in "${!labels[@]}"; do
    printf '%d) %s\n' "$((i + 1))" "${labels[$i]}" >&2
  done

  local choice=""
  local default_choice="1"
  while true; do
    printf 'Enter number (1-%d) [default %s]: ' "${#ids[@]}" "$default_choice" >&2
    IFS= read -r choice </dev/tty || true

    if [[ -z "$choice" ]]; then
      choice="$default_choice"
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ids[@]} )); then
      UDID="${ids[$((choice - 1))]}"
      if [[ "${kinds[$((choice - 1))]}" == "sim" ]]; then
        IS_SIMULATOR=1
      fi
      break
    fi
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2;;
  esac
done

pick_destination_interactive

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  # Fallback for when git isn't available: this file lives at
  # <repo>/.agents/skills/phoneagent/scripts/start_rpc_bridge_local.sh.
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"
fi

if [[ ! -d "$REPO_ROOT/PhoneAgent.xcodeproj" ]]; then
  echo "Could not locate PhoneAgent.xcodeproj under: $REPO_ROOT" >&2
  echo "Run this script from a PhoneAgent repo checkout." >&2
  exit 1
fi

PYTHON="python3"
if [[ -x "$REPO_ROOT/.venv/bin/python" ]]; then
  PYTHON="$REPO_ROOT/.venv/bin/python"
fi

resolve_development_team() {
  if [[ -n "${PHONEAGENT_DEVELOPMENT_TEAM:-}" ]]; then
    printf '%s\n' "$PHONEAGENT_DEVELOPMENT_TEAM"
    return
  fi

  local -a teams=()
  local team
  while IFS= read -r team; do
    [[ -n "$team" ]] && teams+=("$team")
  done < <(
    security find-certificate -a -c "Apple Development" -p 2>/dev/null |
      openssl crl2pkcs7 -nocrl -certfile /dev/stdin 2>/dev/null |
      openssl pkcs7 -print_certs -noout 2>/dev/null |
      sed -nE 's/.*OU[[:space:]]*=[[:space:]]*([A-Z0-9]{10}).*/\1/p' |
      sort -u || true
  )

  if ((${#teams[@]} != 1)); then
    echo "Expected one Apple Development signing team; found ${#teams[@]}. Set PHONEAGENT_DEVELOPMENT_TEAM explicitly." >&2
    return 1
  fi

  printf '%s\n' "${teams[0]}"
}

FORWARD_PID=""
cleanup() {
  if [[ -n "${FORWARD_PID:-}" ]]; then
    kill "$FORWARD_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

DEVELOPMENT_TEAM=""
if ((!IS_SIMULATOR)); then
  DEVELOPMENT_TEAM="$(resolve_development_team)"
  echo "Using Apple Development team: $DEVELOPMENT_TEAM" >&2
fi

if ((IS_SIMULATOR)); then
  echo "Simulator detected; use RPC host 127.0.0.1:$RPC_PORT (wait for PHONEAGENT_RPC_READY ... in logs)" >&2
else
  echo "Physical device detected; starting localhost forward: 127.0.0.1:$RPC_PORT -> device:$RPC_PORT" >&2
  "$PYTHON" "$SCRIPT_DIR/forward_rpc_localhost.py" \
    --udid "$UDID" &
  FORWARD_PID="$!"

  # Give the forwarder a moment to bind; fail fast if it died (missing deps, port in use, etc).
  sleep 0.2
  kill -0 "$FORWARD_PID" 2>/dev/null || { echo "Port forwarder failed to start." >&2; exit 1; }

  echo "Port forwarder is listening on 127.0.0.1:$RPC_PORT (wait for PHONEAGENT_RPC_READY ... in logs)" >&2
fi

# Start the test-hosted JSON-RPC server via a single UI-test entrypoint.
XCODEBUILD_CODESIGN_ARGS=()
if ((IS_SIMULATOR)); then
  # Simulator builds don't need signing; disabling it avoids requiring a configured signing identity.
  XCODEBUILD_CODESIGN_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
else
  XCODEBUILD_CODESIGN_ARGS=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" -allowProvisioningUpdates)
fi

XCODEBUILD_ARGS=(
  xcodebuild
  test
  -project "$REPO_ROOT/PhoneAgent.xcodeproj"
  -scheme "PhoneAgent"
  -destination "id=$UDID"
  -only-testing:PhoneAgentUITests/PhoneAgent/testRPCBridge
)
if ((${#XCODEBUILD_CODESIGN_ARGS[@]})); then
  XCODEBUILD_ARGS+=("${XCODEBUILD_CODESIGN_ARGS[@]}")
fi

"${XCODEBUILD_ARGS[@]}"
