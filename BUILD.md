# Building & Signing — MC Launcher (iOS)

This guide takes you from the source in this folder to an installed app on an
iPhone/iPad running **iOS 18.0 or newer** (18.x, 26.x, 27.x), using **AltStore
or Sideloadly with a free Apple ID**.

Read the two **reality checks** first — they explain why the process has the
steps it has.

---

## Reality check 1 — the Java runtime is not in this repo

A launcher is a *front end*. To actually run Minecraft: Java Edition on iOS you
need four native components that are **large prebuilt binaries** and cannot be
generated from source in a normal build:

| Component | What it does | Where it comes from |
|---|---|---|
| **OpenJDK for iOS** | Runs the game's Java bytecode | A JRE ported to arm64 iOS (PojavLauncher's `JavaLauncher` lineage) |
| **GL4ES** | Translates OpenGL 2.1 → OpenGL ES | `ptitSeb/gl4es` |
| **ANGLE** | Translates OpenGL ES → Metal (needed for 1.17+) | `google/angle` |
| **LWJGL-for-iOS** | Java bindings to the graphics/audio/input stack | Custom LWJGL 3 builds for iOS |

This project is built so it **compiles, runs, and is fully usable as a UI**
*without* those components. It detects their absence and shows a clear banner.
Once you add them (see [Adding the JRE](#adding-the-jre)), launching is enabled.

> The author of this repo cannot redistribute those binaries. You obtain or
> build them yourself from their upstream open-source projects, respecting each
> project's license (PojavLauncher is GPL-3.0; GL4ES is MIT; ANGLE is BSD).

## Reality check 2 — JIT and your signing method

The JVM is **dramatically** faster with JIT (just-in-time compilation). On iOS,
JIT requires one of:

- a **jailbroken** device / **TrollStore**, or
- the `com.apple.security.cs.allow-jit` entitlement, which needs a **paid**
  Apple Developer account, or
- **AltStore's "Enable JIT"** feature (works with a free Apple ID when AltStore
  is running and the device is reachable — it attaches a debugger to grant JIT).

If you are on a **free Apple ID without AltStore's JIT**, the launcher runs the
JVM in **interpreter-only mode** (`-Xint`, wired to the *Prefer JIT* toggle in
Settings). It works, but expect low frame rates — this is a hardware/signing
limitation, not a bug in the launcher.

---

## Prerequisites

1. **A Mac** with **Xcode 16 or newer** (iOS 18 SDK+).
2. **XcodeGen** — generates the `.xcodeproj` from `project.yml`:
   ```bash
   brew install xcodegen
   ```
3. **An Apple ID** (free is fine) added in Xcode → Settings → Accounts.
4. A **USB cable** and your iPhone/iPad (Developer Mode enabled:
   Settings → Privacy & Security → Developer Mode → On → reboot).

---

## Step 1 — Generate the Xcode project

```bash
cd mclauncher
xcodegen generate
open MCLauncher.xcodeproj
```

`project.yml` is the single source of truth for the project. If you add files,
re-run `xcodegen generate`; do not hand-edit the `.xcodeproj`.

## Step 2 — Set your signing team

In Xcode:

1. Select the **MCLauncher** target → **Signing & Capabilities**.
2. Tick **Automatically manage signing**.
3. Choose **your Personal Team**.
4. Change the **Bundle Identifier** to something unique, e.g.
   `com.yourname.mclauncher` (free IDs cannot reuse someone else's).

Keep `MCLauncher.entitlements` as shipped (only `get-task-allow`). Free
profiles reject `allow-jit` and friends — adding them will make the install
fail.

## Step 3 — Build & run (simulator or device)

Simulator (UI only — no JRE will load):
```bash
xcodebuild -project MCLauncher.xcodeproj -scheme MCLauncher \
  -sdk iphonesimulator -configuration Debug build
```

Device (this is what you sideload):
```bash
xcodebuild -project MCLauncher.xcodeproj -scheme MCLauncher \
  -sdk iphoneos -configuration Release \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates build
```

## Step 4 — Package an IPA

An IPA is just a zip with a `Payload/` folder containing the `.app`:

```bash
./scripts/build-ipa.sh        # see scripts/build-ipa.sh
```

Or by hand:
```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "MCLauncher.app" -path "*Release-iphoneos*" | head -1)
rm -rf /tmp/ipa && mkdir -p /tmp/ipa/Payload
cp -R "$APP" /tmp/ipa/Payload/
cd /tmp/ipa && zip -qr MCLauncher.ipa Payload
```

## Step 5 — Install

**Sideloadly** (simplest with a free ID):
1. Open Sideloadly, drag `MCLauncher.ipa` in, enter your Apple ID.
2. Install. Trust the profile: Settings → General → VPN & Device Management.

**AltStore**:
1. Add the `.ipa` to AltStore (via AltStore's `My Apps` → `+`).
2. AltStore re-signs it every 7 days automatically while running.

**Free-ID limits:** 7-day expiry, max 3 sideloaded apps, max 10 App IDs/week.
AltStore refreshes in the background to work around expiry.

---

## Adding the JRE

Once you have the runtime components:

1. Put them under `native-runtime/` with this layout:
   ```
   native-runtime/
     Frameworks/
       jre/                     ← the OpenJDK-for-iOS tree (bin, lib, …)
       libjvm_launcher.dylib    ← boots the JVM (exports launchJVM)
       libgl4es.dylib
       libangle.dylib
       liblwjgl.dylib
   ```
2. In `project.yml`, **uncomment** the `dependencies:` block under the
   `MCLauncher` target so the dylibs and the `jre` folder are copied into the
   app bundle at `MCLauncher.app/Frameworks/`.
3. Re-run `xcodegen generate`.

### If the entry symbol is named differently

`MCLauncher/Native/jvm_bridge.m` resolves the JVM entry point by trying, in
order:

1. a statically linked `launchJVM` (weak import), then
2. `dlopen` of `libjvm_launcher.dylib` / `libjvm.dylib`, then `dlsym` of
   `launchJVM`, `Java_org_lwjgl_Launcher_launchJVM`, `JVM_launch`.

If your build uses another name, add it to `kJVMSymbolCandidates[]` in that
file. Nothing else needs to change — the Swift side never sees the symbol.

### Signing the bundled dylibs

Free-Apple-ID signing requires **every** embedded Mach-O binary to be signed.
After embedding, add a run-script build phase **before** Xcode's "Embed
Frameworks":

```bash
APP="${CODESIGNING_FOLDER_PATH}"
find "$APP/Frameworks" -type f \( -name "*.dylib" -o -perm +111 \) -print0 |
  while IFS= read -r -d '' f; do
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
      --preserve-metadata=identifier,entitlements "$f" || true
  done
```

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "Java runtime not bundled" banner | Expected until you complete *Adding the JRE*. |
| `dyld: Library not loaded: @rpath/...` | The dylib wasn't embedded/signed. Redo the run-script above. |
| App installs then "Untrusted Developer" | Trust the profile in Settings → VPN & Device Management. |
| Install fails with an entitlement error | Remove `allow-jit` / `get-task-allow` variants from the entitlements; free IDs reject them. |
| Very low FPS | Interpreter mode. Enable AltStore JIT, or use a paid cert with `allow-jit`. |
| Game starts then black screen | Renderer mismatch — set the renderer manually in Settings (GL4ES for ≤1.16, ANGLE for ≥1.17). |
| `codesign` errors on `jre/` | Sign each binary individually as shown above; the JRE tree is not pre-signed. |
| 7-day expiry | Normal for free IDs. Use AltStore's automatic refresh, or a paid cert. |

---

## Sanity check before you build

Every Swift file in this project has been checked with a real Swift compiler
(`swiftc -parse`, Swift 5.10) and parses cleanly. You can re-run the same check
locally without a full build:

```bash
swiftc -parse $(find MCLauncher -name '*.swift')
```

`-parse` checks syntax only — it does not need the iOS SDK, so it also works on
Linux. It will not catch type errors or missing frameworks; only Xcode can do
that.

---

## No Mac? Build in CI instead

If you are on Linux or Windows, you cannot run Xcode locally. Use
[`BUILD-LINUX.md`](BUILD-LINUX.md): a GitHub Actions workflow builds an
**unsigned IPA** on a free macOS runner, and `zsign` signs it on Linux. The
workflow lives at `.github/workflows/build-ipa.yml`.

---

## What is intentionally a stub

Two things are scaffolded rather than fully implemented, and are labelled in
code so you can finish them:

1. **Native extraction** (`VersionInstaller.extractNatives`) — expects the
   natives to come from the packaged runtime rather than being unzipped from
   library jars.
2. **Forge's post-install processors** — `ModLoaderService` merges the loader
   profile; running Forge's `installer` processors needs the JVM and happens at
   first launch.

Everything else — accounts, Microsoft OAuth, version manifest, downloads with
SHA-1 verification, argument assembly, classpath, console, settings, controller
bridge — is complete and exercised by the UI.
