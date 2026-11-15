#!/usr/bin/env python3
"""Prepare the Quest smoke project after compiling the native extension."""
import argparse
import hashlib
from pathlib import Path
import shutil
import urllib.request

MODEL_NAME = "ggml-tiny.en-q5_1.bin"
MODEL_SHA256 = "c77c5766f1cef09b6b7d47f21b546cbddd4157886b3b5d6d4f709e91e66c7c2b"
MODEL_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/" + MODEL_NAME


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, help="Use an already downloaded tiny.en Q5_1 model")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    project = root / "quest-test"
    addon = project / "addons/godot_whisper"
    (addon / "bin").mkdir(parents=True, exist_ok=True)
    source = root / "bin/addons/godot_whisper"
    shutil.copy2(source / "godot_whisper.gdextension", addon)
    libraries = list((source / "bin").glob("*.so")) + list((source / "bin").glob("*.dll"))
    if not any(path.name.endswith("android.template_release.arm64.so") for path in libraries):
        raise SystemExit("Build the Android ARM64 extension first.")
    for library in libraries:
        shutil.copy2(library, addon / "bin")
    shutil.copy2(root / "thirdparty/whisper.cpp/samples/jfk.wav", project / "jfk.wav")
    model = project / "models" / MODEL_NAME
    model.parent.mkdir(exist_ok=True)
    if args.model:
        shutil.copyfile(args.model, model)
    elif not model.exists():
        print("Downloading 30.7 MiB offline model from " + MODEL_URL)
        urllib.request.urlretrieve(MODEL_URL, model)
    digest = hashlib.sha256(model.read_bytes()).hexdigest()
    if digest != MODEL_SHA256:
        raise SystemExit("Model SHA256 mismatch: " + digest)
    print("Ready: " + str(project))


if __name__ == "__main__":
    main()
