#!/usr/bin/env python3
"""Check dry runs, rollback copies, idempotence, and personal-data preservation."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def snapshot(directory):
    return {str(p.relative_to(directory)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in directory.rglob("*") if p.is_file()}


def invoke(repo, target, *flags, success=True):
    result = subprocess.run([sys.executable, str(repo / "scripts/install.py"),
                             "--rime-dir", str(target), *flags], capture_output=True, text=True)
    if (result.returncode == 0) != success:
        raise RuntimeError(result.stdout + result.stderr)


def main():
    with tempfile.TemporaryDirectory(prefix="tiger-addons-install-test-") as folder:
        target = Path(folder) / "rime"
        sentinel = {
            "rime.lua": "official loader",
            "lua/tiger_sentence.lua": "official core",
            "tiger_sentence.schema.yaml": "official schema",
            "tiger_sentence.custom.yaml": "patch:\n  key_binder/bindings/+: []\n# personal\n",
            "default.custom.yaml": "personal scheme list",
            "symbols.yaml": "personal symbols",
            "models/model.bin": "model",
            "build/schema.yaml": "compiled artifact",
            "lua/zqj_stats.userdb/keep": "personal statistics",
            "tiger_sentence_learning.userdb/keep": "personal learning",
        }
        for name, text in sentinel.items():
            p = target / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text)
        old = target / "lua/tiger_emoji.lua"
        old.write_text("older helper")
        retired = target / "lua/tiger_kf.lua"
        retired.write_text("retired quick symbols")
        before = snapshot(target)
        invoke(ROOT, target, "--dry-run")
        assert snapshot(target) == before, "Dry run wrote files"
        invoke(ROOT, target)
        for name, text in sentinel.items():
            assert (target / name).read_text() == text, f"Personal/base file changed: {name}"
        backups = list((target / "backups").glob("tiger-addons-*/lua/tiger_emoji.lua"))
        assert len(backups) == 1 and backups[0].read_text() == "older helper", "Rollback copy missing"
        assert not retired.exists(), "Retired helper was not removed"
        retired_backups = list((target / "backups").glob("tiger-addons-*/lua/tiger_kf.lua"))
        assert len(retired_backups) == 1 and retired_backups[0].read_text() == "retired quick symbols", "Retired backup missing"
        invoke(ROOT, target, "--check")
        installed = snapshot(target)
        invoke(ROOT, target)
        assert snapshot(target) == installed, "Repeated install changed files"

        bad_repo = Path(folder) / "bad-repo"
        (bad_repo / "scripts").mkdir(parents=True)
        shutil.copy2(ROOT / "scripts/install.py", bad_repo / "scripts/install.py")
        (bad_repo / "assets").symlink_to(ROOT / "assets", target_is_directory=True)
        manifest = json.loads((ROOT / "manifest.json").read_text())
        manifest["assets"][0]["sha256"] = "0" * 64
        (bad_repo / "manifest.json").write_text(json.dumps(manifest))
        invoke(bad_repo, target, success=False)
        assert snapshot(target) == installed, "Invalid resource caused a partial install"
    print("PASS installer: dry run, backups, retirement, personal data, idempotence, hash validation")


if __name__ == "__main__":
    main()
