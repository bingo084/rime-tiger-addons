#!/usr/bin/env python3
"""Refresh hashes for the resources already registered in manifest.json."""
import json
from pathlib import Path

from install import ROOT, digest


def main():
    path = ROOT / "manifest.json"
    manifest = json.loads(path.read_text())
    changed = 0
    for entry in manifest["assets"]:
        relative = Path(entry["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Invalid resource path: {relative}")
        sha = digest(ROOT / "assets" / relative)
        if sha != entry["sha256"]:
            entry["sha256"] = sha
            changed += 1
    if changed:
        path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Updated hashes for {changed} resource(s).")


if __name__ == "__main__":
    main()
