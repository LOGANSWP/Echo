#!/usr/bin/env python3
"""Materialize the separately pinned Debug simulator artifact, without downloading.

Task 4.0k; ADR-023. Closed SHA inventory; no device/release approval.
"""

import argparse
import json
from pathlib import Path
import shutil

import prepare_generation_resources as resources

IDENTITY = "6a67bb65383697558556a14f2e1a7d12c2f79ad9e688f55bbe27466f75cdefff"


def prepare(verify_only=False):
    root = resources.ROOT
    approved = root / "Echo/Resources/Models/OfflineGeneration.bundle"
    resources.prepare(approved, True)
    manifest = root / "docs/05-planning/4.0k-simulator-artifact-manifest.json"
    if resources.digest(manifest) != IDENTITY:
        raise ValueError("Simulator manifest changed")
    document = json.loads(manifest.read_text())
    entries = document["files"]
    target = root / "Echo/Resources/Models/OfflineGenerationSimulator.bundle"
    pinned = root / "PinnedModels/offline-generation-evaluation/qwen3-0.6b/simulator-prefill4-v2"
    expected = {entry["path"] for entry in entries}
    if len(expected) != len(entries) or target.is_symlink():
        raise ValueError("Invalid simulator inventory")
    if target.exists():
        for path in target.rglob("*"):
            if path.is_symlink() or (not path.is_dir() and str(path.relative_to(target)) not in expected):
                raise ValueError("Unexpected simulator resource")
    work = []
    for entry in entries:
        source_root = pinned if entry["path"].startswith("Qwen06BSimulatorPrefill4.mlmodelc/") else approved
        source = resources.checked_path(source_root, entry["path"])
        destination = resources.checked_path(target, entry["path"])
        resources.verify(source, entry)
        if verify_only or destination.exists():
            resources.verify(destination, entry)
        work.append((source, destination, entry))
    for source, destination, entry in work:
        if not verify_only and not destination.exists():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
        resources.verify(destination, entry)
    return {"artifactIdentity": IDENTITY, "fileCount": len(entries),
            "totalBytes": sum(entry["sizeBytes"] for entry in entries),
            "scope": "debug-simulator-engineering-only", "releaseApproved": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true")
    print(json.dumps(prepare(parser.parse_args().verify_only), indent=2))
