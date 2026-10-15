# MC Launcher — lightweight Minecraft: Java Edition launcher for iOS

A small, native SwiftUI launcher for **Minecraft: Java Edition** on iOS, in the
spirit of PojavLauncher but built as a lean, readable codebase you can extend.

- **Target:** iOS **18.0+** (works on 18.x, 26.x and 27.x), iPhone + iPad, arm64.
- **Signing:** designed for **AltStore / Sideloadly** with a free Apple ID.
- **Accounts:** offline ("cracked") accounts **and** real **Microsoft / Xbox
  Live** sign-in.
- **Loaders:** Vanilla, **Fabric**, **Forge**, **OptiFine** hooks.
- **Modrinth built in:** search and install **mods, resource packs, shaders,
  datapacks and modpacks**. A modpack creates its own instance, with the game
  and loader versions read from the pack's manifest.
- **Built-in file manager:** add mods, resource packs, shaders and datapacks
  from the system Files app without leaving the launcher.
- **Per-instance isolation:** every instance has its own `mods/`,
  `resourcepacks/`, `shaderpacks/`, `datapacks/`, `saves/` and `config/`.
- **Extras:** live console, controller bridge, performance & renderer settings.

> ⚠️ **Read [`BUILD.md`](BUILD.md) first.** Two facts matter: (1) the Java
> runtime + graphics stack are large prebuilt native binaries you must add
> yourself, and (2) JIT needs a paid cert, AltStore, or a jailbreak.
>
> Building without a Mac? See [`BUILD-LINUX.md`](BUILD-LINUX.md) — a GitHub
> Actions workflow that builds the IPA in CI, plus a Linux signing path (`zsign`).

---

## What's in the box

```
mclauncher/
├── project.yml                     # XcodeGen spec — the project's source of truth
├── BUILD.md                        # build, sign, install, add-the-JRE guide
├── BUILD-LINUX.md                  # build + sign without a Mac (CI, zsign)
├── README.md
├── .github/workflows/build-ipa.yml # unsigned-IPA builder (GitHub Actions)
├── scripts/
│   └── build-ipa.sh                # archive → .app → .ipa
├── native-runtime/                 # drop the JRE / GL4ES / ANGLE here
└── MCLauncher/
    ├── MCLauncherApp.swift         # @main entry
    ├── Info.plist
    ├── MCLauncher.entitlements
    ├── Models/
    │   ├── Account.swift           # offline + Microsoft account model
    │   ├── Instance.swift          # version + loader + game dir
    │   ├── LauncherSettings.swift  # settings + renderer auto-selection
    │   ├── MinecraftVersion.swift  # Mojang manifest / version JSON schema
    │   └── Modrinth.swift          # Modrinth API + .mrpack index models
    ├── Services/
    │   ├── AccountStore.swift      # persistence + Keychain for tokens
    │   ├── Crypto.swift            # offline UUID (UUIDv3) + SHA-1 verify
    │   ├── GamepadService.swift    # MFi/Bluetooth → controller.json
    │   ├── InstanceFileManager.swift # per-instance folders + file operations
    │   ├── JVMBridge.swift         # Swift side of the native JVM bridge
    │   ├── Keychain.swift
    │   ├── LauncherModel.swift     # central @MainActor app state
    │   ├── LauncherPaths.swift     # on-device layout
    │   ├── LaunchService.swift     # argv assembly + launch
    │   ├── MicrosoftAuth.swift     # device-code OAuth → XBL → XSTS → MSA
    │   ├── ModLoaderService.swift  # Fabric/Forge profile merging
    │   ├── ModrinthService.swift   # Modrinth API client + installers
    │   ├── VersionInstaller.swift  # downloads + SHA-1 verification
    │   ├── VersionManifestService.swift
    │   └── ZipArchive.swift        # dependency-free ZIP reader (.mrpack)
    ├── Views/                      # Launch, Instances, InstanceDetail, Files,
    │                               # Directory, Modrinth, ModrinthProject,
    │                               # Versions, Accounts, Settings, Console
    └── Native/
        ├── jvm_bridge.h
        ├── jvm_bridge.m            # weak-import + dlopen JVM entry resolution
        └── MCLauncher-Bridging-Header.h
```

## Architecture in one paragraph

`LauncherModel` is the single `@MainActor` state owner. `AccountStore` and
`SettingsStore` are injected into the environment. `VersionManifestService`
fetches Mojang's manifest; `VersionInstaller` downloads the client jar,
libraries and assets, verifying every SHA-1; `ModLoaderService` layers Fabric or
Forge onto the vanilla profile; `LaunchService` assembles the exact JVM
command line (`java <jvm args> -cp <classpath> <mainClass> <game args>`);
`JVMBridge` hands that argv to the native runtime through a weak-imported
`launchJVM` symbol, falling back to `dlopen`. The JVM's stdout/stderr is
redirected to `.minecraft/latest.log`, which `LauncherModel` tails into the live
console.

## Offline vs. online accounts

- **Offline** — the UUID is derived exactly as Java does:
  `UUID.nameUUIDFromBytes("OfflinePlayer:<name>")` (UUIDv3 / MD5), so the
  player identity matches what a server computes. Works in singleplayer and on
  servers with `online-mode=false`.
- **Microsoft** — OAuth 2.0 **device-code** flow (no redirect URI, so it works
  under free-ID signing) → Xbox Live → XSTS → Minecraft services → profile.
  Tokens are stored in the **Keychain**; the JSON store keeps only non-secrets.

## Where your data lives ("On My iPhone")

Everything the launcher writes lives in **`Documents/minecraft`**, which the app
publishes to the Files app. On the device it appears as:

> **On My iPhone → MC Launcher → minecraft**

That folder holds `versions/`, `libraries/`, `assets/`, `instances/`, `mods/`,
worlds and `latest.log`. It is a *visible* folder (not the usual hidden
`.minecraft`) so you can drag in mods, pull out worlds, and see logs without a
jailbreak. The location is included in iCloud/iTunes backups, so your data
survives reinstalls. Older builds that used `.minecraft` are migrated
automatically on first launch.

Settings → **Files → Open in Files app** jumps straight there.

## Adding mods, resource packs & datapacks in-app

The **Files** tab (and each instance's detail screen) is a full file manager:

1. Pick an instance, then open a category — **Mods**, **Resource Packs**,
   **Shaders**, **Datapacks**, **Worlds**, **Config**, **Logs**,
   **Screenshots**.
2. Tap **⋯ → Import from Files…** and choose a `.jar` / `.zip` from iCloud, On
   My iPhone, or any provider. Multi-select is supported.
3. Swipe a row to **rename**, **delete**, or **move** it to another category;
   tap the share icon to export it back out.

Files are written straight into the instance's game directory, so the game
picks them up on next launch — no jailbreak, no iTunes file sharing dance. The
importer warns you if a file looks out of place (e.g. a `.zip` dropped into
Mods) but never blocks it.

> **Datapacks:** vanilla loads datapacks from a *world's* own folder. Use
> **Datapacks** as a staging area, then open **Worlds → <world> → datapacks** to
> install one for a specific world.

## Modrinth integration

**Instances → ＋ → Install modpack from Modrinth**, or open an instance and use
**Browse Modrinth** (also on the Files tab).

- **Mods, resource packs, shaders, datapacks** — search results are filtered to
  the target instance's Minecraft version and loader, so you only see things
  that will actually run. Downloads go straight into that instance's own
  folder. Every file is verified against its SHA-1.
- **Modpacks** — the launcher downloads the `.mrpack`, reads its
  `modrinth.index.json`, creates a **new instance** with the pack's Minecraft and
  loader versions, downloads every indexed file into it, then overlays
  `overrides/` and `client-overrides/`. Files marked `client: unsupported` are
  skipped, and the base game files are fetched right after.

No third-party packages: `.mrpack` archives are read by `ZipArchive.swift`, a
small ZIP reader built on Apple's `Compression` framework. It rejects absolute
paths and `..` traversal, so a malicious pack cannot write outside its own
instance folder.

## Per-instance content isolation

Each instance owns a separate game directory —
`minecraft/instances/<slug>` — containing its own `mods/`, `resourcepacks/`,
`shaderpacks/`, `datapacks/`, `saves/`, `config/`, `logs/` and
`screenshots/`. The launch arguments point `--gameDir` at that directory, so
installing a mod in one instance never affects another. Only version-level
artifacts (`versions/`, `libraries/`, `assets/`) are shared, which is what you
want — they are identical per Minecraft version.

## Publish to GitHub

One command pushes the whole project as a single clean commit:

```bash
./scripts/push-to-github.sh                    # uses the default repo URL
./scripts/push-to-github.sh git@github.com:you/your-fork.git
```

It force-pushes, which is intentional: it replaces any partial history with one
commit. After that, **Actions → Build iOS IPA → Run workflow** builds an
unsigned `.ipa` on a free macOS runner and attaches it to a release.

## License / attribution

This launcher is original code. It is designed to interoperate with
open-source components (PojavLauncher — GPL-3.0; GL4ES — MIT; ANGLE — BSD;
LWJGL — BSD) which you obtain separately. Minecraft is a trademark of Mojang
Synergies AB; this project is not affiliated with or endorsed by Mojang or
Microsoft. Use your own account.
