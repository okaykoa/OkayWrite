# Installing the OkayWrite build on a Kindle

Step-by-step for putting this OkayWrite version of KOReader onto a jailbroken Kindle.

> Two important facts up front:
> 1. **KPM (`;kpm install koreader`) will NOT install this build** — it pulls the
>    official KOReader. To get the OkayWrite version you must copy our files
>    manually (Option B) or drop the patch onto an existing install (Option A).
> 2. **If KOReader is already on your Kindle, use Option A** — it's one file,
>    instant, and trivially reversible.

> All commands below are run **from the repository root** (the folder containing
> `build.sh`). Adjust the Kindle mount path (`/Volumes/Kindle`) for your OS.

---

## Which package matches your Kindle

- **Firmware 5.16.3 or newer** → `kindlehf` (built: `dist/okaywrite-kindlehf-v2026.07.1.zip`)
- **Touchscreen, firmware 5.16.2 or older** → `kindlepw2` (build with `./build.sh kindlepw2`)

Check firmware on the device: **Settings → Menu → Device Info** (or
**Settings → Device Options → Device Info**).

---

## Option A — Recommended: patch your existing KOReader (fastest, reversible)

Use this if KOReader is already installed.

1. Connect the Kindle by USB. It mounts at **`/Volumes/Kindle`** (adjust if named differently).
2. Copy the patch in (creating the `patches` folder if needed), from the repo root:
   ```sh
   mkdir -p /Volumes/Kindle/koreader/patches
   cp overlay/koreader/patches/2-okaywrite.lua /Volumes/Kindle/koreader/patches/
   ```
3. Safely eject:
   ```sh
   diskutil eject /Volumes/Kindle
   ```
4. On the Kindle, launch KOReader as usual (KUAL/KUALA/scriplet → *Start KOReader*).
5. **To undo:** delete `/mnt/us/koreader/patches/2-okaywrite.lua`, or drop an empty file
   named `.patches_disabled` into that folder.

---

## Option B — Full install of the standalone "OkayWrite" package

Use this for a fresh device, or if you want the rebranded "OkayWrite" launcher entry.

1. **Build the package** (if not already in `dist/`), from the repo root:
   ```sh
   ./build.sh kindlehf        # or: ./build.sh kindlepw2
   ```
2. Connect the Kindle by USB (`/Volumes/Kindle`).
3. **Extract our zip to the USB root** so `koreader/` and `extensions/` land at the top
   level (overwrites an existing KOReader install; settings under `koreader/` are kept):
   ```sh
   unzip -o dist/okaywrite-kindlehf-v2026.07.1.zip -d /Volumes/Kindle/
   ```
   Result: `/Volumes/Kindle/koreader/` and `/Volumes/Kindle/extensions/koreader/`.
4. **Ensure a launcher exists.** If you already ran KOReader, reuse it. On a fresh
   device, install one per your jailbreak (our zip does not include it):
   - Firmware **5.16.3+**: KUALA — https://github.com/kasparcode/kuala/releases
     (extract `documents` and `kuala` folders to the USB root).
   - Firmware **< 5.16.3**: KUAL, or a launcher scriplet from
     https://scriptlets.notmarek.com/ placed in `documents/`.
5. Safely eject: `diskutil eject /Volumes/Kindle`.
6. On the Kindle, open your launcher and select **“Start OkayWrite”**.

---

## Verify it worked (either option)

- KOReader opens into an **OkayWrite** file browser (the `/mnt/us/OkayWrite` folder,
  created on first run).
- Tapping a `.txt` or `.md` opens the **Text editor**, not the reader.
- If something's off, check `/mnt/us/koreader/crash.log` for a line containing
  `[OkayWrite] reskin applied` — present = patch ran; absent = patch not loaded.

---

## Caveats

- Don't switch to USB-drive (USBMS) mode while KOReader is running.
- This build has not been runtime-tested. Prefer Option A first: it's one file and
  trivially reversible, so a misbehaving reskin risks nothing.

---

## Bluetooth keyboard (optional)

OkayWrite makes a physical keyboard type correctly (including shifted
punctuation), but it does not pair the keyboard itself — Kindle's stock
Bluetooth stack cannot. Pairing is handled outside OkayWrite by
**kindle-hid-passthrough** (https://github.com/zampierilucas/kindle-hid-passthrough),
which must be installed separately (install `usbnetlite` first as a recovery net,
and use its minimal daemon + KOReader-plugin path — not the full installer).

Once a keyboard is paired and connected, OkayWrite's layout patch handles typing;
no configuration is needed. US layout is provided by default.
