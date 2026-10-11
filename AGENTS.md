# AGENTS.md

Sample apps and the infrastructure for the Java on AWS workshops. The workshop content lives
in sibling repositories (one per workshop, listed in `infra/workshops.json`), checked out next
to this one.

## Layout

- `apps/`: sample applications and workshop tools (`unicorn-store-spring`, the
  `perf-sensor` and `perf-profiler` samples, ...). The Java apps build with Maven; tests
  run with `mvn test` in the directory with the `pom.xml`.
- `infra/cdk/`: one CDK app that generates a CloudFormation template per workshop
  (`infra/workshops.json`); `infra/cfn/` holds the generated templates.
- `infra/scripts/ide/`: IDE bootstrap. `infra/scripts/templates/<workshop>.sh`: the
  workshop's post-deploy on the IDE. `infra/scripts/deploy/<workshop>/`: the per-workshop
  installs, plus `reset-app.sh` where a workshop can be reset to its starting point.
- `infra/scripts/ws-test/`: runs a workshop's content as a test, and the operator tools for
  a live environment. Read [its README](infra/scripts/ws-test/README.md) before a test run.

## Conventions

- Work on a branch cut from `origin/main` (`git checkout --no-track -b <name> origin/main`).
  Never commit on `main`; changes reach it as squash-merged pull requests.
- Commit messages: `type(scope): Summary` (`feat`, `fix`, `docs`, `test`, `chore`; scope =
  app, workshop or area, for example `perf-sensor`, `java-performance`, `ws-test`).
- Generated files are regenerated, never edited: `infra/cfn/*.yaml`
  (`cd infra && npm run gen`), the content repos' `static/` templates and IAM policies
  (`npm run sync`), `infra/scripts/ws-test/<workshop>.sh` (`node infra/scripts/ws-test/generate.mjs <workshop>`).
- The IDE clones `main` at bootstrap: a branch reaches a test environment only through
  `infra/scripts/ws-test/remote/sync-branch.sh`.
- Workshops are independent: a change for one workshop must not change another's template,
  scripts or policies. Shared code (the CDK constructs, `infra/scripts/lib/`, the apps) is
  changed with all users in mind. java-on-amazon-eks runs several java-performance deploy
  scripts through one-line wrappers (same app, sensor and profiler); a change there reaches
  both workshops.
- Shell scripts start with a header comment that says what the script does, its arguments
  and its side effects; they source `infra/scripts/lib/common.sh` for logging where they run
  on the IDE.
- No account IDs, instance IDs, bucket names or credentials in code or docs. Credentials
  for a test environment come from a git-ignored file (`WS_ENV_FILE`).
- Treat any AWS account as production unless shown otherwise: read before you change, and
  ask before deleting.
