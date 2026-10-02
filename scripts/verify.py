#!/usr/bin/env python3
"""Build and test a fresh Rime profile without using the live databases."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import yaml

from install import ROOT, digest


def run_logged(command, log):
    with log.open("w") as output:
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print(log.read_text()[-8000:])
        raise RuntimeError(f"Command failed ({result.returncode}); log: {log}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-rime-dir", required=True, type=Path)
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--allow-new-base", action="store_true", help="Test a different upstream version")
    args = parser.parse_args()
    base = args.base_rime_dir.expanduser().resolve()
    expected = json.loads((ROOT / "BASELINE.json").read_text())["official_runtime_sha256"]
    drift = [name for name, sha in expected.items()
             if not (base / name).is_file() or digest(base / name) != sha]
    if drift and not args.allow_new_base:
        parser.error("Base differs from the recorded version: " + ", ".join(drift))
    if drift:
        print("Testing changed base: " + ", ".join(drift))
    work = args.work_dir.expanduser().resolve() if args.work_dir else Path(tempfile.mkdtemp(prefix="tiger-addons-verify-"))
    if args.work_dir and work.exists() and any(work.iterdir()):
        parser.error("--work-dir must be empty")
    user = work / "user"
    user.mkdir(parents=True, exist_ok=True)
    print(f"Verification directory: {work}", flush=True)
    core_files = [name for name in expected if not name.startswith("models/")]
    core_files += ["tiger_sentence.dict.yaml", "tiger_sentence_ascii.schema.yaml", "symbols.yaml"]
    for name in core_files:
        source = base / name
        destination = user / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    (user / "models").symlink_to(base / "models", target_is_directory=True)
    run_logged([sys.executable, str(ROOT / "scripts/install.py"), "--rime-dir", str(user)], work / "install.log")
    run_logged([sys.executable, str(ROOT / "scripts/install.py"), "--rime-dir", str(user), "--check"], work / "resource-check.log")
    custom = yaml.safe_load((ROOT / "config/tiger_sentence.custom.yaml").read_text())
    fixture = yaml.safe_load((ROOT / "tests/shortcuts.yaml").read_text())
    custom["patch"].update(fixture["patch"])
    (user / "tiger_sentence.custom.yaml").write_text(yaml.safe_dump(custom, allow_unicode=True, sort_keys=False))
    (user / "default.custom.yaml").write_text("patch:\n  schema_list:\n    - schema: tiger_sentence\n")
    (user / "tiger_sentence.options.yaml").write_text(
        "options:\n  tiger_sentence_allow_duplicate_single: true\n"
        "  tiger_sentence_correction_level: weak\n  tiger_sentence_early_commit: true\n"
        "  tiger_sentence_early_commit_to_preedit: false\n  tiger_sentence_key_correction: true\n")
    run_logged(["rime_deployer", "--build", str(user), "/usr/share/rime-data", str(user / "build")], work / "deploy.log")
    built = yaml.safe_load((user / "build/tiger_sentence.schema.yaml").read_text())
    original = yaml.safe_load((base / "tiger_sentence.schema.yaml").read_text())
    if built["key_binder"]["bindings"] != original["key_binder"]["bindings"] + fixture["patch"]["key_binder/bindings/+"]:
        raise RuntimeError("Generated bindings differ from the official defaults plus the fixture")
    if built["speller"] != original["speller"]:
        raise RuntimeError("Official speller changed")
    punctuation = dict(original["punctuator"])
    symbols = yaml.safe_load((base / "symbols.yaml").read_text())
    punctuation.update({key: symbols["punctuator"][key] for key in ("half_shape", "full_shape")})
    if built["punctuator"] != punctuation:
        raise RuntimeError("Official punctuation changed")
    binary = work / "librime_smoke"
    run_logged(["g++", "-std=c++17", str(ROOT / "tests/librime_smoke.cpp"), "-o", str(binary), "-lrime", "-ldl", "-Wl,-rpath,/usr/lib/rime-plugins"], work / "compile.log")
    run_logged([str(binary), str(user)], work / "smoke.log")
    print((work / "smoke.log").read_text().splitlines()[-1])
    print("Fresh install, generated bindings, and isolated librime behavior verified.")
    print(f"Logs retained in {work}; live databases were not copied or modified.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
