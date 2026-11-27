# VIctory on Intel Arc & Linux (fork of VIctory-7900XTX)

A fork of [VIctory](https://github.com/Marvisak/VIctory) (via
[VIctory-7900XTX](https://github.com/avatarmanz/VIctory-7900XTX) /
[Belobug/VIctory-Belobug-AMD](https://github.com/Belobug/VIctory-Belobug-AMD)),
a compatibility layer that runs an Xbox Series title natively on Windows — and
on Linux via Proton + `vkd3d-proton` — from files the user supplies.

## The goal

**A stable 30 fps or more without ray tracing, then as high a frame rate and as
low frame times as the PC allows**, on an AMD RX 7900 XTX first and on PCs with
32 GB (later 16 GB) of RAM.

The way there is **porting, not emulating**: patching the title's renderer so it
behaves the way a PC renderer does, rather than having the layer watch and copy
the console's shared memory every frame. Shaders are translated ahead of time
into a versioned store that is kept between builds. Ray tracing stays optional
and off by default. The picture comes after the frame rate: texture pop-in and
lighting that is too bright or too dark when walking indoors are next in line.

**This repository contains no game files, code or assets.** You need your own
copy of the game. It is not affiliated with or endorsed by the game's developer
or publisher.

## Where it stands (2026-11-26)

The measurements below come from one Windows 11 PC with an Intel i9-12900K,
64 GB of system RAM and a Radeon RX 7900 XTX (24 GB of dedicated video memory).
Ray tracing was off for these runs.

| | |
|---|---|
| City street, Series S profile, renderer patches 1, 2, 5, 6 and 7 on | about 45 ms a frame (about 22 fps, 44.9 ms in run merge-5) |
| Same, patches 1, 2, 5 and 6 | 45.6 ms, p95 47 ms |
| Same, patches 1, 2 and 5 | 47.3 ms (about 21 fps), p95 49 ms |
| Series X profile, patches 1+2 | about 53 ms (about 19 fps) |
| Same scene before the patches | 57-75 ms (13-17 fps) |
| Shaders the title uses that translate | all of them (25,790 of 25,985; the rest are unused geometry shaders) |
| Memory | about 30 GB of private memory, 10.5 GB of VRAM: **64 GB of RAM recommended** for now |

It started at 280 ms a frame in the same scenes three days earlier. What sets
the frame now is the one thread that submits the title's work to the card
(about 40 ms); the card itself needs about 36 ms and now waits about 7 ms a frame with nothing queued.

### Reports from other GPUs

| GPU and build | What the contributor observed |
|---|---|
| Radeon RX 9060 XT (16 GB), `cd8dfc0` with local changes | In the same Series X interior at 1080p, the game averaged 19.8 fps with ray tracing off and 15.6 fps with it on. Indirect lighting showed white patches and dark smears. [Run settings and results](https://github.com/Belobug/VIctory-Belobug-AMD/issues/313) |
| GeForce RTX 3090 (24 GB), `a-publier@cd8dfc0` | The prison rendered. Two warm Series S runs averaged 545 and 532 ms per frame. The contributor reported 10.0 and 10.2 GB of VRAM in those runs. [Run settings and results](https://github.com/Belobug/VIctory-Belobug-AMD/issues/333) |
| Intel Arc B580 (12 GB), revision unreported | Startup and initial menu navigation worked. Further menu interaction slowed to about 0.7 fps before D3D12 device removal. [Crash report](https://github.com/Belobug/VIctory-Belobug-AMD/issues/98) |
| Intel Arc B570 (10 GB), Linux (Arch, Mesa 26.2.5 ANV, GE-Proton11-14 + vkd3d-proton), Ryzen 5 5600, 32 GB RAM + 46 GB swap | **3D world renders (prison opening scene, guard tower, sky, credits, audio, Prologue pause menu, zero device removals)** once native Microsoft `d3dcompiler_47.dll` is installed in the Proton prefix (`winetricks -q d3dcompiler_47` + `WINEDLLOVERRIDES="d3dcompiler_47=n,b"`). Menus run at locked 30 fps (~3% GPU); 3D world reached 3,836 draws/frame and 1.6–2.5 fps during first-run pipeline compilation (~1,125 pipelines `being made`, 9,322 / 9,405 MB VRAM used on Series X, ~22 GB RAM). Only 3 compute shaders refused out of 25,790. Without native `d3dcompiler_47.dll`, Wine's built-in compiler fails on VIctory's internal HLSL shaders (dropping all indirect world draws, ambient lighting, depth twins, and the Series S two-plane composer). |

The 10.5 GB of VRAM in the RX 7900 XTX table is the usage reported for that run.
Memory use and frame time depend on the scene and settings. The [ray-tracing notes](docs/fork-ray-tracing.md)
describe which lighting paths run and the remaining rendering issues.

### Renderer patches (off by default while they are tested)

| Switch | What it does |
|---|---|
| `VICTORY_PORT_CONSTANTS=1` | The title's 174 MB constants heap is read by the card where the title writes it: no uploads, no fills |
| `VICTORY_PORT_DESCRIPTORS=1` | The title's descriptor-table stores are patched (byte-checked) to report the slots they write, instead of a scan of ~600,000 slots a frame |
| `VICTORY_PORT_CBV=1` | Translated shaders read constant buffers in place as raw bytes (~22,000 fills a frame to none; -4.7 ms) |
| `VICTORY_PORT_GUARD=1` | The write guards' lock is shared by faults and refreshes, with a claim per 64 KiB block; the submission's planning runs beside it (title threads' waits 29 ms to ~2 ms a frame; -2 ms) |
| `VICTORY_PORT_JOURNAL=1` | The heaps' records are asked for at the title's submit, and the journal's notes are split into 64 parts with locks of their own (the submit thread's waits ~5 ms + 1 ms to ~0.3 ms; -1 to -3 ms) |

### Other switches

| Switch | What it does |
|---|---|
| `--console series-s` | The Series S profile: 1080p output, about 5 ms faster, a softer picture |
| `VICTORY_OUTPUT=1920x1080` | The title renders to that output size itself (Series X profile; about 16 ms less card time) |
| `VICTORY_FRAME_INTERVAL_MS=16.667` | Lets the title go above 30 fps (menus and videos reach 60; the game's clock stays right) |
| `VICTORY_AMBIENT_SETTLE` | How fast light settles after walking indoors (on by default, `250,3`; `0` turns it off) |
| `VICTORY_TEXTURE_STORE=1` | Converted textures kept between runs (about 8 ms a frame for now: off) |
| `VICTORY_KBM_GTA=1` | Optional GTA V PC-style keyboard and mouse mapping on the stand-in pad: `F2` or `` ` `` (`~`) toggles mouse-look and auto-hides the cursor while locked (`Esc`/`P`/focus loss unlocks and restores it), LMB/RMB = RT/LT, MMB/`C` = R3, `Shift` = A, `Space` = X, `R` = B, `F` = Y, `Tab` = LB, `Q` = RB, `Ctrl` = L3, `E` = D-pad Right, `V` = View. Tune with `VICTORY_MOUSE_SENS` (default `1.0`) and `VICTORY_MOUSE_INVERT_Y=1` (or pass via `scripts\play.ps1 -More @{VICTORY_KBM_GTA='1'}`) |

What is known to be wrong:

- Trees, signs and far objects flicker in the distance in some places.
- Lighting is too bright or too dark after walking indoors, until the title has
  run for a while; rooms with little direct light are too dark without `-RayTracing`.
- Textures of what just came into view appear late while the title streams.
- The first run of a new build stutters while the driver makes pipelines
  (`victory warm` makes them ahead).
- Recording a frame in the world makes the title's own watchdog end it.

## How to run it

You need Windows 10/11 x64, a CPU with AVX2, a Direct3D 12 GPU with shader
model 6.6 and mesh shaders, Rust (the toolchain is pinned), the MSVC build
tools, and your own dump of the title.

```powershell
git clone https://github.com/niiithish/VIctory-Belobug-intel
cd VIctory-Belobug-intel
copy victory.example.toml victory.toml      # then set your paths, outside this folder
cargo build --locked --profile diag -p victory --features diagnostics
scripts\play.ps1 -Exe <path of your copy's executable>
```

The launcher requests light device removal diagnostics (DRED) by default with
`-Build diag`. DRED requires `--features diagnostics`. For a release binary
built with that feature, request DRED with
`-Build release -More @{VICTORY_D3D12_DRED='light'}`.

`scripts\play.ps1 -Safe` leaves out the newest, faster ways; try it first when
something is wrong. `-RayTracing` turns the title's ray-traced indirect light on.

For PC FSR 4.1.2, set `[paths].fidelityfx_dir` in `victory.toml` or
`VICTORY_FIDELITYFX_DIR` to the folder containing AMD's signed
`amd_fidelityfx_upscaler_dx12.dll`. Use the DirectX 12 upscaler in
`Kits/FidelityFX/signedbin`. [AMD FSR SDK 2.4.0](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/tree/v2.4.0/Kits/FidelityFX/signedbin)

`scripts\play.ps1 -Exe <path> -Fsr4K quality` selects 2560×1440 input for
the retail 1.0.2.1 Series X 4K SDR profile. `balanced` selects 2258×1270
and `performance` selects 1920×1080. All three output 3840×2160. With
`victory run` directly, set `VICTORY_FSR_4K` to the preset name.
AMD's SDK offers FSR 4.1.2 for some cards only. Where it does not, the
newest FSR 3.1 it offers is used in its place and the log says so; its
picture differs from FSR 4's. Where it offers neither, the run stops
before the title starts and names the versions that were offered.
The log reports the provider at context creation and the actual input and
output sizes at the first successful temporal dispatch. The title profile
and PC FidelityFX bridge were ported from [DexNom/VIctory](https://github.com/DexNom/VIctory/commit/ab34a8b21477c94da2a6cf07249138e8bc84602e).

On a hybrid-graphics PC, the runtime and offline pipeline checks prefer a
high-performance adapter with Shader Model 6.6. The runtime logs its adapter
name, PCI vendor and device IDs, and dedicated VRAM. Set
`VICTORY_D3D12_ADAPTER` to a zero-based DXGI index or part of the adapter's
name to select it explicitly. With the launcher, pass
`-More @{VICTORY_D3D12_ADAPTER='NVIDIA'}`.

Before the first run, ahead of time (both can be stopped and go on later):

```powershell
target\diag\victory.exe shaders <the shader archives>   # every shader translated, minutes
target\diag\victory.exe warm --used                     # pipelines earlier runs drew with, for a new driver or build
```

Commands, debugging switches and upstream's own description:
[docs/README-fxceless.md](docs/README-fxceless.md). Every `VICTORY_...` switch is
described in a comment where it is read.

## Running on Linux (Proton / vkd3d-proton)

`victory run` and `victory warm` target Windows (`x86_64-pc-windows-msvc`), so on
Linux you cross-compile `victory.exe` with `cargo-xwin` and launch it through
`umu-run` (GE-Proton + `vkd3d-proton` for Direct3D 12 Shader Model 6.6 and mesh
shaders).

### Required packages

On Arch Linux (adjust package names for your distro):

```bash
# Cross-compilation linker & LLVM tools
sudo pacman -S lld clang llvm

# Proton/vkd3d-proton launcher + winetricks + Vulkan driver (pick your GPU driver)
sudo pacman -S umu-launcher winetricks vulkan-intel   # or vulkan-radeon / nvidia-utils

# Rust Windows MSVC target + cargo-xwin
rustup target add x86_64-pc-windows-msvc
cargo install --locked cargo-xwin
```

### Build, install native `d3dcompiler_47`, and configure

```bash
cp victory.example.toml victory.toml   # set game_dir, cache_dir, data_dir outside the repo
cargo xwin build --locked --profile diag --target x86_64-pc-windows-msvc -p victory --features diagnostics

# Initialize the prefix once (downloads GE-Proton + steamrt4), then install native d3dcompiler_47:
./scripts/play-linux.sh --dry-run
WINEPREFIX="$HOME/.local/share/umu/prefixes/victory" winetricks -q d3dcompiler_47
```

> **Why native `d3dcompiler_47` is required on Linux:** Wine's built-in
> `d3dcompiler_47.dll` fails to compile 4 of VIctory's internal HLSL shaders
> (`RWByteAddressBuffer.InterlockedOr` in the indirect argument clamp, `isnan()`
> in the ambient stand-in, the depth-twin copy shader, and `vs_5_1`
> `[RootSignature]` in the Series S two-plane composer). Without Microsoft's
> native `d3dcompiler_47.dll` (`WINEDLLOVERRIDES="d3dcompiler_47=n,b"`, set
> automatically by `scripts/play-linux.sh`), all indirect 3D world draws are
> dropped and you only see sky + UI.

### Launch (`scripts/play-linux.sh`)

[scripts/play-linux.sh](scripts/play-linux.sh) reads your paths from `victory.toml`,
converts them to Wine `Z:\` paths, keeps `vkd3d-proton.cache` in `$CACHE_DIR/vkd3d`
(outside the repo), and applies defaults tuned for 10 GB VRAM / 32 GB RAM / 6-core CPUs:

```bash
./scripts/play-linux.sh --shaders          # pre-translate shaders.rpf (~45-60 s on a 6-core CPU)
./scripts/play-linux.sh --dry-run          # verify PE loading/binding without executing
./scripts/play-linux.sh --safe --kbm       # conservative first boot (F2 or ` toggles mouse-look)
./scripts/play-linux.sh --kbm              # standard fast flags (VICTORY_THIN=1, THIN_THREADS=6)
./scripts/play-linux.sh --kbm --log        # same, saving full untruncated logs to ~/.cache/victory/cache/victory.log
./scripts/play-linux.sh --ports --kbm      # also enable renderer patches 1, 2, 5, 6, 7
./scripts/play-linux.sh --warm             # warm driver pipelines after a run
```

### Resource usage & Linux / Intel Arc notes

- **RAM & swap:** Observed ~22 GB RAM during menus and initial world load on a 32 GB
  system (with 46 GB swap configured for headroom). Ensure you have generous swap if
  running on 32 GB RAM.
- **10 GB VRAM (Intel Arc B570):** `scripts/play-linux.sh` enables
  `VICTORY_LEVELS_ON_DEMAND=1` (saves ~2.2–3.0 GB VRAM), `VICTORY_OUTPUT=1920x1080`,
  and `VICTORY_CARD_BUFFERS_MIN_MB=1` / `VICTORY_CARD_BUFFERS_MB=512` (leaves VRAM
  headroom alongside ~1.5 GB used by the desktop while offloading large buffer checks).
- **Series S vs Series X on Linux:** With native `d3dcompiler_47.dll` installed,
  both `--console series-x` (default, 1080p) and `--console series-s` (lower VRAM
  footprint, ~5 ms faster) work. On 10 GB cards (where Series X reaches ~9.3 / 9.4 GB
  VRAM), try `--console series-s` to reduce texture eviction pressure.
- **First-run pipeline compilation:** The first time you enter the world, ~1,100+
  pipelines compile on background threads (`being made`), causing low initial FPS
  (~2 fps) and missing objects until they finish. Run with `VICTORY_PIPELINE_BOOK=1`
  and then `./scripts/play-linux.sh --warm` to pre-build them into the driver cache.
- **Note on `--ports` (`VICTORY_PORT_CBV=1`):** `VICTORY_PORT_CBV=1` changes the shader
  cache key; if you pre-translated shaders without `--ports`, test `./scripts/play-linux.sh --kbm`
  first or re-run `./scripts/play-linux.sh --ports --shaders`.

## What is different here

In short; the reasons and the measurements are in [docs/findings.md](docs/findings.md).

- **List calls are written down, not carried out, on the title's threads**
  (`VICTORY_THIN`): eight threads of ours translate them.
- **Submissions are prepared by a thread of ours and joined**
  (`VICTORY_ASYNC_SUBMIT`, `VICTORY_JOIN_PARTS`), with what can be spread over
  threads spread: refreshes, compares (AVX2), descriptor records, landings.
- **What shaders wrote comes back beside the write guards**, by the dwords that
  changed, on a thread of its own (`VICTORY_RELAY`, `VICTORY_LAND`).
- **Buffer fills that need bytes still on the card are done on the card**
  (`VICTORY_CARD_STEPS`) instead of waiting for it.
- **The title's writes are caught more cheaply**: one view opened at a fault,
  blocks that rest, places in the title's code that look before they write.
- **Textures go up on a copy queue of their own** and a slot shows one only after
  its upload ran, which also ended a device loss that came every 15 minutes or so.
- **Boats float**: textures that shaders write and the title's CPU reads go back
  to title memory (from fxceless and Geckomacabre, on by default here).
- **Frame record and replay** with per-pass times and shader variants compared
  turn by turn ([docs/replay.md](docs/replay.md)).

## Credits

This is a tree of other people's work with more on top. The history is kept, and
commits taken from elsewhere name the commit and its author.

- **[VIctory](https://github.com/Marvisak/VIctory)** by Marvisak and its
  contributors: the loader, the runtime services, the Direct3D 12 back end and
  the shader recompiler.
- **[fxceless/victory-fork](https://github.com/fxceless/victory-fork)**: the fork
  this one started from, and the people whose pull requests it carries.
- **[DexNom/VIctory](https://github.com/DexNom/VIctory)**: ray tracing fixes,
  cube gradients, sparse textures.
- **[Belobug/VIctory-Belobug-AMD](https://github.com/Belobug/VIctory-Belobug-AMD)**:
  the ambient light idea, pipeline workers, and work by romainhedouin.
- **[FQY55kai/ZJOU-VICTORY](https://github.com/FQY55kai/ZJOU-VICTORY)**.
- **[myokex/victory-amd](https://github.com/myokex/victory-amd)**: the guard over
  every view of a page (with Spexivus, joroyt and tightfall), and Joshua Odom's
  reads into title memory.
- **Geckomacabre** and **cxy0072019-sketch**: the texture read-back.
- **[XCL](https://github.com/ivall/xcl)** (GPL-2.0-only) was read for how the same
  title behaves under another layer; no code of it is here.
- This fork's changes were made with [Claude Code](https://claude.com/claude-code).

## License

GPL-3.0-or-later, as VIctory. See [LICENSE](LICENSE); the one file that is not
covered is named in [docs/asset-policy.md](docs/asset-policy.md).
