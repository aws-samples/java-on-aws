#!/usr/bin/env python3
"""Generate stages/NN-*/main.py (stages 04 onwards) from main.template.py, and assemble runnable stages.

Template blocks:
  #+feature [note]   lines included from the stage that introduces `feature` onwards
  #+feature!later    the same, but only until the stage that introduces `later`
  #!feature          lines included only before that stage (replaced by a #+ block)
  #-                 end of block
Lines new in a stage are wrapped in "# >> note" / "# <<" markers (consecutive new lines are merged),
which tools/render.py turns into highlightLines and explanations.

Usage:
  build_stages.py                   regenerate stage main.py files
  build_stages.py assemble STAGE DIR  copy all files up to STAGE into DIR, without markers
"""

import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
STAGES = sorted(p.name for p in (HERE / "stages").iterdir() if p.is_dir())
FEATURE_STAGE = {name.split("-", 1)[1]: i for i, name in enumerate(STAGES)}
FIRST_TEMPLATED = FEATURE_STAGE["memory"]
BLOCK = re.compile(r"^#([+!])([\w-]+)(?:!([\w-]+))?(?: (.+))?$")
MARKER = re.compile(r"^\s*# (>>|<<)")


def render(stage):
    out, mode, feature, until, note, new_run = [], None, None, None, None, None
    lines = (HERE / "main.template.py").read_text().rstrip("\n").split("\n")
    for line in lines:
        m = BLOCK.match(line)
        if m:
            mode, feature, until, note = m.group(1), m.group(2), m.group(3), m.group(4)
            continue
        if line == "#-":
            mode = None
            continue
        if mode:
            introduced = FEATURE_STAGE[feature]
            if (mode == "+" and stage < introduced) or (mode == "!" and stage >= introduced):
                continue
            if until and stage >= FEATURE_STAGE[until]:
                continue
            is_new = mode == "+" and stage == introduced
        else:
            is_new = False
        if is_new and new_run is None:
            new_run = len(out)
            out.append(f"# >> {note or ''}")
        elif is_new and note and out[new_run] == "# >> ":
            out[new_run] = f"# >> {note}"
        elif not is_new and new_run is not None:
            out.append("# <<")
            new_run = None
        out.append(line)
    if new_run is not None:
        out.append("# <<")
    # move a marker that wraps only leading blank lines onto the first code line
    text = "\n".join(out) + "\n"
    return re.sub(r"(# >> [^\n]*)\n((?:\n)+)", r"\2\1\n", text)


def assemble(stage_name, target):
    target = Path(target)
    target.mkdir(parents=True, exist_ok=True)
    for name in STAGES[: STAGES.index(stage_name) + 1]:
        for f in (HERE / "stages" / name).iterdir():
            if f.is_file():
                text = f.read_text()
                if f.suffix == ".py" or f.name == "Dockerfile":
                    text = "".join(l for l in text.splitlines(True) if not MARKER.match(l))
                (target / f.name).write_text(text)
    for f in ("pyproject.toml", "uv.lock", ".python-version", ".gitignore"):
        shutil.copy(HERE / f, target / f)


def main():
    if sys.argv[1:2] == ["assemble"]:
        assemble(sys.argv[2], sys.argv[3])
        return
    for i, name in enumerate(STAGES):
        if i >= FIRST_TEMPLATED:
            (HERE / "stages" / name / "main.py").write_text(render(i))
            print(f"wrote stages/{name}/main.py")


if __name__ == "__main__":
    main()
