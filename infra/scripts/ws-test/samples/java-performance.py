"""Sample mapping for the java-performance content (used by refresh.py).

Each change in a module is split into short steps, each with its own block: Build (image
and code modules), Roll out (apply, rollout, startup line, commit), Score (the checklist).
Build blocks have no expand; Roll out expands drop the rollout wait lines; Score expands
start at "Score:". Claude's answers go in as markdown (raw), so its bold labels and lists
render as in Claude Code (no wrapping: markdown reflows, and a wrap
could split an inline code span). See refresh() for the blocks and expands per page.

A block re-run by hand replaces its expand with that real output; this mapping then
overwrites it on the next refresh, so re-run the block or restore the expand from git.
"""
from refresh import drop, since

ROLLOUT_WAIT = r'^Waiting for deployment'


def refresh(s):
    s.set_expand('setup/index.en.md', 0, s.blocks('setup/index.en.md')[0])

    # baseline: read the policy, opt in, the rule (expand 2 is the rule YAML, not refreshed),
    # the checklist question, the profile link (no expand).
    b = s.blocks('baseline/index.en.md')
    s.set_expand('baseline/index.en.md', 0, b[0])
    s.set_expand('baseline/index.en.md', 1, drop(b[1], ROLLOUT_WAIT))
    s.set_expand('baseline/index.en.md', 3, b[3], raw=True)

    # manifest: question, roll out, score.
    md = 'improve-manifest/index.en.md'
    question, rollout, score = s.blocks(md)
    s.set_expand(md, 0, question, raw=True)
    s.set_expand(md, 1, drop(rollout, ROLLOUT_WAIT))
    s.set_expand(md, 2, since(score, 'Score:'))

    # image: AOT question, build, roll out; CRaC question, build, roll out, score; profile link.
    md = 'improve-image/index.en.md'
    aot_q, _, aot_rollout, crac_q, _, crac_rollout, crac_score = s.blocks(md)[:7]
    s.set_expand(md, 0, aot_q, raw=True)
    s.set_expand(md, 1, drop(aot_rollout, ROLLOUT_WAIT))
    s.set_expand(md, 2, crac_q, raw=True)
    s.set_expand(md, 3, drop(crac_rollout, ROLLOUT_WAIT))
    s.set_expand(md, 4, since(crac_score, 'Score:'))

    # code: question, build, roll out, score.
    md = 'improve-code/index.en.md'
    question, _, rollout, score = s.blocks(md)
    s.set_expand(md, 0, question, raw=True)
    s.set_expand(md, 1, drop(rollout, ROLLOUT_WAIT))
    s.set_expand(md, 2, since(score, 'Score:'))

    question, run = s.blocks('enforce/index.en.md')
    s.set_expand('enforce/index.en.md', 0, question, raw=True)
    s.set_expand('enforce/index.en.md', 1, run)
