# Cropaway Windows Build Script
# Run this on a Windows machine to produce a ready-to-install Setup.exe
#
# Prerequisites: .NET 8 SDK, Inno Setup (auto-detected or specify path)
# Usage: .\build.ps1

param(
    [string]$Configuration = "Release",
    [switch]$SkipFFmpeg,
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Join-Path $ScriptDir "CropawayWindows"
$PublishDir = Join-Path $ScriptDir "publish"
$FFmpegDir = Join-Path $ScriptDir "ffmpeg-bin"
$OutputDir = Join-Path $ScriptDir "output"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Cropaway Windows Build" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Download FFmpeg ---
if (-not $SkipFFmpeg) {
    Write-Host "[1/4] Downloading FFmpeg..." -ForegroundColor Yellow

    if (-not (Test-Path $FFmpegDir)) {
        New-Item -ItemType Directory -Path $FFmpegDir | Out-Null
    }

    $ffmpegExe = Join-Path $FFmpegDir "ffmpeg.exe"
    $ffprobeExe = Join-Path $FFmpegDir "ffprobe.exe"

    if ((Test-Path $ffmpegExe) -and (Test-Path $ffprobeExe)) {
        Write-Host "  FFmpeg already downloaded, skipping." -ForegroundColor Green
    } else {
        $ffmpegUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
        $zipPath = Join-Path $ScriptDir "ffmpeg-download.zip"
        $extractDir = Join-Path $ScriptDir "ffmpeg-extract"

        Write-Host "  Downloading from $ffmpegUrl ..."
        Invoke-WebRequest -Uri $ffmpegUrl -OutFile $zipPath -UseBasicParsing

        Write-Host "  Extracting..."
        if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
        Expand-Archive -Path $zipPath -DestinationPath $extractDir

        # Find the bin directory inside the extracted archive
        $binDir = Get-ChildItem -Path $extractDir -Recurse -Directory -Filter "bin" | Select-Object -First 1
        if ($binDir) {
            Copy-Item (Join-Path $binDir.FullName "ffmpeg.exe") $ffmpegExe
            Copy-Item (Join-Path $binDir.FullName "ffprobe.exe") $ffprobeExe
            Write-Host "  FFmpeg downloaded successfully." -ForegroundColor Green
        } else {
            Write-Error "Could not find FFmpeg binaries in downloaded archive."
            exit 1
        }

        # Cleanup
        Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "[1/4] Skipping FFmpeg download." -ForegroundColor DarkGray
}

# --- Step 2: Build the app ---
Write-Host ""
Write-Host "[2/4] Building Cropaway..." -ForegroundColor Yellow

dotnet publish $ProjectDir/CropawayWindows.csproj `
    -c $Configuration `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=false `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $PublishDir

if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed!"
    exit 1
}
Write-Host "  Build succeeded." -ForegroundColor Green

# --- Step 3: Bundle FFmpeg into publish directory ---
Write-Host ""
Write-Host "[3/4] Bundling FFmpeg..." -ForegroundColor Yellow

$ffmpegDest = Join-Path $PublishDir "ffmpeg"
if (-not (Test-Path $ffmpegDest)) {
    New-Item -ItemType Directory -Path $ffmpegDest | Out-Null
}

if (Test-Path (Join-Path $FFmpegDir "ffmpeg.exe")) {
    Copy-Item (Join-Path $FFmpegDir "ffmpeg.exe") (Join-Path $ffmpegDest "ffmpeg.exe") -Force
    Copy-Item (Join-Path $FFmpegDir "ffprobe.exe") (Join-Path $ffmpegDest "ffprobe.exe") -Force
    Write-Host "  FFmpeg bundled into app directory." -ForegroundColor Green
} else {
    Write-Warning "  FFmpeg binaries not found in $FFmpegDir. App will require FFmpeg on PATH."
}

# --- Step 4: Create installer ---
if (-not $SkipInstaller) {
    Write-Host ""
    Write-Host "[4/4] Creating installer..." -ForegroundColor Yellow

    # Find Inno Setup
    $innoPath = $null
    $innoPaths = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 5\ISCC.exe"
    )
    foreach ($p in $innoPaths) {
        if (Test-Path $p) { $innoPath = $p; break }
    }

    if ($innoPath) {
        if (-not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir | Out-Null
        }

        $issFile = Join-Path $ScriptDir "installer.iss"
        & $innoPath $issFile

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Installer created in $OutputDir" -ForegroundColor Green
        } else {
            Write-Error "Inno Setup failed."
        }
    } else {
        Write-Warning "  Inno Setup not found. Install it from https://jrsoftware.org/isdl.php"
        Write-Warning "  You can still run the app directly from: $PublishDir\Cropaway.exe"
    }
} else {
    Write-Host "[4/4] Skipping installer." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Build complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Run directly: $PublishDir\Cropaway.exe" -ForegroundColor White
if (Test-Path $OutputDir) {
    $setupFile = Get-ChildItem $OutputDir -Filter "CropawaySetup*.exe" | Select-Object -First 1
    if ($setupFile) {
        Write-Host "  Installer:    $($setupFile.FullName)" -ForegroundColor White
    }
}
Write-Host "========================================" -ForegroundColor Cyan
