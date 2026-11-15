#!/usr/bin/env python3
"""Check the ARM64 artifact and cross-compile the NEON load regression paths.

Run after SCons (which applies the pinned whisper.cpp source workaround):
  python scripts/check_android_arm64.py --ndk /path/to/android-ndk-r27d
"""
import argparse
import os
from pathlib import Path
import struct
import subprocess
import tempfile


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ndk", required=True, type=Path)
    parser.add_argument("--library", type=Path, default=Path(
        "bin/addons/godot_whisper/bin/libgodot_whisper.android.template_release.arm64.so"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    os.chdir(root)
    host = "windows-x86_64" if os.name == "nt" else "linux-x86_64"
    suffix = ".exe" if os.name == "nt" else ""
    tools = args.ndk.resolve() / "toolchains/llvm/prebuilt" / host / "bin"
    nm = tools / ("llvm-nm" + suffix)
    compiler = tools / ("clang++" + suffix)
    data = args.library.read_bytes()
    assert data[:6] == b"\x7fELF\x02\x01", "Expected little-endian ELF64"
    assert struct.unpack_from("<H", data, 18)[0] == 183, "Expected AArch64"
    phoff = struct.unpack_from("<Q", data, 32)[0]
    phsize, phnum = struct.unpack_from("<HH", data, 54)
    alignments = []
    for index in range(phnum):
        header = struct.unpack_from("<IIQQQQQQ", data, phoff + index * phsize)
        if header[0] == 1:
            alignments.append(header[7])
            assert header[7] >= 16384, "PT_LOAD must support 16 KiB pages"
            assert header[2] % 16384 == header[3] % 16384
    assert alignments, "No loadable segments"
    undefined = run(nm, "--dynamic", "--undefined-only", args.library)
    for line in undefined.splitlines():
        symbol = line.split()[-1]
        assert not any(name in symbol for name in (
            "GLOBAL__N_", "ggml_", "whisper_", "godot_whisper_")), line
    exports = run(nm, "--dynamic", "--defined-only", args.library)
    assert "godot_whisper_library_init" in exports, "Missing GDExtension entry point"
    print("PASS: ARM64 ELF, 16 KiB segments, entry point, no unresolved internal symbols")

    whisper = root / "thirdparty/whisper.cpp"
    cpu = whisper / "ggml/src/ggml-cpu"
    includes = [whisper / "include", whisper / "ggml/include", whisper / "ggml/src", cpu]
    variants = [
        ("baseline-arm64", "aarch64-linux-android21", ["-march=armv8-a"]),
        ("fp16-arm64", "aarch64-linux-android21", ["-march=armv8.2-a+fp16"]),
        ("baseline-arm32", "armv7a-linux-androideabi21", ["-march=armv7-a", "-mfpu=neon"]),
    ]
    with tempfile.TemporaryDirectory(prefix="whisper-neon-") as scratch:
        for name, target, arch_flags in variants:
            obj = Path(scratch) / (name + ".o")
            flags = ["--target=" + target, *arch_flags, "-std=c++17", "-O2", "-fPIC"]
            flags += ["-I" + str(path) for path in includes]
            run(compiler, *flags, "-c", cpu / "llamafile/sgemm.cpp", "-o", obj)
            missing = run(nm, "--undefined-only", obj)
            assert "_ZN12_GLOBAL__N_14load" not in missing, missing
            print("PASS: " + name + " sgemm compiles with no undefined load template")


if __name__ == "__main__":
    main()
