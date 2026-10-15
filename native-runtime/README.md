# native-runtime/ — drop the prebuilt components here

This folder is empty on purpose. The Java runtime and graphics translation
layer are large prebuilt native binaries that must be obtained or built from
their upstream open-source projects. `BUILD.md` → *Adding the JRE* explains how
to wire them into the Xcode project.

## Expected layout

```
native-runtime/
└── Frameworks/
    ├── jre/                     # OpenJDK-for-iOS tree: bin/, lib/, lib/server/libjvm.dylib …
    ├── libjvm_launcher.dylib    # boots the JVM; exports launchJVM (or see jvm_bridge.m)
    ├── libgl4es.dylib           # OpenGL 2.1 → OpenGL ES
    ├── libangle.dylib           # OpenGL ES → Metal (Minecraft 1.17+)
    └── liblwjgl.dylib           # LWJGL 3 iOS build
```

## Where each component comes from

| Component | Upstream project (verify current state yourself) |
|---|---|
| OpenJDK-for-iOS / `launchJVM` | The **PojavLauncher** family of projects, which maintains the OpenJDK iOS port and the `JavaLauncher` bridge. |
| GL4ES | `ptitSeb/gl4es` — build for iOS/arm64. |
| ANGLE | `google/angle` — Metal backend (`angle_enable_metal`). |
| LWJGL 3 | Upstream LWJGL has no official iOS target; use the iOS-patched LWJGL 3 build maintained alongside the PojavLauncher project. |
| MoltenVK (for Zink) | `KhronosGroup/MoltenVK`. |

## Building vs. downloading

- **Fastest path:** use the prebuilt iOS artifacts published by the
  PojavLauncher projects, matching the Minecraft version you intend to run.
- **From source:** you need the iOS SDK and, for the JRE, a full OpenJDK cross
  build. This is a multi-hour build and is out of scope for this repo.

## Signing reminder

Every embedded Mach-O binary (each `.dylib`, every executable under `jre/bin`)
must be signed with your identity for the app to install under a free Apple ID.
See the *Signing the bundled dylibs* run-script in `BUILD.md`.

## Licenses

Each component keeps its own license. If you redistribute an app containing
them, comply with those licenses — notably **PojavLauncher is GPL-3.0**, which
has implications for a combined work. This repository ships **none** of them.
