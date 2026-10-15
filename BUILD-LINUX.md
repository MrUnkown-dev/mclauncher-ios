# Building the IPA from Linux (no Mac required)

Short answer: **you cannot compile an iOS app on Linux directly** — Apple's iOS
SDK and toolchain ship only with Xcode, and macOS virtualization is restricted
to Apple hardware by the macOS licence. But you have three practical routes that
do **not** require owning a Mac. Pick one:

| Route | Needs a Mac? | Produces | Best for |
|---|---|---|---|
| **A. GitHub Actions** (recommended) | No | Unsigned `.ipa` artifact | Free, repeatable, zero local setup |
| **B. Cloud Mac** (MacinCloud, MacStadium, Codemagic) | No | Signed or unsigned `.ipa` | When you also want to sign in the cloud |
| **C. Docker-OSX** (macOS VM on Linux/KVM) | No | Signed or unsigned `.ipa` | Full local control; heavy, Apple HW only |

Then sign the resulting IPA. Signing **can** be done on Linux with `zsign`.

---

## Route A — GitHub Actions (the "IPA builder" you asked for)

A ready-to-use workflow is included at
[`.github/workflows/build-ipa.yml`](../.github/workflows/build-ipa.yml).

1. Push this repo to GitHub.
2. Actions → **Build iOS IPA** → **Run workflow**.
3. When it finishes, download the **MCLauncher-ipa** artifact.

The workflow:
- runs on a GitHub-hosted **macOS** runner (free for public repos),
- installs `xcodegen`, generates the project,
- archives with signing **disabled** (`CODE_SIGNING_ALLOWED=NO`) so it needs no
  certificates or secrets,
- packages `Payload/` into an **unsigned** `.ipa` and uploads it.

Because the build is unsigned, you sign it yourself — on device with
**Sideloadly**/**AltStore**, or on Linux with **zsign** (below). This is the
standard "build in CI, sign locally" workflow and it needs nothing from you but
a GitHub account.

> Want the workflow to produce a *signed* IPA directly? Add your certificate and
> provisioning profile as base64-encoded repository secrets and switch the
> archive step to use them. That requires a paid Apple Developer account, since
> you must export a `.p12`. Free Apple IDs cannot export a signing identity, so
> unsigned-build + local-sign is the correct path for free accounts.

## Route B — Cloud Mac

Any of these give you a macOS desktop or CI minutes in a browser:

- **MacinCloud** / **MacStadium** — rent a Mac, install Xcode, build normally.
- **Codemagic** / **Bitrise** — iOS-focused CI; similar to Route A but with
  first-class signing UI if you have a paid account.
- **Xcode Cloud** — Apple's own CI (paid account).

## Route C — macOS in a VM on Linux

[`sickcodes/Docker-OSX`](https://github.com/sickcodes/Docker-OSX) runs macOS in a
Docker container backed by KVM. Inside it you install Xcode and build exactly as
on a real Mac.

```bash
docker run -it \
  --device /dev/kvm \
  -p 50922:10022 \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -e "DISPLAY=${DISPLAY:-:0.0}" \
  sickcodes/docker-osx:latest
```

Caveats: needs `/dev/kvm`, 16 GB+ RAM and ~100 GB disk, it is slow, and Apple's
licence permits macOS virtualization only on Apple hardware. Use it only if
Route A or B is not an option.

---

## Signing an unsigned IPA on Linux — `zsign`

[`zsign`](https://github.com/zhlynn/zsign) is a cross-platform IPA signer that
runs on Linux. You still need a certificate + provisioning profile, which for a
**free** Apple ID you obtain by letting Sideloadly/AltStore generate them once
(then export the `.p12` and `.mobileprovision`).

```bash
# 1. Build zsign
git clone https://github.com/zhlynn/zsign
cd zsign && make -j"$(nproc)"

# 2. Sign the unsigned IPA
./zsign \
  -k  cert.p12 -p "your-p12-password" \
  -m  profile.mobileprovision \
  -o  MCLauncher-signed.ipa \
  MCLauncher-unsigned.ipa
```

Then install the signed IPA with Sideloadly, AltStore, or `ideviceinstaller`
(from `libimobiledevice`):

```bash
sudo apt install libimobiledevice-utils
ideviceinstaller -i MCLauncher-signed.ipa
```

### Jailbroken / TrollStore devices

If the target device uses **TrollStore** or is jailbroken, you can skip Apple
signing entirely: build the IPA, **fakesign** it with
[`ldid`](https://github.com/ProcursusTeam/ldid) and install via TrollStore.

```bash
ldid -S MCLauncher.app/MCLauncher
```

TrollStore installs the app permanently (no 7-day expiry) and also allows JIT,
which removes the interpreter-mode performance limit.

---

## Recommended combination

For a free Apple ID with no Mac:

1. **Route A** (GitHub Actions) → unsigned IPA.
2. **Sideloadly** on Windows or Linux (`libimobiledevice`) → signs and installs.
3. If you later get a paid account or a jailbreak, add **JIT** for a large
   speed-up (see `BUILD.md` → *Reality check 2*).
