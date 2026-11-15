## Quest 3 Android test fork

This fork fixes the Android ARM64 unresolved NEON `load` symbol reported in
[upstream issue #102](https://github.com/appsinacup/godot-whisper/issues/102).
The original build reproduces the missing symbol even with NDK r27d; the fix
keeps the FP16-to-FP32 conversion available on baseline ARM64.

**[Download the Quest test prerelease](https://github.com/Galygious/godot-whisper/releases/tag/quest3-test-v0.1.0)**

The release provides a signed APK with an offline model, an addon ZIP, and
rebuild instructions. The APK is a standard Android windowed app for testing
native loading and microphone transcription on Quest; it is not an immersive
VR application. Local build, linker, dependency, and desktop transcription
checks pass. Quest hardware testing is still pending.

See [QUEST-ANDROID.txt](QUEST-ANDROID.txt) for installation, verification, and
source build instructions. Upstream documentation follows below.

<p align="center">
	<img width="128px" src="whisper_logo.png"/> 
	<h1 align="center">Godot Whisper</h1> 
</p>

<p align="center">
	<a href="https://github.com/appsinacup/godot-whisper/actions/workflows/runner.yml">
        <img src="https://github.com/appsinacup/godot-whisper/actions/workflows/runner.yml/badge.svg?branch=main"
            alt="build"></a>
    <a href="https://whisper.appsinacup.com" alt="Docs">
        <img src="https://img.shields.io/badge/Documentation-link-%23478cbf?logoColor=white" /></a>
    <a href="https://github.com/ggml-org/whisper.cpp" alt="Whisper CPP">
        <img src="https://img.shields.io/badge/WhisperCPP-v1.8.4-%23478cbf?logoColor=white" /></a>
    <a href="https://github.com/godotengine/godot-cpp" alt="Godot Version">
        <img src="https://img.shields.io/badge/Godot-v4.2-%23478cbf?logo=godot-engine&logoColor=white" /></a>
    <a href="https://discord.gg/v649emcpAu">
        <img src="https://img.shields.io/discord/1138836561102897172?logo=discord"
            alt="Chat on Discord"></a>
</p>

<p align="center">
<img src="whisper_cpp.gif"/>
</p>

## Features

|**Realtime audio transcription**| **Offline audio transcription**|
|-|-|
|**GPU acceleration**| **Flash Attention**|
|**Voice Activity Detection (VAD)**| **Quantized models**|
|**99 languages**| **Model downloader**|

## Platforms

| Platform | GPU Backend |
|----------|-------------|
| **macOS** | Metal + Accelerate |
| **iOS** | Metal + Accelerate |
| **Windows** | OpenCL + Vulkan |
| **Linux** | OpenCL + Vulkan |
| **Android** | OpenCL |
| **Web** | CPU (WebGPU disabled until Godot supports it) |

## Video Tutorial

[![Godot Whisper](https://img.youtube.com/vi/fAgjNkfBOKs/0.jpg)](https://www.youtube.com/watch?v=fAgjNkfBOKs&t=10s)

## How to get started

Go to the [Documentation](https://whisper.appsinacup.com) website.

## Star History

<a href="https://www.star-history.com/?repos=appsinacup%2Fgodot-whisper&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=appsinacup/godot-whisper&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=appsinacup/godot-whisper&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=appsinacup/godot-whisper&type=date&legend=top-left" />
 </picture>
</a>
