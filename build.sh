#!/usr/bin/env bash
#
# build.sh -- assemble an "OkayWrite" Kindle package from a stock KOReader release.
#
# No compilation: this downloads an official prebuilt KOReader Kindle zip and
# layers our overlay (the OkayWrite userpatch + light rebrand) on top, producing
# a ready-to-install zip under dist/.
#
# Usage:
#   ./build.sh                 # build all generations in GENERATIONS_DEFAULT
#   ./build.sh kindlehf        # build a single generation
#
set -euo pipefail

# --- Configuration ---------------------------------------------------------
# Pin to a specific KOReader release for reproducible builds. Bump this
# deliberately (and re-test) rather than tracking a moving target.
KO_VERSION="v2026.07.1"

# Kindle generations to build. kindlehf = newer hard-float models;
# kindlepw2 = Paperwhite-era touch models. Add "kindle"/"kindle-legacy" if needed.
GENERATIONS_DEFAULT=("kindlehf" "kindlepw2")

APP_NAME="OkayWrite"   # KUAL menu label

# --- Paths -----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$SCRIPT_DIR/overlay"
CACHE_DIR="$SCRIPT_DIR/.cache"
DIST_DIR="$SCRIPT_DIR/dist"
BASE_URL="https://github.com/koreader/koreader/releases/download/$KO_VERSION"

mkdir -p "$CACHE_DIR" "$DIST_DIR"

if [[ $# -gt 0 ]]; then
    GENERATIONS=("$@")
else
    GENERATIONS=("${GENERATIONS_DEFAULT[@]}")
fi

prune_release() {
    local work="$1"
    local ko="$work/koreader"

    echo "    pruning to notepad-only"

    # Non-notepad plugins.
    while IFS= read -r plugin; do
        [[ -z "$plugin" || "$plugin" == \#* ]] && continue
        rm -rf "$ko/plugins/$plugin"
    done < "$OVERLAY_DIR/koreader/prune/plugins-delete.txt"

    # Cloud storage app (its one reachable menu entry is removed by
    # 2-okaywrite-menus.lua; this removes the underlying implementation too).
    rm -rf "$ko/frontend/apps/cloudstorage"

    # Non-EFIGS localization data (l10n/LICENSE and l10n/README.md are text
    # files, not language directories, and are left alone by the */ glob).
    for dir in "$ko/l10n"/*/; do
        local lang; lang="$(basename "$dir")"
        if ! grep -qx "$lang" "$OVERLAY_DIR/koreader/prune/l10n-keep.txt"; then
            rm -rf "$dir"
        fi
    done

    # Non-EFIGS on-screen keyboard layouts. generic_ime.lua is only used by
    # the CJK IME layouts already excluded above.
    local kb_dir="$ko/frontend/ui/data/keyboardlayouts"
    rm -f "$kb_dir/generic_ime.lua"
    for f in "$kb_dir"/*.lua; do
        local name; name="$(basename "$f")"
        if ! grep -qx "$name" "$OVERLAY_DIR/koreader/prune/keyboardlayouts-keep.txt"; then
            rm -f "$f"
        fi
    done
    for f in "$kb_dir/keypopup"/*.lua; do
        local name; name="keypopup/$(basename "$f")"
        if ! grep -qx "$name" "$OVERLAY_DIR/koreader/prune/keyboardlayouts-keep.txt"; then
            rm -f "$f"
        fi
    done
}

build_one() {
    local gen="$1"
    local zip_name="koreader-${gen}-${KO_VERSION}.zip"
    local url="$BASE_URL/$zip_name"
    local cached="$CACHE_DIR/$zip_name"
    local work; work="$(mktemp -d)"
    local out="$DIST_DIR/okaywrite-${gen}-${KO_VERSION}.zip"

    echo "==> [$gen] fetching $zip_name"
    if [[ ! -f "$cached" ]]; then
        curl -fL --progress-bar -o "$cached" "$url"
    else
        echo "    (using cached $cached)"
    fi

    echo "==> [$gen] extracting"
    unzip -q "$cached" -d "$work"

    prune_release "$work"

    echo "==> [$gen] applying overlay"
    # Copy overlay tree (patches/, etc.) into the extracted package.
    cp -R "$OVERLAY_DIR/"* "$work/"

    echo "==> [$gen] rebranding to $APP_NAME"
    # menu.json: every visible "KOReader" -> app name. Case-sensitive, so the
    # lowercase install paths (/mnt/us/koreader, koreader.sh, *_koreader params)
    # are deliberately left untouched.
    local menu="$work/extensions/koreader/menu.json"
    if [[ -f "$menu" ]]; then
        sed -i.bak "s/KOReader/$APP_NAME/g" "$menu"
        rm -f "$menu.bak"
    fi
    # config.xml: rebrand the extension name and id, but preserve upstream
    # authorship attribution (do not overwrite the KOReader Dev Team credit).
    local cfg="$work/extensions/koreader/config.xml"
    if [[ -f "$cfg" ]]; then
        sed -i.bak -E "s#<name>KOReader</name>#<name>$APP_NAME</name>#; s#<id>KOReader</id>#<id>$APP_NAME</id>#" "$cfg"
        rm -f "$cfg.bak"
    fi

    echo "==> [$gen] packaging -> $out"
    rm -f "$out"
    ( cd "$work" && zip -qr "$out" . )
    rm -rf "$work"
    echo "==> [$gen] done: $out"
}

for gen in "${GENERATIONS[@]}"; do
    build_one "$gen"
done

echo
echo "All packages written to $DIST_DIR/"
