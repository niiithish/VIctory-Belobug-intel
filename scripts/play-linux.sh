#!/usr/bin/env bash
# Linux launcher for VIctory via umu-run (GE-Proton + vkd3d-proton).
# Tuned for Intel Arc B570 (10 GB VRAM), 32 GB RAM, AMD Ryzen 5 5600 (6C/12T).
#
# Usage:
#   scripts/play-linux.sh [options]
#
# Modes:
#   --safe          Conservative flags (no THIN/JOIN_PARTS/UPLOAD_AHEAD). Good for first test on Arc.
#   --fast          Standard fork flags (default, mirrors scripts/play.ps1 with THIN_THREADS=6).
#   --ports         Also enable renderer patches 1,2,5,6,7 (VICTORY_PORT_*).
#   --console MODE  series-s (default, best for 10 GB VRAM) or series-x (sets 1920x1080 output).
#   --kbm           Enable GTA V PC-style keyboard/mouse controls (VICTORY_KBM_GTA=1; F2 or ` toggles mouse-look).
#   --rt            Enable ray-traced indirect light (VICTORY_BVH_BUILDER=1; higher VRAM/GPU cost).
#   --build TYPE    diag (default, enables light DRED) or release.
#   --exe PATH      Path to game_scarlett_master.exe (default: $VICTORY_GAME_DIR/game_scarlett_master.exe).
#   --runner PATH   Override victory.exe path (default: target/x86_64-pc-windows-msvc/<build>/victory.exe).
#   --shaders       Pre-translate shaders.rpf ahead of time instead of launching the game.
#   --warm          Pre-build driver pipelines from previous runs (victory warm --used).
#   --dry-run       Load and bind the executable without executing it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

toml_path() {
    local key="$1"
    if [[ -f "$REPO_ROOT/victory.toml" ]]; then
        sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" "$REPO_ROOT/victory.toml" | head -n 1
    fi
}

GAME_DIR="${VICTORY_GAME_DIR:-$(toml_path game_dir)}"
CACHE_DIR="${VICTORY_CACHE_DIR:-$(toml_path cache_dir)}"
DATA_DIR="${VICTORY_DATA_DIR:-$(toml_path data_dir)}"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/victory/cache}"
DATA_DIR="${DATA_DIR:-$HOME/.local/share/victory/data}"

MODE="fast"
PORTS=0
CONSOLE="series-x"
KBM=0
RT=0
BUILD="diag"
ACTION="run"
EXE=""
RUNNER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --safe)     MODE="safe"; shift ;;
        --fast)     MODE="fast"; shift ;;
        --ports)    PORTS=1; shift ;;
        --console)  CONSOLE="$2"; shift 2 ;;
        --kbm)      KBM=1; shift ;;
        --rt)       RT=1; shift ;;
        --build)    BUILD="$2"; shift 2 ;;
        --exe)      EXE="$2"; shift 2 ;;
        --runner)   RUNNER="$2"; shift 2 ;;
        --shaders)  ACTION="shaders"; shift ;;
        --warm)     ACTION="warm"; shift ;;
        --dry-run)  ACTION="dry-run"; shift ;;
        -h|--help)
            sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

EXE="${EXE:-$GAME_DIR/game_scarlett_master.exe}"
RUNNER="${RUNNER:-$REPO_ROOT/target/x86_64-pc-windows-msvc/$BUILD/victory.exe}"

if [[ ! -f "$RUNNER" ]]; then
    echo "Missing $RUNNER." >&2
    echo "Build it first with:" >&2
    echo "  cargo xwin build --locked --profile $BUILD --target x86_64-pc-windows-msvc -p victory --features diagnostics" >&2
    exit 1
fi

if [[ "$ACTION" == "run" || "$ACTION" == "dry-run" ]] && [[ ! -f "$EXE" ]]; then
    echo "Missing game executable: $EXE" >&2
    exit 1
fi

mkdir -p "$CACHE_DIR" "$CACHE_DIR/vkd3d" "$DATA_DIR"

# Keep vkd3d-proton's shader cache outside the git repository.
export VKD3D_SHADER_CACHE_PATH="${VKD3D_SHADER_CACHE_PATH:-$CACHE_DIR/vkd3d}"

# Convert Linux absolute paths to Wine Z:\ paths so Windows victory.exe resolves them cleanly.
to_win_path() {
    local p="$1"
    printf 'Z:%s' "${p//\//\\}"
}

export GAMEID="${GAMEID:-0}"
export PROTONPATH="${PROTONPATH:-GE-Proton}"
export WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/umu/prefixes/victory}"
mkdir -p "$WINEPREFIX"

export VICTORY_GAME_DIR="$(to_win_path "$GAME_DIR")"
export VICTORY_CACHE_DIR="$(to_win_path "$CACHE_DIR")"
export VICTORY_DATA_DIR="$(to_win_path "$DATA_DIR")"

# Base settings mirroring scripts/play.ps1
export VICTORY_TEXTURE_NO_WAIT=1
export VICTORY_RELAY=2
export VICTORY_WIDE_BACK=1
export VICTORY_CARD_REHASH_RUNS=1
export VICTORY_JOIN_COPIES=1
export VICTORY_INDIRECT_WINDOW=1
export VICTORY_RELAY_COPY=1
export VICTORY_CARD_STEPS=2
export VICTORY_INDIRECT_BATCH=2
export VICTORY_MAP_THREADS=1
export VICTORY_TITLE_PRIORITIES=0
export VICTORY_CARD_AWAKE=1
export VICTORY_SHOW_AFTER=1
export VICTORY_AMBIENT=0.8

# Arc B570 (10 GB VRAM): allocate only texture mip levels held by the title (~2.2-3 GB VRAM saved),
# and move >=1 MiB buffer write-checks onto the GPU instead of scanning 2+ GB/frame on the CPU.
export VICTORY_LEVELS_ON_DEMAND="${VICTORY_LEVELS_ON_DEMAND:-1}"
export VICTORY_CARD_BUFFERS_MIN_MB="${VICTORY_CARD_BUFFERS_MIN_MB:-1}"
export VICTORY_CARD_BUFFERS_MB="${VICTORY_CARD_BUFFERS_MB:-1024}"

# Explicit Intel adapter preference (optional override via env).
export VICTORY_D3D12_ADAPTER="${VICTORY_D3D12_ADAPTER:-Intel}"

if [[ "$BUILD" == "diag" ]]; then
    export VICTORY_D3D12_DRED="${VICTORY_D3D12_DRED:-light}"
fi

if [[ "$MODE" == "safe" ]]; then
    export VICTORY_UNDER_WIDE=0
    export VICTORY_LAND_ECHO=0
    unset VICTORY_THIN VICTORY_JOIN_PARTS VICTORY_UPLOAD_AHEAD || true
else
    export VICTORY_THIN=1
    # Ryzen 5 5600 (6C/12T): 6 workers avoids oversubscribing alongside title + submit/relay threads.
    export VICTORY_THIN_THREADS="${VICTORY_THIN_THREADS:-6}"
    export VICTORY_JOIN_PARTS=8
    export VICTORY_UPLOAD_AHEAD=1
fi

if [[ "$PORTS" == "1" ]]; then
    export VICTORY_PORT_CONSTANTS=1
    export VICTORY_PORT_DESCRIPTORS=1
    export VICTORY_PORT_CBV=1
    export VICTORY_PORT_GUARD=1
    export VICTORY_PORT_JOURNAL=1
fi

if [[ "$CONSOLE" == "series-x" ]]; then
    export VICTORY_OUTPUT="${VICTORY_OUTPUT:-1920x1080}"
fi

if [[ "$KBM" == "1" ]]; then
    export VICTORY_KBM_GTA=1
fi

if [[ "$RT" == "1" ]]; then
    export VICTORY_BVH_BUILDER=1
fi

cd "$REPO_ROOT"

WIN_EXE="$(to_win_path "$EXE")"
WIN_SHADERS="$(to_win_path "$GAME_DIR/shaders.rpf")"

case "$ACTION" in
    shaders)
        echo "Pre-translating shaders from $WIN_SHADERS ..."
        exec umu-run "$RUNNER" shaders "$WIN_SHADERS"
        ;;
    warm)
        echo "Warming driver pipelines (--used) ..."
        exec umu-run "$RUNNER" warm --used
        ;;
    dry-run)
        echo "Dry-run binding $WIN_EXE (--console $CONSOLE) ..."
        exec umu-run "$RUNNER" run "$WIN_EXE" --console "$CONSOLE"
        ;;
    run)
        echo "Launching VIctory ($BUILD, mode=$MODE, ports=$PORTS, console=$CONSOLE, kbm=$KBM, rt=$RT) ..."
        exec umu-run "$RUNNER" run "$WIN_EXE" --console "$CONSOLE" --execute
        ;;
esac
