#!/usr/bin/env python3
"""refresh.py WORKSHOP REPORT_DIR CONTENT_DIR — put a ws-test run's real output into the
"Sample ..." expands of the workshop content.

The per-workshop mapping samples/WORKSHOP.py defines refresh(s), with s a Samples object:
which block output goes into which expand, and how it is trimmed. Blocks are picked per
page in run order (blocks.json keys "page:start-end"), so line shifts in the content do
not matter. Expands are counted per page in order of `::::expand{header="Sample`.

The account ID in REPORT_DIR/account (written by remote/fetch-report.sh) is replaced
with 123456789012 everywhere. Review the result with git diff before committing.
"""
import importlib.util
import json
import re
import sys
import textwrap
from pathlib import Path

MASK = '123456789012'


class Samples:
    def __init__(self, report, content):
        self.content = Path(content)
        report = Path(report)
        account_file = report / 'account'
        account = account_file.read_text().strip() if account_file.exists() else None
        if not account:
            print(f'warning: no {account_file}, the account ID is not masked', file=sys.stderr)
        raw = json.loads((report / 'blocks.json').read_text())
        self.raw = {k: v.replace(account, MASK) if account else v for k, v in raw.items()}

    def blocks(self, page):
        """Outputs of the page's blocks, in run order."""
        keys = sorted((k for k in self.raw if k.startswith(page + ':')),
                      key=lambda k: int(k.split(':')[1].split('-')[0]))
        return [self.raw[k] for k in keys]

    def set_expand(self, page, n, body, lang='text', raw=False):
        """Replace the body of the page's n-th Sample expand (0-based). raw=True puts the
        text in as markdown, otherwise it goes into a code block of language lang."""
        path = self.content / page
        s = path.read_text()
        starts = [m.start() for m in re.finditer(r'::::expand\{header="Sample', s)]
        if n >= len(starts):
            raise SystemExit(f'{page}: no Sample expand #{n} (found {len(starts)})')
        a = starts[n]
        e = s.index('\n::::\n', a) + len('\n::::\n')
        head = s[a:s.index('\n', a) + 1]
        inner = body + '\n' if raw else \
            f':::code{{showCopyAction=false showLineNumbers=false language={lang}}}\n{body}\n:::\n'
        path.write_text(s[:a] + head + inner + '::::\n' + s[e:])


def drop(text, *patterns):
    """Lines matching none of the regex patterns."""
    return '\n'.join(l for l in text.split('\n') if not any(re.search(p, l) for p in patterns))


def keep(text, *prefixes):
    """Lines starting with one of the prefixes."""
    return '\n'.join(l for l in text.split('\n') if l.startswith(prefixes))


def until(text, marker):
    """Lines before the first line starting with marker."""
    out = []
    for l in text.split('\n'):
        if l.startswith(marker):
            break
        out.append(l)
    return '\n'.join(out).strip('\n')


def since(text, marker):
    """Text from the first occurrence of marker."""
    return text[text.index(marker):].strip('\n')


def wrap(text, width=110):
    """Wrap prose lines at width; bullets and numbered items keep their indent, tables and
    fences stay as they are."""
    out = []
    for l in text.split('\n'):
        if len(l) <= width or l.lstrip().startswith(('|', '```')):
            out.append(l)
            continue
        indent = ' ' * len(re.match(r'^(\s*(?:[-*] |\d+\. )?)', l).group(1))
        out.extend(textwrap.wrap(l, width, subsequent_indent=indent,
                                 break_long_words=False, break_on_hyphens=False))
    return '\n'.join(out)


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    workshop, report, content = sys.argv[1:]
    mapping = Path(__file__).with_name(workshop + '.py')
    spec = importlib.util.spec_from_file_location(workshop.replace('-', '_'), mapping)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.refresh(Samples(report, content))
    print('samples refreshed')
