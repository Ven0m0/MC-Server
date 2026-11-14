#!/usr/bin/env python3
"""Tests for the optimize-resourcepacks.py pipeline (no PackSquash needed)."""

import importlib.util
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any

_SPEC = importlib.util.spec_from_file_location(
    "optimize_resourcepacks",
    Path(__file__).parent.parent / "optimize-resourcepacks.py",
)
assert _SPEC is not None and _SPEC.loader is not None
opt: Any = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(opt)


def _make_pack(root: Path) -> Path:
    pack = root / "pack"
    pack.mkdir()
    (pack / "pack.mcmeta").write_text(
        '{"pack": {"pack_format": 34, "description": "x"}}'
    )
    return pack


def test_restore_runs_when_packsquash_fails():
    calls = []

    def fail(*_args):
        raise subprocess.CalledProcessError(1, "packsquash")

    with tempfile.TemporaryDirectory() as tmp:
        pack = _make_pack(Path(tmp))
        original_run, opt._run = opt._run, fail
        try:
            opt._optimize("ps", pack, Path(tmp) / "out.zip", lambda: calls.append(1))
        except subprocess.CalledProcessError:
            pass
        else:
            raise AssertionError("expected CalledProcessError")
        finally:
            opt._run = original_run
    assert calls == [1], f"restore calls: {calls}"


def test_process_one_survives_unexpected_error():
    def boom(*_args):
        raise OSError("disk gone")

    with tempfile.TemporaryDirectory() as tmp:
        pack = _make_pack(Path(tmp))
        original, opt.process_dir = opt.process_dir, boom
        try:
            assert opt.process_one("ps", pack) is False
        finally:
            opt.process_dir = original


def test_selected_packs_txt_is_kept():
    def fake_run(_ps, pack_dir, output_zip):
        # PackSquash output: only pack files, no stray root .txt
        with zipfile.ZipFile(output_zip, "w") as zf:
            zf.write(pack_dir / "pack.mcmeta", "pack.mcmeta")

    with tempfile.TemporaryDirectory() as tmp:
        pack = _make_pack(Path(tmp))
        (pack / "Selected Packs.txt").write_bytes(b"Packs:\nDarkUI")
        out = Path(tmp) / "out.zip"
        original_run, opt._run = opt._run, fake_run
        try:
            opt._optimize("ps", pack, out, lambda: None)
        finally:
            opt._run = original_run
        with zipfile.ZipFile(out) as zf:
            assert zf.read("Selected Packs.txt") == b"Packs:\nDarkUI"


if __name__ == "__main__":
    tests = [
        test_selected_packs_txt_is_kept,
        test_restore_runs_when_packsquash_fails,
        test_process_one_survives_unexpected_error,
    ]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"\033[0;32m✓\033[0m {t.__name__}")
        except AssertionError as e:
            print(f"\033[0;31m✗\033[0m {t.__name__}: {e}")
            failed += 1

    print(f"\nTests: {len(tests)}, Failed: {failed}")
    sys.exit(failed)
