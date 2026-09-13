# OkayWrite (KOReader-based Kindle writing app)

A focused, distraction-free **writing app for jailbroken Kindles**, built as a thin
"costume" over stock KOReader. No forking, no compiling: we ship KOReader's official
prebuilt Kindle binaries and layer a single userpatch that reskins it into a writing app.

> **OkayWrite is a modified version of [KOReader](https://github.com/koreader/koreader).**
> It is built on KOReader's official prebuilt binaries and is distributed under the same
> license (**AGPL-3.0**). OkayWrite is **not affiliated with or endorsed by** the KOReader
> project. All credit for the underlying reader belongs to the KOReader authors; this repo
> only adds a small overlay on top. See [LICENSE](LICENSE).

## Vision

OkayWrite aims to be a **lightweight writing device**: distraction-free text entry on
e-ink, driven primarily by a **Bluetooth keyboard** (with the on-screen keyboard fully
supported as a fallback), simple **multi-file management**, and an easy way to get
finished notes **off the device**.

**Strategy — overlay now, strip later.** Today OkayWrite ships KOReader's prebuilt binary
unchanged and reskins it via userpatches; "salvage what enables writing, discard the rest"
is achieved first by *hiding and disabling* the non-writing surfaces, not by forking. Over
time, if it earns its cost, the project may progressively strip toward a purpose-built
build — but light-touch overlay is the default until then.

## What it does (today)

- `.txt` and `.md` files open in KOReader's built-in **Text editor** on a single tap
  (KOReader already supports this; we just set it as the default).
- The file browser opens in a dedicated **`/mnt/us/OkayWrite`** folder.
- The app always boots into the file browser, never the reader.
- Keeps KOReader's ~60 UI localizations for free.

Everything reading-related (documents, PDF/EPUB engines, most plugins) is still technically
present in the binary but out of the way.

## Roadmap

| Area | Status | Notes |
|------|--------|-------|
| **On-screen keyboard** | ✅ works | KOReader's built-in Text editor keyboard. |
| **Bluetooth keyboard** | ✅ implemented (US layout, Shift incl. punctuation, terminal-style word/line movement) — pending on-device verification | OkayWrite provides a real US layout (Shift + AltGr) via userpatch, plus Alt+Left/Right (word jump) and Cmd+Left/Right (line start/end). Requires `kindle-hid-passthrough` for pairing. |
| **Multi-file management** | ✅ mostly | KOReader's FileManager, scoped to the writing folder (create / rename / organize `.txt`/`.md`). The "+" menu offers **New file**, and the editor has **Save as**. |
| **Export — USB copy** | ✅ works | Files are plain `.txt`/`.md` under `/mnt/us/OkayWrite`; mount over USB and copy them off. The reliable baseline. |
| **Export — wireless / cloud sync** | 🔎 spike (primary) | Salvage KOReader's Dropbox / WebDAV / FTP sync; spike to confirm it works on-device and survives trimming. |
| **Export — QR snippet-share** | 💡 nice-to-have | Use KOReader's QR widget to render a short note on-screen to scan with a phone. Snippet-sized only (QR + e-ink is capacity-limited), not a whole-document path. |

Deeper feature work (wireless sync, QR, any actual stripping/fork) is future and each gets
its own design pass.

## Repository layout

```
overlay/koreader/patches/2-okaywrite.lua    the reskin userpatch (the whole app, really)
build.sh                                     downloads a KOReader release + layers the overlay
dist/                                        built, installable OkayWrite packages (git-ignored)
.cache/                                      downloaded KOReader release zips (git-ignored)
```

## Fast iteration loop (recommended while developing)

If your Kindle already has KOReader installed, you do **not** need to repackage anything to
test a change. Just copy the patch into the running install's `patches/` folder:

```sh
# with the Kindle mounted over USB (adjust the mount path for your OS):
cp overlay/koreader/patches/2-okaywrite.lua /Volumes/Kindle/koreader/patches/
```

Eject, then relaunch KOReader from KUAL. Edit the patch, recopy, relaunch. That is the
entire dev cycle. To confirm the patch ran, check `koreader/crash.log` / the log for a
`[OkayWrite] reskin applied` line, or open the patch-management menu in KOReader (patches
report success/failure there).

To temporarily disable the reskin without deleting it, drop an empty file named
`.patches_disabled` into the `patches/` folder.

## Building a full installable package

Produces a standalone OkayWrite zip (KOReader + our overlay + an "OkayWrite" KUAL label):

```sh
./build.sh                # builds kindlehf + kindlepw2 into dist/
./build.sh kindlehf       # single generation
```

Requires only `curl`, `unzip`, `zip`, and `bash` (all present on macOS). Pin the KOReader
version by editing `KO_VERSION` at the top of `build.sh`.

## Installing on the Kindle

See [INSTALL.md](INSTALL.md) for step-by-step instructions.

## License

AGPL-3.0, inherited from KOReader (see [LICENSE](LICENSE)). If you distribute a build, you
must provide the corresponding source (this overlay plus the pinned KOReader release it is
built from) and preserve KOReader's notices. See the KOReader `COPYING` file.

## How it works (one paragraph)

KOReader runs Lua "userpatches" from `koreader/patches/` at defined startup phases. Our
`2-okaywrite.lua` is a `late`-phase patch (filename prefix `2-`), so it runs after
`G_reader_settings` is loaded. It sets three settings KOReader already honors: the
per-extension default provider (`txt`/`md` → `texteditor`), the home directory, and
`start_with = filemanager`. Because `FileManager:openFile` consults auxiliary providers,
tapping a file opens the editor instead of the reader. No core files are modified, so
upgrading to a newer KOReader release is just a matter of bumping `KO_VERSION` and
rebuilding.
