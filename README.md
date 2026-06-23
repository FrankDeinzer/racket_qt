# racket-qt

Spike: Qt Widgets backend ("qt") for `racket/gui`, activated via `PLT_QT=1`.

## Environment

| | |
|---|---|
| Qt | 6.11.0 |
| CMake | ≥ 3.21 |
| Racket | ≥ 8.18 |

## Build (Windows x64)

```powershell
# Qt must be on PATH so racket can find the DLLs at runtime
$env:PATH = "C:\Qt\6.11.0\msvc2022_64\bin;" + $env:PATH

cmake --preset windows-x64 -S qt-shim
cmake --build qt-shim/build/windows-x64 --config Debug
```

## Run

```powershell
$env:PLT_QT = "1"
$env:PATH   = "C:\Qt\6.11.0\msvc2022_64\bin;" + $env:PATH
racket examples/hello.rkt
```

## macOS (arm64/x64)

```sh
cmake --preset macos-arm64 -S qt-shim   # or macos-x64
cmake --build qt-shim/build/macos-arm64
PLT_QT=1 racket examples/hello.rkt
```

RPATH is baked into the dylib; no `DYLD_LIBRARY_PATH` needed.

## Linux (x64)

```sh
cmake --preset linux-x64 -S qt-shim
cmake --build qt-shim/build/linux-x64
PLT_QT=1 racket examples/hello.rkt
```

RPATH is baked into the .so; no `LD_LIBRARY_PATH` needed.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
