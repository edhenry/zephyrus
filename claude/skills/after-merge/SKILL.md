---
name: after-merge
description: What to do when the user reports merging PRs ("Merged 57", "604 merged", "both merged", "all merged", "Merged and synced"). Confirms each merge reached the default branch, retargets stacked PRs, rebases PRs the merge put in conflict, checks the tracker, removes finished worktrees, proposes the dev rollout, starts an already-agreed next lane, and replies in the status-report layout.
user_invocable: true
---

# After a merge

The user merges PRs between replies and reports them in a few words. Work through every step below for every PR they name, even when the message also asks something else. Answer the question too.

## 1. Find each PR

Resolve each number to its repo from this session's work. When a number is ambiguous (the same number open in two repos), check both with `gh pr view` and use the one that is merged. Ask only if both are.

## 2. Confirm it landed on the default branch

```
gh pr view <n> --repo <owner/repo> --json state,baseRefName,headRefName,mergeCommit
git -C <repo> fetch origin
git -C <repo> merge-base --is-ancestor <mergeCommit> origin/<default> && echo landed
```

If the PR merged into anything other than the default branch (a stacked parent's branch), stop and say so first thing. The fix is one landing PR from the top of the stack, merged with the default branch, never a pile of re-merges.

## 3. Retarget stacked PRs and fix conflicts

```
gh pr list --repo <owner/repo> --base <merged PR's head branch> --json number,title
gh pr edit <child> --repo <owner/repo> --base <default>
```

Do this right away, without asking. GitHub only retargets children automatically when the parent's branch is deleted at merge. After retargeting, check that the child's diff contains only its own commits (`gh pr diff <child> --name-only`). With squash merges it may show the parent's commits again. If so, rebase it onto `origin/<default>` in its worktree and push with `--force-with-lease`.

Then check every other open PR from this effort for conflicts the merge caused, and rebase any that conflict, following section 6 of the `pull-request` skill.

## 4. Tracker

Most trackers' GitHub integrations move a ticket when the PR title or body carries its ID. Check that it did:

- Read the ticket. When its "Done when" is met and it is not Done, set it to Done.
- When the merge covers only part of the ticket, leave it open and add a comment saying what remains.
- When a PR had no ticket ID, say so in the reply.

## 5. Remove finished worktrees

For each merged branch's worktree:

- `git -C <worktree> status --porcelain` is empty: run `git -C <repo> worktree remove <worktree>` and `git -C <repo> branch -D <branch>`. Use `-D` because squash merges leave the branch looking unmerged.
- It is not empty: leave it, and list it in the reply with what is uncommitted.
- Never touch the user's own checkout or remote branches.

## 6. Propose the dev rollout

Work out how the change reaches the development environment, list the exact commands, and wait for the user's yes before running any of them. Read-only checks do not need a yes.

- **GitOps deploy repos (Argo CD, Flux).** The controller syncs the default branch. Check the app is synced and healthy at the merge commit. A change to a chart's env or ConfigMap restarts every pod in that chart on sync, so a config change and the code that depends on it may need separate PRs, merged in order.
- **App repos that publish a floating image tag** (for example `dev` or `latest`). Publishing a new image does not restart pods. Wait for the publish workflow to finish, compare running pods' image IDs with the new digest, and propose `kubectl rollout restart` for every deployment that lags, not only the one the change seems to target. A service left on the old image can fail to read data written by the new one, and retry forever without an alert.
- **Repos run locally.** Remind the user to pull their checkout. Where dependencies changed, give the install command the repo uses (for editable installs, `pip install -e` or `uv pip install -e`, never a plain install over an editable one).
- **Staging and production.** Never part of this skill. They move through the release process.

After an approved rollout, verify it: pods run the new digest, the app is synced and healthy, and nothing is crash-looping. When two environments may now differ in a way that matters, run the `env-parity` check.

## 7. Next lane

If the user already agreed to a next lane and this merge unblocks it, dispatch it now using the `agent-brief` skill, and say so in the reply. Otherwise list the lanes the merge unblocks and wait.

## 8. Reply

Use the `status-report` layout, kept short:

- Open with one line per PR: landed, or where it went wrong.
- Then what you did: retargeted, rebased, worktrees removed, tickets closed.
- "Needs you": the rollout commands waiting for a yes, the next merges in order, and open decisions.
- What started, if a lane was dispatched.

When a batch of lanes has merged or a phase is finished, end with one line suggesting `/checkpoint`.
