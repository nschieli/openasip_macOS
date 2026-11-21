#!/usr/bin/env python3
"""
Syntax-check every `run:` block in the workflows.

⛔ WHY THIS EXISTS. A `cat > NOTES.md <<'EOF'` in ci-macos.yml lost its closing
   EOF (adc9cb6b). `cat` then swallowed the rest of the script — `gh release
   create` became four lines of text inside NOTES.md — and bash warned
   "here-document delimited by end-of-file" and EXITED 0. Tag v2.2-macos.4
   published no macOS asset and the step reported SUCCESS with zero output.

⚠ AN UNTERMINATED HEREDOC IS A WARNING, NOT AN ERROR. `bash -n` returns 0 for
  it, so checking the exit code alone reproduces the original blindness. The
  warning text must be matched explicitly — that is the whole point of this file
  and the reason it is not a one-line `bash -n` in a step.

⭐ Verified against the broken commit before being trusted: it reports exactly
   that step and no other.
"""
import subprocess
import sys

import yaml

WORKFLOWS = ['.github/workflows/ci.yml', '.github/workflows/ci-macos.yml']


def main() -> int:
    bad = 0
    checked = 0
    for path in WORKFLOWS:
        try:
            doc = yaml.safe_load(open(path))
        except FileNotFoundError:
            print(f'  ?  {path}: not found')
            bad += 1
            continue
        for job, jobdef in (doc.get('jobs') or {}).items():
            for i, step in enumerate(jobdef.get('steps') or []):
                script = step.get('run')
                if not script:
                    continue
                checked += 1
                name = step.get('name', f'step {i}')
                r = subprocess.run(['bash', '-n'], input=script,
                                   text=True, capture_output=True)
                # ⛔ BOTH CONDITIONS. See the module docstring: the heredoc case
                #    exits 0 and only shows up in stderr.
                if r.returncode != 0 or 'delimited by end-of-file' in r.stderr:
                    bad += 1
                    first = (r.stderr.strip().splitlines() or [f'rc={r.returncode}'])[0]
                    print(f'  ✗  {path} [{job}] {name}')
                    print(f'     {first}')
    bad += check_release_notes()
    if bad:
        print(f'\n{bad} problem(s); {checked} run: blocks checked')
        return 1
    print(f'{checked} run: blocks parse')
    return 0


NOTES = '.github/release-notes.md'
ASSETS = ['openasip-linux-x86_64.tar.gz', 'openasip-linux-x86_64.tar.gz.sha256',
          'openasip-macos-arm64.tar.gz', 'openasip-macos-arm64.tar.gz.sha256']


def check_release_notes() -> int:
    """Both workflows publish to the same release, and only the first to arrive
    creates it. Each must therefore write the SAME notes file, and `gh release
    edit` after its upload, so the release reads the same whichever job finishes
    first. With per-platform notes the release showed only one platform's text
    (Linux at v0.3.0, macOS at v0.3.1). Returns the number of problems."""
    bad = 0
    try:
        notes = open(NOTES).read()
    except FileNotFoundError:
        print(f'  ✗  {NOTES}: not found')
        return 1
    for a in ASSETS:
        if a not in notes:
            print(f'  ✗  {NOTES}: does not name {a}')
            bad += 1
    if notes.count('@TAG@') != 1:
        print(f'  ✗  {NOTES}: needs exactly one @TAG@ (the release line)')
        bad += 1
    titles = set()
    for path in WORKFLOWS:
        steps = [s for j in (yaml.safe_load(open(path)).get('jobs') or {}).values()
                 for s in (j.get('steps') or []) if s.get('name') == 'Publish release']
        if len(steps) != 1:
            print(f'  ✗  {path}: {len(steps)} "Publish release" steps, expected 1')
            bad += 1
            continue
        run = steps[0].get('run', '')
        for need in (NOTES, 'gh release edit', '--notes-file NOTES.md'):
            if need not in run:
                print(f'  ✗  {path} Publish release: missing {need!r}')
                bad += 1
        titles |= {ln.strip() for ln in run.splitlines() if ln.strip().startswith('TITLE=')}
    if len(titles) != 1:
        print(f'  ✗  the two Publish release steps set different titles: {sorted(titles)}')
        bad += 1
    if not bad:
        print(f'release notes: both workflows publish {NOTES} and edit after upload')
    return bad


if __name__ == '__main__':
    sys.exit(main())
