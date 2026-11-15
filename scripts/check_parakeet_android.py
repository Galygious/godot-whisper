#!/usr/bin/env python3
"""Check ARM64 ELF layout and strong symbol dependency closure (Android API 27)."""
import argparse
from pathlib import Path
import struct
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ndk", required=True, type=Path)
    parser.add_argument("--cxx-runtime", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    host = "windows-x86_64" if sys.platform == "win32" else "linux-x86_64"
    toolchain = args.ndk / "toolchains/llvm/prebuilt" / host
    nm = toolchain / "bin" / ("llvm-nm.exe" if sys.platform == "win32" else "llvm-nm")
    base = root / "parakeet/addons/godot_parakeet/bin"
    libraries = [base / "libgodot_parakeet.android.arm64.so", base / "android/libsherpa-onnx-c-api.so", base / "android/libonnxruntime.so"]
    system = toolchain / "sysroot/usr/lib/aarch64-linux-android"
    dependencies = [system / "27" / name for name in ["libc.so", "libm.so", "libdl.so", "liblog.so", "libandroid.so"]]
    dependencies.append(args.cxx_runtime or system / "libc++_shared.so")

    def symbols(path, undefined=False):
        output = subprocess.check_output([str(nm), "--dynamic", "--undefined-only" if undefined else "--defined-only", str(path)], text=True)
        return {line.split()[-1].split("@")[0] for line in output.splitlines()
                if line.strip() and (not undefined or line.split()[-2] == "U")}

    available = set().union(*(symbols(path) for path in libraries + dependencies))
    for path in libraries:
        data = path.read_bytes()
        assert data[:6] == b"\x7fELF\x02\x01" and struct.unpack_from("<H", data, 18)[0] == 183
        offset = struct.unpack_from("<Q", data, 32)[0]
        size, count = struct.unpack_from("<HH", data, 54)
        loads = 0
        for index in range(count):
            header = struct.unpack_from("<IIQQQQQQ", data, offset + index * size)
            if header[0] == 1:
                loads += 1
                assert header[7] >= 16384 and header[2] % 16384 == header[3] % 16384, path.name + " is not 16 KiB aligned"
        assert loads > 0
        missing = symbols(path, True) - available
        assert not missing, path.name + ": unresolved imports " + str(sorted(missing))
        print("PASS: ARM64, 16 KiB ELF layout, API 27 dependency closure: " + path.name)
    assert "godot_parakeet_library_init" in symbols(libraries[0])
    print("PASS: Parakeet GDExtension entry point exported")


if __name__ == "__main__":
    main()
