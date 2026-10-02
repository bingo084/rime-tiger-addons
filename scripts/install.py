#!/usr/bin/env python3
"""Install the versioned auxiliary resources, leaving personal config intact."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def resources():
    entries = json.loads((ROOT / "manifest.json").read_text())["assets"]
    for entry in entries:
        relative = Path(entry["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Invalid resource path: {relative}")
        source = ROOT / "assets" / relative
        if digest(source) != entry["sha256"]:
            raise ValueError(f"Resource hash mismatch: {relative}")
    return entries


def atomic_copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as stream:
        temporary = Path(stream.name)
    try:
        shutil.copy2(source, temporary)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rime-dir", required=True, type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Show changes without writing")
    mode.add_argument("--check", action="store_true", help="Check installed resource hashes")
    args = parser.parse_args()
    target = args.rime_dir.expanduser().resolve()
    for name in ("rime.lua", "lua/tiger_sentence.lua", "tiger_sentence.schema.yaml"):
        if not (target / name).is_file():
            parser.error(f"Install the official Tiger Sentence base first: missing {name}")
    entries = resources()
    changed = []
    for entry in entries:
        destination = target / entry["path"]
        matches = destination.is_file() and digest(destination) == entry["sha256"]
        if not matches:
            changed.append(entry)
        print(f"{'OK' if matches else 'COPY'} {entry['path']}")
    if args.check:
        return 1 if changed else 0
    if args.dry_run or not changed:
        print(f"{len(changed)} resource(s) need installation; no files written.")
        return 0
    backup = target / "backups" / ("tiger-addons-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
    for entry in changed:
        destination = target / entry["path"]
        if destination.is_file():
            saved = backup / entry["path"]
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(destination, saved)
    for entry in changed:
        atomic_copy(ROOT / "assets" / entry["path"], target / entry["path"])
    print(f"Installed {len(changed)} resource(s). Personal custom and user data were preserved.")
    if backup.exists():
        print(f"Backup: {backup}")
    print("Restore custom through chezmoi, or merge config/tiger_sentence.custom.yaml; then deploy Rime.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
