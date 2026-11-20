#!/usr/bin/env python3
"""Print the UDID of an available iPhone simulator on the newest iOS runtime."""
import json, re, subprocess, sys

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
def version(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
preferred = ["iPhone 16", "iPhone 17", "iPhone 16 Pro", "iPhone 17 Pro", "iPhone 15", "iPhone 15 Pro"]
candidates = []
for runtime, devices in data["devices"].items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if d["name"].startswith("iPhone"):
            rank = preferred.index(d["name"]) if d["name"] in preferred else 99
            candidates.append((version(runtime), -rank, d["udid"], d["name"], runtime))
if not candidates:
    sys.exit("No iPhone simulator available")
candidates.sort(reverse=True)
best = candidates[0]
print(best[2])
print(f"{best[3]} — {best[4]}", file=sys.stderr)
