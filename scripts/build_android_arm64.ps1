param(
    [Parameter(Mandatory = $true)][string]$NdkRoot,
    [string]$Python = 'python',
    [int]$Jobs = 8
)
$ErrorActionPreference = 'Stop'
$ndkFullPath = (Resolve-Path -LiteralPath $NdkRoot).Path
$previousNdk = $env:ANDROID_NDK_ROOT
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $env:ANDROID_NDK_ROOT = $ndkFullPath
    # godot-cpp 4.2 otherwise selects a hardcoded NDK below ANDROID_HOME.
    & $Python -m SCons platform=android arch=arm64 target=template_release `
        'ANDROID_HOME=' build_profile=scripts/android_build_profile.json "-j$Jobs"
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed' }
    & $Python scripts/check_android_arm64.py --ndk $ndkFullPath
    if ($LASTEXITCODE -ne 0) { throw 'Android verification failed' }
} finally {
    $env:ANDROID_NDK_ROOT = $previousNdk
    Pop-Location
}
