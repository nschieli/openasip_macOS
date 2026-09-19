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

---

## ⭐⭐ A signed + notarized + STAPLED `.pkg` removes the problem structurally

Measured 2026-09-18, same Mac.

```
pkgbuild    --root <signed prefix> --identifier … --ownership recommended
productbuild --distribution … --sign "Developer ID Installer: …" --timestamp
xcrun notarytool submit --wait        → Accepted
xcrun stapler staple                  → "The staple and validate action worked!"
spctl -a -t install -vv               → accepted, source=Notarized Developer ID
pkgutil --check-signature             → notarization trusted, trusted timestamp
```

**Two results that decide the delivery shape:**

⭐ **The installed files carry NO quarantine — 0 of 5477**, only
`com.apple.provenance`. So the two traps above **cannot reach a user at all**
through this path. They still apply to anything shipped as a zip or tarball, and
to CI verification steps.

⭐ **A QUARANTINED `.pkg` installs with no admin password**:
`installer -pkg … -target CurrentUserHomeDirectory` → success, rc=0. That comes
from `<domains enable_currentUserHome="true" enable_localSystem="false"/>` — the
same non-admin reasoning that makes `~/Applications` worth searching for an
editor.

⚠ **Stapling only works on pkg/dmg/app, never on loose binaries.** So a stapled
`.pkg` is also the only shape that needs **no network at install time** — a
tarball of signed binaries always depends on the online notarization lookup, and
therefore on trap 1.

⛔ **THE `.pkg` PROVED ABOVE IS NOT SHIPPABLE.** It was built from a
signed-but-**unvendored** prefix, so its binaries still require
`/opt/homebrew`. It demonstrates the Gatekeeper chain and nothing whatsoever
about self-containment.

⛔ **ORDER, because getting it wrong surfaces late and misleadingly:**

    vendor the dylibs → codesign (162) → notarize → staple

`install_name_tool` invalidates signatures, so vendoring after signing
invalidates all 162 — and that shows up as a **notarization rejection**, not as
anything that fails locally.

---

## Not done

- **Vendoring the four Homebrew dylibs** — the remaining blocker for a
  shippable macOS artifact. Everything above is proven; none of it ships until
  this is done.
- **CI wiring** — cert `.p12` and notarization credential as secrets on a macOS
  runner: keychain import → vendor → sign → notarize → staple → upload.

## ⚠ An open decision, not a technical one

Whether the **public open-source baseline** is signed with a personal Developer
ID is a choice about identity and release dependencies, not a build detail: it
ties this repository's releases to one individual's certificates. The facts
above hold wherever signing happens; where it *should* happen is NS's call.
