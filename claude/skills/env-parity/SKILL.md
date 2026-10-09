---
name: env-parity
description: Compare two environments (for example dev and staging) deployed from a GitOps repo, to answer "are dev and staging equivalent?", "why doesn't staging have X?", "is the config the same in both?", or "it's broken in both environments". Diffs what the deploy repo deploys to each from git, then compares live Argo CD apps and running image digests with read-only kubectl.
user_invocable: true
---

# Environment parity

Run, from the deploy repo:

```
~/.claude/skills/env-parity/scripts/env-parity.py dev staging
```

By default, environment `<env>` maps to `clusters/<env>/`, `apps/<app>/values-<env>.yaml`, and the kube context `<env>`. Change the layout with `--cluster-path 'deploy/{env}'`, `--apps-dir charts`, and `--context 'mycorp-{env}'`. The script reads git from the remote default branch, never the local checkout, and uses only read-only `kubectl get`. Add `--no-live` to skip the clusters, or `--ref <ref>` to compare a release tag.

It reports:

1. Apps deployed in one environment and not the other, from git.
2. Per-app differences in image, `enabled`, and replica settings, by full key path.
3. Argo CD apps present in only one cluster, and apps that are not Synced and Healthy.
4. Containers whose running image digest differs between the clusters. A container with two digests in one cluster has a partial rollout or a stale pod.

## Reading the result

Most differences are on purpose: dev often floats on a moving image tag while later environments pin release digests, and some apps run only in dev. Do not hand the user the raw output. Sort it into:

- **Expected**: dev-only apps, tag versus digest pins, and features deliberately off in the later environment. Summarise these in one line.
- **Probably drift**: a feature on in one environment and off in the other with no comment or ticket explaining it, an app missing that a customer-facing flow needs, or a pinned digest older than the last release.
- **Broken now**: apps not Synced and Healthy, crash loops, and two digests for one container.

For the answer to "why doesn't staging have X", find the commit or PR that added X to dev (`git log origin/<default> -- <apps-dir>/<x> <cluster path for dev>`), and check whether a matching change for the other environment was ever made or ticketed.

Never change either cluster from this skill. Fixes go through deploy-repo PRs, and through releases for the later environments.
