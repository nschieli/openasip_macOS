# Signing and notarizing the macOS prefix

Measured 2026-09-18 on macOS 26 (arm64), against the published prefix.

⭐ **THE RESULT: a QUARANTINED copy of a signed + notarized prefix runs with no
user workaround at all.** Same shape of `com.apple.quarantine` a browser sets;
`ttasim --version` rc=0, `generateprocessor` reaches its own argument parser. No
`xattr -dr`, no instructions, no System Settings trip.

⇒ Ad-hoc / linker signing — what the build produces by default — cannot do this.
See `openasip/INSTALL.macOS.md` for the failure it produces.

---

## The recipe

**Order matters: nested code first, then executables.** 162 Mach-O files: 46
dylib/`.so`, then 116 executables. ~52 s, 0 failures.

```
codesign --force --timestamp --options runtime \
         --entitlements <plist> \
         --sign "Developer ID Application: …" <file>
```

Each signed file then reports `flags=0x10000(runtime)`, an Authority chain to
Apple Root CA, a Team Identifier, and a timestamp.

Notarization:

```
ditto -c -k --keepParent local openasip.zip     # 287 MB
xcrun notarytool submit openasip.zip --keychain-profile <profile> --wait
```

Accepted, `issues: 0`, **`ticketContents: 162`** — every Mach-O ticketed,
including `share/openasip/**.so`. ⭐ That is the same inventory the
self-containment scan walks; narrowing either one would miss the runtime
plugins.

---

## ⛔ Entitlements are load-bearing, and they fail at RUN time

Signing **succeeds** without them. The binaries then die when used.

| entitlement | why this toolchain needs it |
|---|---|
| `com.apple.security.cs.allow-jit` | LLVM JITs |
| `com.apple.security.cs.allow-unsigned-executable-memory` | same |
| `com.apple.security.cs.disable-library-validation` | users `dlopen` their **own** `.opb`/`.so`, built against the prefix and **not signed by us** — this is the OSAL custom-operation path, i.e. the tour's whole subject |

⚠ The third is the one that is easy to miss and impossible to notice at sign
time: without it, a user's own custom operation cannot be loaded, and the
failure appears in the middle of their build.

---

## ⛔⛔ Two traps, both of which made a first measurement say "still blocked"

**1. The ticket is not usable the instant `notarytool` prints Accepted.**
A quarantined run ~1 minute after acceptance was SIGKILLed (rc=137), with
*"library load disallowed by system policy"*. The **same zip**, re-extracted
minutes later, ran. ⇒ **A CI step that verifies immediately after `--wait` will
produce a FALSE RED.** Staple and `stapler validate` rather than racing the
online lookup, or retry with backoff.

**2. A denial is cached per file instance and is permanent for that copy.**
A tree killed once stays killed. Re-writing its quarantine xattr does **not**
clear it, while `ditto` of the *same bytes* to a new path runs fine.
⇒ The fix after a block is **re-extract**, never `xattr -dr`.
⚠ It also means a stale test tree will keep reporting failure for a build that
is actually fine — check a fresh extraction before believing a red.

---

## Not done

- **`xcrun stapler staple`** — works on pkg/dmg/app only, and removes the
  online-lookup dependency (and therefore trap 1) entirely.
- **A signed `.pkg`** — the Developer ID *Installer* certificate is still
  unused. ⭐ A signed + notarized `.pkg` avoids quarantine **structurally**,
  because installer-placed files are not quarantined.
- **CI wiring** — cert `.p12` and notarization credential as secrets on a macOS
  runner: keychain import → sign → notarize → staple → upload.

## ⚠ An open decision, not a technical one

Whether the **public open-source baseline** is signed with a personal Developer
ID is a choice about identity and release dependencies, not a build detail: it
ties this repository's releases to one individual's certificates. The facts
above hold wherever signing happens; where it *should* happen is NS's call.
