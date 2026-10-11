"""Sample mapping for the java-performance content (used by refresh.py).

setup: expand 0 = the environment check.
baseline: expand 0 = the policy-view + attach block (rollout wait lines dropped), expand 2 =
  the checklist answer as raw markdown.
improve-manifest, improve-image, improve-code: two blocks each, the Claude question and
  the combined roll-out block. Expand 0 = Claude's answer wrapped at 110 columns,
  expand 1 = the roll-out block up to "Pod is" (image and code: only the build, rollout,
  startup and heap-flag lines), expand 2 = the checklist from "Score:".
enforce: expand 0 = Claude's answer, expand 1 = the apply block.

A block re-run by hand replaces its expand with that real output; this mapping then
overwrites it on the next refresh, so re-run the block or restore the expand from git.
"""
from refresh import drop, keep, since, until, wrap

ROLLOUT_WAIT = r'^Waiting for deployment'


def refresh(s):
    s.set_expand('setup/index.en.md', 0, s.blocks('setup/index.en.md')[0])

    b = s.blocks('baseline/index.en.md')
    s.set_expand('baseline/index.en.md', 0, drop(b[0], ROLLOUT_WAIT))
    s.set_expand('baseline/index.en.md', 2, b[2], raw=True)

    for page in ('improve-manifest', 'improve-image', 'improve-code'):
        md = page + '/index.en.md'
        question, run = s.blocks(md)
        s.set_expand(md, 0, wrap(question))
        head = drop(until(run, 'Pod is'), ROLLOUT_WAIT)
        if page != 'improve-manifest':
            head = keep(head, '[build] docker build', '[build] pushed', 'deployment', '20', '-XX')
        s.set_expand(md, 1, head)
        s.set_expand(md, 2, since(run, 'Score:'))

    question, run = s.blocks('enforce/index.en.md')
    s.set_expand('enforce/index.en.md', 0, wrap(question))
    s.set_expand('enforce/index.en.md', 1, run)
