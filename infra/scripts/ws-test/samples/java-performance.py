"""Sample mapping for the java-performance content (used by refresh.py).

setup: expand 0 = the environment check.
baseline: expand 0 = the policy-view + attach block (rollout wait lines dropped), expand 2 =
  the checklist answer as raw markdown. The profile-link block (block 3) has no expand.
improve-manifest, improve-code: two blocks each, the Claude question and the combined
  roll-out block. Expand 0 = Claude's answer wrapped at 110 columns, expand 1 = the roll-out
  block up to "Pod is" (code: only the build, rollout, startup and heap-flag lines), expand 2 =
  the checklist from "Score:".
improve-image: the AOT question and its build block, the CRaC question and its build block,
  then the profile link (no expand). Expands 0–4 = AOT answer, AOT build lines, CRaC answer,
  CRaC build lines up to "Pod is", the checklist from "Score:".
enforce: expand 0 = Claude's answer, expand 1 = the apply block.

A block re-run by hand replaces its expand with that real output; this mapping then
overwrites it on the next refresh, so re-run the block or restore the expand from git.
"""
from refresh import drop, keep, since, until, wrap

ROLLOUT_WAIT = r'^Waiting for deployment'
BUILD_LINES = ('[build] docker build', '[build] pushed', 'deployment', '20', '-XX')


def refresh(s):
    s.set_expand('setup/index.en.md', 0, s.blocks('setup/index.en.md')[0])

    b = s.blocks('baseline/index.en.md')
    s.set_expand('baseline/index.en.md', 0, drop(b[0], ROLLOUT_WAIT))
    s.set_expand('baseline/index.en.md', 2, b[2], raw=True)

    for page in ('improve-manifest', 'improve-code'):
        md = page + '/index.en.md'
        question, run = s.blocks(md)
        s.set_expand(md, 0, wrap(question))
        head = drop(until(run, 'Pod is'), ROLLOUT_WAIT)
        if page != 'improve-manifest':
            head = keep(head, *BUILD_LINES)
        s.set_expand(md, 1, head)
        s.set_expand(md, 2, since(run, 'Score:'))

    # improve-image: AOT question + build block, CRaC question + build block, profile link.
    md = 'improve-image/index.en.md'
    aot_q, aot_run, crac_q, crac_run = s.blocks(md)[:4]
    s.set_expand(md, 0, wrap(aot_q))
    s.set_expand(md, 1, keep(drop(aot_run, ROLLOUT_WAIT), *BUILD_LINES))
    s.set_expand(md, 2, wrap(crac_q))
    s.set_expand(md, 3, keep(drop(until(crac_run, 'Pod is'), ROLLOUT_WAIT), *BUILD_LINES))
    s.set_expand(md, 4, since(crac_run, 'Score:'))

    question, run = s.blocks('enforce/index.en.md')
    s.set_expand('enforce/index.en.md', 0, wrap(question))
    s.set_expand('enforce/index.en.md', 1, run)
