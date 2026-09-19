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
    if bad:
        print(f'\n{bad} broken run: block(s) of {checked}')
        return 1
    print(f'{checked} run: blocks parse')
    return 0


if __name__ == '__main__':
    sys.exit(main())
