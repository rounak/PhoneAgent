#!/usr/bin/env python3
"""
PhoneAgent Android JSON-RPC bridge.

This script exposes a localhost-only newline-delimited JSON-RPC server that
mirrors the iOS RPC surface as closely as possible using adb + UiAutomator.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shutil
import socket
import subprocess
import threading
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple


DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 45678
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
COORD_RE = re.compile(
    r"\{\{\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\},\s*\{\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\}\}"
)
BOUNDS_RE = re.compile(r"\[(\-?\d+),(\-?\d+)\]\[(\-?\d+),(\-?\d+)\]")
PACKAGE_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$")


class RPCError(Exception):
    pass


def eprint(*args: object) -> None:
    print(*args, flush=True)


def _number_value(params: Dict[str, Any], key: str) -> float:
    if key not in params:
        raise RPCError(f"missing parameter '{key}'")
    value = params[key]
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError as exc:
            raise RPCError(f"parameter '{key}' must be a number") from exc
    raise RPCError(f"parameter '{key}' must be a number")


def _string_value(params: Dict[str, Any], key: str) -> str:
    if key not in params:
        raise RPCError(f"missing parameter '{key}'")
    value = params[key]
    if not isinstance(value, str):
        raise RPCError(f"parameter '{key}' must be a string")
    return value


def _read_png_dimensions(data: bytes) -> Optional[Tuple[int, int]]:
    if len(data) < 24 or not data.startswith(PNG_SIGNATURE):
        return None
    if data[12:16] != b"IHDR":
        return None
    width = int.from_bytes(data[16:20], byteorder="big", signed=False)
    height = int.from_bytes(data[20:24], byteorder="big", signed=False)
    return width, height


def _parse_coordinate_rect(coordinate: str) -> Tuple[float, float, float, float]:
    match = COORD_RE.fullmatch(coordinate.strip())
    if match is None:
        raise RPCError(f"coordinate must look like {{{{x, y}}, {{w, h}}}}; got '{coordinate}'")
    x, y, w, h = (float(match.group(i)) for i in range(1, 5))
    return x, y, w, h


def _format_rect(x: float, y: float, w: float, h: float) -> str:
    return f"{{{{{x:.1f}, {y:.1f}}}, {{{w:.1f}, {h:.1f}}}}}"


def _bounds_to_rect(bounds: str) -> Optional[Tuple[float, float, float, float]]:
    match = BOUNDS_RE.fullmatch(bounds.strip())
    if match is None:
        return None
    x1, y1, x2, y2 = (float(match.group(i)) for i in range(1, 5))
    width = max(0.0, x2 - x1)
    height = max(0.0, y2 - y1)
    return x1, y1, width, height


def _escape_adb_text(text: str) -> str:
    specials = set("\\\"'`()[]{}<>|;&*~$")
    out: list[str] = []
    for ch in text:
        if ch in (" ", "\t"):
            out.append("%s")
        elif ch in specials:
            out.append("\\" + ch)
        else:
            out.append(ch)
    return "".join(out)


def _chunk_text(text: str, chunk_size: int = 80) -> list[str]:
    if not text:
        return []
    return [text[i : i + chunk_size] for i in range(0, len(text), chunk_size)]


@dataclass
class AndroidDeviceBridge:
    serial: str
    adb_binary: str
    api_key: Optional[str] = None

    def _adb(
        self,
        *args: str,
        timeout: float = 20.0,
        binary: bool = False,
        check: bool = True,
    ) -> subprocess.CompletedProcess[bytes]:
        cmd = [self.adb_binary, "-s", self.serial, *args]
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False)
        if check and proc.returncode != 0:
            stderr = proc.stderr.decode("utf-8", errors="replace").strip()
            stdout = proc.stdout.decode("utf-8", errors="replace").strip()
            detail = stderr or stdout or f"exit={proc.returncode}"
            raise RPCError(f"adb command failed ({' '.join(cmd)}): {detail}")
        if binary:
            return proc
        return proc

    def _screen_size(self) -> Tuple[int, int]:
        proc = self._adb("shell", "wm", "size", timeout=8)
        out = proc.stdout.decode("utf-8", errors="replace")
        match = re.search(r"(\d+)\s*x\s*(\d+)", out)
        if not match:
            raise RPCError(f"failed to read screen size from: {out.strip()!r}")
        return int(match.group(1)), int(match.group(2))

    def _uiautomator_xml(self) -> str:
        self._adb("shell", "uiautomator", "dump", "/sdcard/window_dump.xml", timeout=12)
        proc = self._adb("exec-out", "cat", "/sdcard/window_dump.xml", timeout=12)
        raw = proc.stdout.decode("utf-8", errors="replace")
        idx = raw.find("<?xml")
        if idx != -1:
            raw = raw[idx:]
        if "<hierarchy" not in raw:
            raise RPCError("uiautomator dump did not return XML hierarchy")
        return raw.strip()

    def _format_tree(self, xml_text: str) -> str:
        try:
            root = ET.fromstring(xml_text)
        except ET.ParseError as exc:
            raise RPCError(f"failed to parse UI hierarchy XML: {exc}") from exc

        lines: list[str] = ["Hierarchy"]

        def walk(node: ET.Element, depth: int) -> None:
            if node.tag == "node":
                attrs = node.attrib
                class_name = attrs.get("class", "Node").split(".")[-1] or "Node"
                text = (attrs.get("text") or "").strip()
                desc = (attrs.get("content-desc") or "").strip()
                identifier = (attrs.get("resource-id") or "").strip()
                bounds = (attrs.get("bounds") or "").strip()
                clickable = (attrs.get("clickable") or "").strip()

                label = text or desc
                parts = [class_name]
                if label:
                    parts.append(f"label: {json.dumps(label)}")
                if desc and desc != label:
                    parts.append(f"value: {json.dumps(desc)}")
                if identifier:
                    parts.append(f"identifier: {json.dumps(identifier)}")
                rect = _bounds_to_rect(bounds)
                if rect is not None:
                    parts.append(f"frame: {_format_rect(*rect)}")
                if clickable == "true":
                    parts.append("clickable: true")

                lines.append(f"{'  ' * depth}{', '.join(parts)}")
                depth += 1

            for child in list(node):
                walk(child, depth)

        walk(root, 0)
        return "\n".join(lines)

    def _current_tree(self) -> str:
        xml = self._uiautomator_xml()
        return self._format_tree(xml)

    def _screen_png(self) -> bytes:
        proc = self._adb("exec-out", "screencap", "-p", timeout=15, binary=True)
        data = proc.stdout
        if not data.startswith(PNG_SIGNATURE):
            raise RPCError("device screencap did not return PNG bytes")
        return data

    def _input_text(self, text: str) -> None:
        if not text:
            return
        lines = text.split("\n")
        for line_index, line in enumerate(lines):
            for chunk in _chunk_text(line, chunk_size=80):
                escaped = _escape_adb_text(chunk)
                if escaped:
                    self._adb("shell", "input", "text", escaped, timeout=10)
            if line_index < len(lines) - 1:
                self._adb("shell", "input", "keyevent", "66", timeout=8)

    def _center_of_coordinate(self, coordinate: str) -> Tuple[int, int]:
        x, y, w, h = _parse_coordinate_rect(coordinate)
        cx = int(round(x + (w / 2.0)))
        cy = int(round(y + (h / 2.0)))
        return cx, cy

    def _foreground_package(self) -> Optional[str]:
        proc = self._adb("shell", "dumpsys", "window", "windows", timeout=12, check=False)
        text = proc.stdout.decode("utf-8", errors="replace")
        patterns = [
            r"mCurrentFocus=.*? ([A-Za-z0-9_.]+)/",
            r"mFocusedApp=.*? ([A-Za-z0-9_.]+)/",
        ]
        for pattern in patterns:
            match = re.search(pattern, text)
            if match:
                return match.group(1)
        return None

    def _launch_package(self, package: str) -> None:
        # First choice: resolve launcher activity and start it directly.
        resolved = self._adb(
            "shell", "cmd", "package", "resolve-activity", "--brief", package, timeout=10, check=False
        )
        if resolved.returncode == 0:
            lines = [line.strip() for line in resolved.stdout.decode("utf-8", errors="replace").splitlines() if line.strip()]
            component = next((line for line in reversed(lines) if "/" in line), None)
            if component:
                started = self._adb("shell", "am", "start", "-W", "-n", component, timeout=12, check=False)
                output = (
                    started.stdout.decode("utf-8", errors="replace")
                    + "\n"
                    + started.stderr.decode("utf-8", errors="replace")
                )
                if started.returncode == 0 and "Error:" not in output:
                    return

        # Fallback: monkey launcher event.
        monkey = self._adb(
            "shell",
            "monkey",
            "-p",
            package,
            "-c",
            "android.intent.category.LAUNCHER",
            "1",
            timeout=12,
            check=False,
        )
        output = (
            monkey.stdout.decode("utf-8", errors="replace")
            + "\n"
            + monkey.stderr.decode("utf-8", errors="replace")
        )
        if monkey.returncode != 0 or "No activities found to run" in output:
            raise RPCError(f"failed to open app '{package}': {output.strip()}")

    def handle(self, method: str, params: Dict[str, Any]) -> Tuple[Dict[str, Any], bool]:
        if method == "get_tree":
            return {"tree": self._current_tree()}, False

        if method == "get_screen_image":
            png = self._screen_png()
            payload: Dict[str, Any] = {
                "screenshot_base64": base64.b64encode(png).decode("ascii"),
            }
            dims = _read_png_dimensions(png)
            if dims is not None:
                payload["metadata"] = {"width": dims[0], "height": dims[1]}
            return payload, False

        if method == "get_context":
            tree = self._current_tree()
            png = self._screen_png()
            payload = {
                "tree": tree,
                "screenshot_base64": base64.b64encode(png).decode("ascii"),
            }
            dims = _read_png_dimensions(png)
            if dims is not None:
                payload["metadata"] = {"width": dims[0], "height": dims[1]}
            return payload, False

        if method == "tap":
            x = int(round(_number_value(params, "x")))
            y = int(round(_number_value(params, "y")))
            self._adb("shell", "input", "tap", str(x), str(y), timeout=8)
            return {"tree": self._current_tree()}, False

        if method == "tap_element":
            coordinate = _string_value(params, "coordinate")
            count = int(params.get("count", 1))
            long_press = bool(params.get("longPress", False))
            if count < 1:
                raise RPCError("count must be >= 1")
            x, y = self._center_of_coordinate(coordinate)
            if long_press:
                self._adb("shell", "input", "swipe", str(x), str(y), str(x), str(y), "550", timeout=10)
                effective_count = 1
            else:
                for _ in range(count):
                    self._adb("shell", "input", "tap", str(x), str(y), timeout=8)
                effective_count = count
            return {
                "coordinate": coordinate,
                "count": effective_count,
                "longPress": long_press,
                "tree": self._current_tree(),
            }, False

        if method == "enter_text":
            coordinate = _string_value(params, "coordinate")
            text = _string_value(params, "text")
            x, y = self._center_of_coordinate(coordinate)
            self._adb("shell", "input", "tap", str(x), str(y), timeout=8)
            time.sleep(0.2)
            self._input_text(text)
            self._adb("shell", "input", "keyevent", "66", timeout=8)
            return {"coordinate": coordinate, "tree": self._current_tree()}, False

        if method == "scroll":
            x = int(round(_number_value(params, "x")))
            y = int(round(_number_value(params, "y")))
            distance_x = int(round(_number_value(params, "distanceX")))
            distance_y = int(round(_number_value(params, "distanceY")))
            width, height = self._screen_size()
            x2 = min(max(x + distance_x, 0), width - 1)
            y2 = min(max(y + distance_y, 0), height - 1)
            self._adb("shell", "input", "swipe", str(x), str(y), str(x2), str(y2), "220", timeout=10)
            return {"tree": self._current_tree()}, False

        if method == "swipe":
            x = int(round(_number_value(params, "x")))
            y = int(round(_number_value(params, "y")))
            direction = _string_value(params, "direction").lower().strip()
            if direction not in {"up", "down", "left", "right"}:
                raise RPCError("direction must be one of: up, down, left, right")
            width, height = self._screen_size()
            span = max(180, min(width, height) // 2)
            x2, y2 = x, y
            if direction == "up":
                y2 = y - span
            elif direction == "down":
                y2 = y + span
            elif direction == "left":
                x2 = x - span
            elif direction == "right":
                x2 = x + span
            x2 = min(max(x2, 0), width - 1)
            y2 = min(max(y2, 0), height - 1)
            self._adb("shell", "input", "swipe", str(x), str(y), str(x2), str(y2), "220", timeout=10)
            return {"tree": self._current_tree()}, False

        if method == "open_app":
            package = (
                str(params.get("bundle_identifier") or params.get("package_name") or "").strip()
            )
            if not package:
                raise RPCError("bundle_identifier is required")
            if PACKAGE_RE.fullmatch(package) is None:
                raise RPCError(f"bundle_identifier '{package}' is not a valid Android package name")
            self._launch_package(package)
            time.sleep(0.8)
            foreground = self._foreground_package()
            if foreground is not None and foreground != package:
                raise RPCError(f"failed to foreground app '{package}' (current foreground package: '{foreground}')")
            tree = self._current_tree()
            return {
                "bundle_identifier": package,
                "package_name": package,
                "tree": tree,
            }, False

        if method == "set_api_key":
            key = _string_value(params, "api_key").strip()
            if not key:
                raise RPCError("api_key is required")
            self.api_key = key
            return {"ok": True}, False

        if method == "submit_prompt":
            if not self.api_key:
                raise RPCError("No API key found")
            raise RPCError("submit_prompt is not yet supported on the Android bridge; use RPC tool methods directly")

        if method == "stop":
            return {}, True

        if method == "ping":
            return {"status": "ok", "pong": True}, False

        raise RPCError(f"Unsupported command: {method}")


class AndroidRPCServer:
    def __init__(self, host: str, port: int, bridge: AndroidDeviceBridge) -> None:
        self.host = host
        self.port = port
        self.bridge = bridge
        self._stop_event = threading.Event()
        self._socket: Optional[socket.socket] = None

    def start(self) -> None:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((self.host, self.port))
        server.listen(64)
        server.settimeout(0.5)
        self._socket = server
        eprint(f"PHONEAGENT_RPC_READY platform=android serial={self.bridge.serial} host={self.host} port={self.port}")

        try:
            while not self._stop_event.is_set():
                try:
                    conn, addr = server.accept()
                except socket.timeout:
                    continue
                except OSError:
                    break
                t = threading.Thread(target=self._handle_connection, args=(conn, addr), daemon=True)
                t.start()
        finally:
            try:
                server.close()
            except OSError:
                pass

    def stop(self) -> None:
        self._stop_event.set()
        if self._socket is not None:
            try:
                self._socket.close()
            except OSError:
                pass

    def _handle_connection(self, conn: socket.socket, addr: Tuple[str, int]) -> None:
        peer = addr[0]
        if peer not in {"127.0.0.1", "::1"}:
            conn.close()
            return

        buffer = bytearray()
        try:
            while not self._stop_event.is_set():
                chunk = conn.recv(65536)
                if not chunk:
                    return
                buffer.extend(chunk)
                while True:
                    nl = buffer.find(b"\n")
                    if nl < 0:
                        break
                    line = bytes(buffer[:nl]).strip()
                    del buffer[: nl + 1]
                    if not line:
                        continue
                    self._handle_line(conn, line)
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def _send(self, conn: socket.socket, payload: Dict[str, Any]) -> None:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n"
        conn.sendall(data)

    def _handle_line(self, conn: socket.socket, line: bytes) -> None:
        req_id: Any = None
        try:
            obj = json.loads(line.decode("utf-8"))
            if not isinstance(obj, dict):
                raise RPCError("Invalid JSON payload")
            req_id = obj.get("id", None)
            method = obj.get("method")
            params = obj.get("params", {})
            if method is None:
                raise RPCError("Missing 'method' field")
            if not isinstance(method, str):
                raise RPCError("Field 'method' must be a string")
            if not isinstance(params, dict):
                raise RPCError("Field 'params' must be an object")

            result, should_stop = self.bridge.handle(method, params)
            self._send(conn, {"id": req_id, "result": result})
            if should_stop:
                self.stop()
        except RPCError as exc:
            self._send(conn, {"id": req_id, "error": {"message": str(exc)}})
        except Exception as exc:
            self._send(conn, {"id": req_id, "error": {"message": f"Internal error: {exc}"}})


def _resolve_adb_binary(explicit: Optional[str]) -> str:
    if explicit:
        return explicit

    env_override = os.environ.get("PHONEAGENT_ADB")
    if env_override:
        return env_override

    from_path = shutil.which("adb")
    if from_path:
        return from_path

    roots = [
        os.environ.get("ANDROID_HOME", ""),
        os.environ.get("ANDROID_SDK_ROOT", ""),
        os.path.expanduser("~/Library/Android/sdk"),
    ]
    for root in roots:
        if not root:
            continue
        candidate = os.path.join(root, "platform-tools", "adb")
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate

    raise SystemExit(
        "adb was not found. Set PHONEAGENT_ADB, pass --adb-binary, or add adb to PATH."
    )


def _list_connected_devices(adb_binary: str) -> list[str]:
    proc = subprocess.run([adb_binary, "devices"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if proc.returncode != 0:
        stderr = proc.stderr.decode("utf-8", errors="replace").strip()
        raise SystemExit(f"adb devices failed: {stderr or proc.returncode}")
    out = proc.stdout.decode("utf-8", errors="replace").splitlines()
    devices: list[str] = []
    for line in out[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            devices.append(parts[0])
    return devices


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="PhoneAgent Android JSON-RPC bridge (localhost only).")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--serial", default=None, help="adb device serial. Defaults to the only connected device.")
    parser.add_argument("--adb-binary", default=None, help="Path to adb binary. Defaults to PATH/SDK auto-detection.")
    args = parser.parse_args(argv)
    adb_binary = _resolve_adb_binary(args.adb_binary)

    if args.serial:
        serial = args.serial
    else:
        devices = _list_connected_devices(adb_binary)
        if not devices:
            raise SystemExit("No adb devices found. Start an emulator or connect a device, then retry.")
        if len(devices) > 1:
            joined = ", ".join(devices)
            raise SystemExit(f"Multiple adb devices found ({joined}). Re-run with --serial.")
        serial = devices[0]

    # Validate connectivity early.
    probe = subprocess.run(
        [adb_binary, "-s", serial, "get-state"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if probe.returncode != 0 or probe.stdout.decode("utf-8", errors="replace").strip() != "device":
        stderr = probe.stderr.decode("utf-8", errors="replace").strip()
        raise SystemExit(f"adb device '{serial}' is not ready: {stderr or probe.stdout.decode('utf-8', errors='replace').strip()}")

    server = AndroidRPCServer(
        host=args.host,
        port=args.port,
        bridge=AndroidDeviceBridge(serial=serial, adb_binary=adb_binary),
    )
    server.start()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(__import__("sys").argv[1:]))
