OpenASIP toolchain for Linux x86_64 and macOS on Apple Silicon (arm64),
each built and self-tested by CI from a clean checkout.

Each archive expands to a `local/` prefix containing OpenASIP and the
patched LLVM it requires. `local/BUILD-INFO` records the commit, the
run and the runner.

Licensed LGPL v2.1. The corresponding source is this repository at the
commit named in BUILD-INFO.

## Linux x86_64 (Ubuntu 24.04 LTS, stock)

Verify, extract, and put it on PATH by sourcing the env.sh inside it,
which resolves paths from its own location:

    sha256sum -c openasip-linux-x86_64.tar.gz.sha256
    tar -xzf openasip-linux-x86_64.tar.gz
    . local/env.sh

## macOS arm64

Verify:

    shasum -a 256 -c openasip-macos-arm64.tar.gz.sha256

### Extract from a terminal, not by double-clicking

These binaries are ad-hoc signed (no Developer ID), so Gatekeeper
will not run them once they carry the quarantine flag a browser
download sets.

    tar -xzf openasip-macos-arm64.tar.gz

Archive Utility -- what a double-click in Finder uses -- copies the
quarantine flag onto EVERY extracted file. `tar` does not. Measured
2026-09-16 on macOS 26: expanding this archive with Archive Utility
after a browser download quarantined 5477 of 5478 files, and macOS
then refused to run the tools, offering only "Move to Trash".

For a command-line tool that dialog has no "Open Anyway", and the
override in System Settings is per-binary, so extracting correctly is
much easier than fixing it afterwards.

If a tree is already quarantined but you have NOT yet tried to run it:

    xattr -dr com.apple.quarantine local

### If macOS has already refused to run it, RE-EXTRACT

Removing the quarantine flag at that point does NOT help. macOS caches
the refusal against that copy of the file and the cache survives
clearing the attribute -- measured 2026-09-18: a tree killed once was
still killed afterwards, while the same bytes extracted to a new path
ran normally. Delete the extracted tree and unpack the archive again
with `tar`.

Downloads made with `curl`, `gh` or `git` are not quarantined at all
and need none of this.

---
Release @TAG@ of the nschieli fork. Tracks upstream OpenASIP 2.2; local/BUILD-INFO names the exact commit.
