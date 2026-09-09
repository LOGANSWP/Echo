#!/usr/bin/env python3
"""Verify complete research artifact bytes against an external JSON manifest.

Task: 4.0k; specs: US-RES-004 and ADR-023 section 1 (full artifact integrity).
Required schema: {"schemaVersion": 1, "files": [{"path": "relative/file",
"sha256": "64 lowercase hexadecimal digits", "sizeBytes": 123}]}.
Additional metadata is not validated and cannot grant model approval. Paths use
canonical relative POSIX spelling. The artifact tree must remain unchanged while
this read-only tool runs. Success proves file integrity only, never legal/privacy
approval, model quality, Core ML compatibility, or production readiness.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import stat


CHUNK_BYTES = 1024 * 1024
SCOPE = {"scope": "file-integrity-only", "approvalGranted": False}


class IntegrityError(ValueError):
    """A malformed manifest or artifact tree failed closed."""


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise IntegrityError("Manifest contains duplicate JSON keys")
        result[key] = value
    return result


def _invalid_constant(_value):
    raise IntegrityError("Manifest contains a non-JSON numeric constant")


def _canonical_path(value):
    if not isinstance(value, str) or not value:
        raise IntegrityError("File path must be a nonempty string")
    components = value.split("/")
    if (PurePosixPath(value).is_absolute() or PureWindowsPath(value).drive
            or "\\" in value or any(part in ("", ".", "..") for part in components)
            or any(ord(character) < 32 or ord(character) == 127 for character in value)
            or PurePosixPath(value).as_posix() != value):
        raise IntegrityError("File path is not canonical and relative: " + repr(value))
    return value


def _read_manifest(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as stream:
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode):
            raise IntegrityError("Manifest must be a regular, nonsymlink file")
        document = json.loads(stream.read().decode("utf-8"),
                              object_pairs_hook=_unique_object,
                              parse_constant=_invalid_constant)
    if (not isinstance(document, dict) or type(document.get("schemaVersion")) is not int
            or document["schemaVersion"] != 1):
        raise IntegrityError("Manifest schemaVersion must be integer 1")
    entries = document.get("files")
    if not isinstance(entries, list) or not entries:
        raise IntegrityError("Manifest files must be a nonempty array")
    expected = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise IntegrityError("Manifest file entries must be objects")
        name = _canonical_path(entry.get("path"))
        if name in expected:
            raise IntegrityError("Manifest contains duplicate file path: " + name)
        digest = entry.get("sha256")
        size = entry.get("sizeBytes")
        if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
            raise IntegrityError("File sha256 must be 64 lowercase hexadecimal digits: " + name)
        if type(size) is not int or size < 0:
            raise IntegrityError("File sizeBytes must be a nonnegative integer: " + name)
        expected[name] = (size, digest)
    return expected, metadata


def _signature(metadata):
    return (metadata.st_dev, metadata.st_ino, metadata.st_size,
            metadata.st_mtime_ns, metadata.st_ctime_ns)


def _open_directory(path, parent=None):
    return os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)


def _inventory(descriptor, prefix=""):
    files = {}
    with os.scandir(descriptor) as entries:
        for entry in entries:
            name = prefix + entry.name
            _canonical_path(name)
            metadata = entry.stat(follow_symlinks=False)
            if stat.S_ISLNK(metadata.st_mode):
                raise IntegrityError("Artifact contains a symlink: " + name)
            if stat.S_ISDIR(metadata.st_mode):
                child = _open_directory(entry.name, descriptor)
                try:
                    opened = os.fstat(child)
                    if (opened.st_dev, opened.st_ino) != (metadata.st_dev, metadata.st_ino):
                        raise IntegrityError("Artifact directory changed during verification: " + name)
                    files.update(_inventory(child, name + "/"))
                finally:
                    os.close(child)
            elif stat.S_ISREG(metadata.st_mode):
                files[name] = metadata
            else:
                raise IntegrityError("Artifact contains a nonregular file: " + name)
    return files


def _hash_file(root_descriptor, name, original):
    descriptor = os.dup(root_descriptor)
    try:
        components = name.split("/")
        for component in components[:-1]:
            child = _open_directory(component, descriptor)
            os.close(descriptor)
            descriptor = child
        file_descriptor = os.open(components[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                                  dir_fd=descriptor)
        with os.fdopen(file_descriptor, "rb") as stream:
            before = os.fstat(stream.fileno())
            if not stat.S_ISREG(before.st_mode) or _signature(before) != _signature(original):
                raise IntegrityError("Artifact file changed before hashing: " + name)
            digest = hashlib.sha256()
            size = 0
            while True:
                chunk = stream.read(CHUNK_BYTES)
                if not chunk:
                    break
                digest.update(chunk)
                size += len(chunk)
            if _signature(os.fstat(stream.fileno())) != _signature(before):
                raise IntegrityError("Artifact file changed during hashing: " + name)
            return size, digest.hexdigest()
    finally:
        os.close(descriptor)


def verify_artifact(root, manifest):
    """Return integrity-only evidence or raise IntegrityError; perform no writes."""
    try:
        root = Path(root)
        manifest = Path(manifest)
        if manifest.resolve().is_relative_to(root.resolve()):
            raise IntegrityError("Manifest must be outside the artifact root")
        expected, manifest_metadata = _read_manifest(manifest)
        descriptor = _open_directory(root)
        try:
            root_metadata = os.fstat(descriptor)
            inventory = _inventory(descriptor)
            missing = sorted(expected.keys() - inventory.keys())
            extra = sorted(inventory.keys() - expected.keys())
            if missing or extra:
                raise IntegrityError("File set mismatch: " + json.dumps(
                    {"missing": missing, "extra": extra}, ensure_ascii=True))
            for name in sorted(expected):
                metadata = inventory[name]
                if (metadata.st_dev, metadata.st_ino) == (
                        manifest_metadata.st_dev, manifest_metadata.st_ino):
                    raise IntegrityError("Manifest is also present inside the artifact: " + name)
                size, digest = expected[name]
                if metadata.st_size != size:
                    raise IntegrityError("File size mismatch: " + name)
                actual_size, actual_digest = _hash_file(descriptor, name, metadata)
                if (actual_size, actual_digest) != (size, digest):
                    raise IntegrityError("File SHA-256 or size mismatch: " + name)
            final_inventory = _inventory(descriptor)
            if ({name: _signature(value) for name, value in final_inventory.items()}
                    != {name: _signature(value) for name, value in inventory.items()}):
                raise IntegrityError("Artifact changed during verification")
            if _signature(root.lstat()) != _signature(root_metadata):
                raise IntegrityError("Artifact root changed during verification")
            return {**SCOPE, "passed": True, "verifiedFiles": len(expected),
                    "totalBytes": sum(size for size, _digest in expected.values())}
        finally:
            os.close(descriptor)
    except (OSError, UnicodeError, json.JSONDecodeError, RecursionError) as error:
        raise IntegrityError("Unable to verify artifact: " + str(error)) from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path, help="Complete artifact directory")
    parser.add_argument("--manifest", required=True, type=Path,
                        help="JSON manifest located outside the artifact directory")
    arguments = parser.parse_args()
    try:
        result = verify_artifact(arguments.root, arguments.manifest)
    except IntegrityError as error:
        result = {**SCOPE, "passed": False, "errors": [str(error)]}
    print(json.dumps(result, sort_keys=True))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
