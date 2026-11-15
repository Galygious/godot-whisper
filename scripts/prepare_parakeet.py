#!/usr/bin/env python3
"""Fetch hash-pinned Sherpa libraries/header and optional English INT8 models.

Python 3.12+: python scripts/prepare_parakeet.py --platform all --models
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import urllib.request


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["android", "windows", "all"], default="all")
    parser.add_argument("--models", action="store_true")
    parser.add_argument("--cache", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    project = root / "parakeet"
    vendor = project / "vendor"
    cache = args.cache or vendor / "downloads"
    cache.mkdir(parents=True, exist_ok=True)
    vendor.mkdir(parents=True, exist_ok=True)
    (vendor / ".gdignore").touch()
    manifest = json.loads((project / "dependencies.json").read_text())
    addon = project / "addons/godot_parakeet/bin"
    addon.mkdir(parents=True, exist_ok=True)

    def fetch(name):
        item = manifest[name]
        path = cache / ("c-api.h" if name == "header" else name + ".tar.bz2")
        if not path.exists():
            print("Downloading " + item["url"], flush=True)
            temporary = path.with_suffix(path.suffix + ".part")
            urllib.request.urlretrieve(item["url"], temporary)
            if sha256(temporary) != item["sha256"]:
                raise RuntimeError("SHA256 mismatch: " + name)
            temporary.replace(path)
        if sha256(path) != item["sha256"]:
            raise RuntimeError("SHA256 mismatch in cached " + str(path))
        return path

    header = vendor / "include/sherpa-onnx/c-api/c-api.h"
    header.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(fetch("header"), header)
    platforms = ["android", "windows"] if args.platform == "all" else [args.platform]
    for platform in platforms:
        archive = fetch(platform)
        extracted = cache / (platform + "-extracted")
        extracted.mkdir(exist_ok=True)
        with tarfile.open(archive) as source:
            source.extractall(extracted, filter="data")
        lib = vendor / platform
        lib.mkdir(exist_ok=True)
        if platform == "android":
            destination = addon / "android"
            destination.mkdir(exist_ok=True)
            for name in ["libsherpa-onnx-c-api.so", "libonnxruntime.so"]:
                source = extracted / "jniLibs/arm64-v8a" / name
                shutil.copy2(source, lib / name)
                shutil.copy2(source, destination / name)
        else:
            for name in ["sherpa-onnx-c-api.lib", "sherpa-onnx-c-api.dll", "onnxruntime.dll", "onnxruntime_providers_shared.dll"]:
                source = next(extracted.rglob(name))
                shutil.copy2(source, lib / name)
                if name.endswith(".dll"):
                    shutil.copy2(source, addon / name)
        print("Prepared " + platform, flush=True)
    if args.models:
        directory = project / "addons/godot_parakeet/models/parakeet-tdt-0.6b-v2-int8"
        directory.mkdir(parents=True, exist_ok=True)
        with tarfile.open(fetch("model"), "r|bz2") as archive:
            for member in archive:
                name = Path(member.name).name
                if name in manifest["model_files"] and member.isfile():
                    with archive.extractfile(member) as source, (directory / name).open("wb") as output:
                        shutil.copyfileobj(source, output, 4 * 1024 * 1024)
        for name, expected in manifest["model_files"].items():
            if sha256(directory / name) != expected:
                raise RuntimeError("Model SHA256 mismatch: " + name)
        print("Prepared Parakeet v2 INT8 model files", flush=True)


if __name__ == "__main__":
    main()
