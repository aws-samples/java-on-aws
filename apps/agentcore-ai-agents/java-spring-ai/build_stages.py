#!/usr/bin/env python3
"""Generate the Java stage files from templates/, and assemble runnable stages.

Stages: 01-create … 09-deploy, 09-observability (the second half of the deploy module: ADOT and the GenAI
span attributes), 10-agent-as-tool … 15-optimize. templates/ holds the files that change in many modules
(pom.xml, application.properties, ChatService.java); stages/NN-*/ holds the generated versions of
those files (only where the file changes) and the files a module adds (ContextAdvisor.java, Dockerfile, …).

Template blocks (one or more header lines combine with AND):
  @@+feature [note]   lines included from the stage that introduces `feature` onwards
  @@!feature          lines included only before that stage
  @@-                 end of block
Lines new in a stage are wrapped in highlight markers ("// >> note" / "// <<" in Java, "# >>" in
properties, "<!-- >> note -->" in XML), which tools/render.py turns into highlightLines and notes.

Usage:
  build_stages.py                    regenerate the template files in stages/
  build_stages.py assemble STAGE DIR  copy the files up to STAGE into the Maven project in DIR, without markers
"""

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
STAGES = ["01-create", "02-persona", "03-memory", "04-knowledge", "05-tools", "06-browser",
          "07-code-interpreter", "08-mcp-client", "09-deploy", "09-observability", "10-agent-as-tool",
          "11-guardrails", "12-identity", "13-document-processing", "14-policies", "15-optimize"]
FEATURE_STAGE = {name.split("-", 1)[1]: i for i, name in enumerate(STAGES)}
EXTRA = {"06-browser": [HERE / "ArtifactLinks.java"]}
HEADER = re.compile(r"^@@([+!])([\w-]+)(?: (.+))?$")
MARKER = re.compile(r"^\s*(?://|#|<!--) (?:>>|<<)")
COMMENT = {".java": ("// >> {}", "// <<"), ".properties": ("# >> {}", "# <<"), ".xml": ("<!-- >> {} -->", "<!-- << -->")}
TARGET = {".java": "src/main/java/com/example/agent", ".properties": "src/main/resources", ".xml": ".", "": "."}


def render(template, stage):
    """Template text for one stage; new lines wrapped in highlight markers."""
    start_fmt, end_fmt = COMMENT[template.suffix]
    out, conds, in_header, new_run = [], [], False, None
    for line in template.read_text().rstrip("\n").split("\n"):
        m = HEADER.match(line)
        if m:
            conds = (conds if in_header else []) + [(m.group(1), m.group(2), m.group(3))]
            in_header = True
            continue
        in_header = False
        if line == "@@-":
            conds = []
            continue
        include, is_new, note = True, False, None
        for mode, feature, n in conds:
            introduced = FEATURE_STAGE[feature]
            if (mode == "+" and stage < introduced) or (mode == "!" and stage >= introduced):
                include = False
            if mode == "+" and stage == introduced:
                is_new, note = True, n
        if not include:
            continue
        if is_new and new_run is None:
            new_run = len(out)
            out.append(["start", note or ""])
        elif is_new and note and out[new_run][1] == "":
            out[new_run][1] = note
        elif not is_new and new_run is not None:
            out.append(["end"])
            new_run = None
        out.append(line)
    if new_run is not None:
        out.append(["end"])
    text, indent = [], ""
    for i, item in enumerate(out):
        if isinstance(item, str):
            text.append(item)
        elif item[0] == "start":
            following = [l for l in out[i + 1:] if isinstance(l, str)]
            code = next((l for l in following if l.strip()), "")
            indent = code[: len(code) - len(code.lstrip())]
            blanks = 0
            while blanks < len(following) and not following[blanks].strip():
                blanks += 1
            marker = indent + (start_fmt.format(item[1]) if item[1] else start_fmt.format("").replace("  ", " ").rstrip())
            text.append((blanks, marker))
        else:
            text.append(indent + end_fmt)
    # a start marker before blank lines moves onto the first code line
    result = []
    pending = []
    for item in text:
        if isinstance(item, tuple):
            pending.append(item)
            continue
        if pending and item.strip():
            result += [m for _, m in pending]
            pending = []
        result.append(item)
    result += [m for _, m in pending]
    return "\n".join(result) + "\n"


def strip(text):
    return "".join(l for l in text.splitlines(True) if not MARKER.match(l))


def generate():
    for template in sorted((HERE / "templates").iterdir()):
        previous = None
        for i, name in enumerate(STAGES):
            target = HERE / "stages" / name / template.name
            text = render(template, i)
            if previous is None or strip(text) != previous:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text)
                print(f"wrote stages/{name}/{template.name}")
            elif target.exists():
                target.unlink()
            previous = strip(text)


def assemble(stage_name, project):
    project = Path(project)
    for name in STAGES[: STAGES.index(stage_name) + 1]:
        files = [f for f in (HERE / "stages" / name).iterdir() if f.is_file()] + EXTRA.get(name, [])
        for f in files:
            dest = project / TARGET[f.suffix] / f.name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(strip(f.read_text()))


def main():
    if sys.argv[1:2] == ["assemble"]:
        assemble(sys.argv[2], sys.argv[3])
        return
    generate()


if __name__ == "__main__":
    main()
