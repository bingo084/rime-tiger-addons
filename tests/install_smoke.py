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
sys.path.insert(0, str(ROOT / "scripts"))
from user_codes_patch import CHANGES, apply as patch_core, restore as restore_core


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
            "lua/tiger_sentence.lua": "\n".join(original for original, _ in CHANGES),
            "custom_phrase.txt": "私人词\taa\tafter\n",
            "tiger_sentence.codes.txt": "书\taa\n",
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
        retired_paths = json.loads((ROOT / "manifest.json").read_text())["retired"]
        for name in retired_paths:
            retired = target / name
            retired.parent.mkdir(parents=True, exist_ok=True)
            retired.write_text("retired " + name)
        before = snapshot(target)
        invoke(ROOT, target, "--dry-run")
        assert snapshot(target) == before, "Dry run wrote files"
        invoke(ROOT, target)
        for name, text in sentinel.items():
            if name == "lua/tiger_sentence.lua":
                assert (target / name).read_text() == patch_core(text), "Core patch missing"
                assert restore_core((target / name).read_text()) == text, "Core patch is not reversible"
                core_backups = list((target / "backups").glob("tiger-addons-*/lua/tiger_sentence.lua"))
                assert len(core_backups) == 1 and core_backups[0].read_text() == text, "Core backup missing"
            else:
                assert (target / name).read_text() == text, f"Personal/base file changed: {name}"
        backups = list((target / "backups").glob("tiger-addons-*/lua/tiger_emoji.lua"))
        assert len(backups) == 1 and backups[0].read_text() == "older helper", "Rollback copy missing"
        for name in retired_paths:
            assert not (target / name).exists(), f"Retired helper was not removed: {name}"
            retired_backups = list((target / "backups").glob("tiger-addons-*/" + name))
            assert len(retired_backups) == 1 and retired_backups[0].read_text() == "retired " + name, f"Retired backup missing: {name}"
        invoke(ROOT, target, "--check")
        installed = snapshot(target)
        invoke(ROOT, target)
        assert snapshot(target) == installed, "Repeated install changed files"

        bad_repo = Path(folder) / "bad-repo"
        (bad_repo / "scripts").mkdir(parents=True)
        shutil.copy2(ROOT / "scripts/install.py", bad_repo / "scripts/install.py")
        shutil.copy2(ROOT / "scripts/user_codes_patch.py", bad_repo / "scripts/user_codes_patch.py")
        (bad_repo / "assets").symlink_to(ROOT / "assets", target_is_directory=True)
        manifest = json.loads((ROOT / "manifest.json").read_text())
        manifest["assets"][0]["sha256"] = "0" * 64
        (bad_repo / "manifest.json").write_text(json.dumps(manifest))
        invoke(bad_repo, target, success=False)
        assert snapshot(target) == installed, "Invalid resource caused a partial install"
        (target / "lua/tiger_sentence.lua").write_text("unknown upstream core")
        unsupported = snapshot(target)
        invoke(ROOT, target, success=False)
        assert snapshot(target) == unsupported, "Unsupported core caused a partial install"
    print("PASS installer: dry run, backups, retirement, personal data, idempotence, core reversibility, hash validation, unsupported-core rejection")


if __name__ == "__main__":
    main()
