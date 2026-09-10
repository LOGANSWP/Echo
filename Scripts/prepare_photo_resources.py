#!/usr/bin/env python3
"""Install the approved 4.0l resources from local pinned artifacts only.

Never downloads, overwrites a mismatched resource, or grants release approval.
Task 4.0l; ADR-025. Models remain excluded from Git.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
PACKET = ROOT / "docs/05-planning/4.0l-cpu-approval-supplement"
IDENTITY = "ddbdbe735c47c7346e62c0ef456f9f2e0442dd9615fd57f7f239a10592ec6367"


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def checked_path(root, relative):
    parts = relative.split("/")
    if not relative or any(part in ("", ".", "..") for part in parts):
        raise ValueError("Noncanonical resource path")
    current = root
    for part in parts:
        current = current / part
        if current.is_symlink():
            raise ValueError("Symlink resource rejected")
    return current


def verify(path, entry):
    if (not path.is_file() or path.stat().st_size != entry["sizeBytes"]
            or digest(path) != entry["sha256"]):
        raise ValueError("Resource integrity mismatch: " + path.name)


def prepare(destination, verify_only=False):
    manifest = PACKET / "packet-manifest.json"
    if digest(manifest) != IDENTITY:
        raise ValueError("The frozen approval packet changed")
    approval = json.loads((PACKET / "approval.json").read_text())
    if (approval.get("status") != "approved"
            or approval.get("packetManifestSha256") != IDENTITY):
        raise ValueError("Exact artifact use has not been approved")
    attachments = json.loads(manifest.read_text())["files"]
    for entry in attachments:
        # The frozen packet references sibling evidence in the planning directory.
        relative = entry["path"]
        attachment = (checked_path(PACKET.parent, relative[3:]) if relative.startswith("../")
                      else checked_path(PACKET, relative))
        verify(attachment, entry)
    resources = json.loads((PACKET / "candidate-resources.json").read_text())["files"]
    expected = {entry["destination"] for entry in resources}
    if len(expected) != len(resources):
        raise ValueError("Duplicate resource destination")
    if destination.is_symlink():
        raise ValueError("Symlink bundle rejected")
    if destination.exists():
        for path in destination.rglob("*"):
            if path.is_symlink() or (not path.is_dir() and str(path.relative_to(destination)) not in expected):
                raise ValueError("Unexpected bundle resource")
    # Check every source and existing destination before any write.
    for entry in resources:
        verify(checked_path(ROOT, entry["path"]), entry)
        target = checked_path(destination, entry["destination"])
        if target.exists() or verify_only:
            verify(target, entry)
    if not verify_only:
        for entry in resources:
            target = checked_path(destination, entry["destination"])
            if not target.exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(checked_path(ROOT, entry["path"]), target)
            verify(target, entry)
    return {"artifactIdentity": IDENTITY, "fileCount": len(resources),
            "totalBytes": sum(entry["sizeBytes"] for entry in resources),
            "scope": "approved-artifact-integrity-only", "releaseApproved": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    print(json.dumps(prepare(ROOT / "Echo/Resources/Models/PhotoUnderstanding.bundle", args.verify_only), indent=2))
