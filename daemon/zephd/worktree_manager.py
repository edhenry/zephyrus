"""Git worktree manager — creates isolated working directories per task."""

from __future__ import annotations

import asyncio
import hashlib
import logging
import re
from pathlib import Path

logger = logging.getLogger("zephd.worktree")

WORKTREE_BASE = Path.home() / ".zephyrus" / "worktrees"


def _slugify(text: str, max_len: int = 30) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower())
    return slug[:max_len].strip("-")


def _repo_hash(repo_path: str) -> str:
    return hashlib.sha256(str(Path(repo_path).resolve()).encode()).hexdigest()[:16]


async def _run(cmd: str, cwd: str | None = None) -> tuple[int, str, str]:
    proc = await asyncio.create_subprocess_shell(
        cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=cwd,
    )
    stdout, stderr = await proc.communicate()
    return proc.returncode, stdout.decode().strip(), stderr.decode().strip()


def worktree_path(repo_path: str, task_id: str, task_title: str = "") -> Path:
    """Compute the worktree path for a task."""
    repo_name = Path(repo_path).resolve().name
    slug = f"{task_id[:12]}-{_slugify(task_title)}" if task_title else task_id[:12]
    return WORKTREE_BASE / repo_name / slug


async def create_worktree(
    repo_path: str,
    branch: str,
    task_id: str,
    task_title: str = "",
) -> Path | None:
    """Create a git worktree for a task. Returns the worktree path or None on failure."""
    wt_path = worktree_path(repo_path, task_id, task_title)

    if wt_path.exists():
        logger.info("Worktree already exists: %s", wt_path)
        return wt_path

    wt_path.parent.mkdir(parents=True, exist_ok=True)

    # Ensure the branch exists locally
    code, _, _ = await _run(f"git rev-parse --verify {branch}", cwd=repo_path)
    if code != 0:
        # Create branch from HEAD
        code, _, err = await _run(f"git branch {branch}", cwd=repo_path)
        if code != 0:
            logger.error("Failed to create branch %s: %s", branch, err)
            return None

    # Create the worktree
    code, out, err = await _run(
        f"git worktree add {wt_path} {branch}",
        cwd=repo_path,
    )
    if code != 0:
        logger.error("Failed to create worktree: %s", err)
        return None

    logger.info("Created worktree at %s (branch=%s)", wt_path, branch)
    return wt_path


async def remove_worktree(repo_path: str, wt_path: str) -> bool:
    """Remove a git worktree."""
    code, _, err = await _run(
        f"git worktree remove --force {wt_path}",
        cwd=repo_path,
    )
    if code != 0:
        logger.error("Failed to remove worktree %s: %s", wt_path, err)
        return False

    await _run("git worktree prune", cwd=repo_path)

    # Remove parent dir if empty
    parent = Path(wt_path).parent
    if parent.exists() and not any(parent.iterdir()):
        parent.rmdir()

    logger.info("Removed worktree: %s", wt_path)
    return True


async def list_worktrees(repo_path: str) -> list[dict]:
    """List all git worktrees for a repository."""
    code, out, _ = await _run("git worktree list --porcelain", cwd=repo_path)
    if code != 0:
        return []

    worktrees = []
    current: dict = {}
    for line in out.split("\n"):
        if line.startswith("worktree "):
            if current:
                worktrees.append(current)
            current = {"path": line.split(" ", 1)[1]}
        elif line.startswith("HEAD "):
            current["head"] = line.split(" ", 1)[1]
        elif line.startswith("branch "):
            current["branch"] = line.split(" ", 1)[1].replace("refs/heads/", "")
        elif line == "bare":
            current["bare"] = True
        elif line == "detached":
            current["detached"] = True

    if current:
        worktrees.append(current)

    return worktrees


async def get_diff_summary(repo_path: str, branch: str, base_branch: str = "main") -> dict:
    """Get a diff summary between a branch and its base."""
    # Try the base branch, fall back to HEAD
    code, _, _ = await _run(f"git rev-parse --verify {base_branch}", cwd=repo_path)
    if code != 0:
        code, _, _ = await _run("git rev-parse --verify master", cwd=repo_path)
        base_branch = "master" if code == 0 else "HEAD~1"

    # Stat summary
    code, stat_out, _ = await _run(
        f"git diff --stat {base_branch}...{branch}",
        cwd=repo_path,
    )

    # File list
    code, files_out, _ = await _run(
        f"git diff --name-status {base_branch}...{branch}",
        cwd=repo_path,
    )

    # Shortstat
    code, short_out, _ = await _run(
        f"git diff --shortstat {base_branch}...{branch}",
        cwd=repo_path,
    )

    files = []
    for line in files_out.split("\n"):
        if line.strip():
            parts = line.split("\t", 1)
            if len(parts) == 2:
                files.append({"status": parts[0], "path": parts[1]})

    return {
        "branch": branch,
        "base": base_branch,
        "stat": stat_out,
        "shortstat": short_out,
        "files": files,
    }


async def merge_branch(repo_path: str, branch: str, target: str = "main") -> tuple[bool, str]:
    """Merge a branch into the target. Returns (success, message)."""
    # Check for conflicts first
    code, _, _ = await _run(f"git merge-tree $(git merge-base {target} {branch}) {target} {branch}", cwd=repo_path)

    # Checkout target
    code, _, err = await _run(f"git checkout {target}", cwd=repo_path)
    if code != 0:
        return False, f"Failed to checkout {target}: {err}"

    # Merge
    code, out, err = await _run(f"git merge --no-ff {branch} -m 'Merge {branch} into {target}'", cwd=repo_path)
    if code != 0:
        # Abort on conflict
        await _run("git merge --abort", cwd=repo_path)
        return False, f"Merge conflict: {err}"

    return True, f"Merged {branch} into {target}"


async def delete_branch(repo_path: str, branch: str) -> bool:
    """Delete a branch after merge."""
    code, _, _ = await _run(f"git branch -d {branch}", cwd=repo_path)
    return code == 0


async def clean_stale_worktrees(repo_path: str) -> list[str]:
    """Remove worktrees for merged/deleted branches."""
    await _run("git worktree prune", cwd=repo_path)
    worktrees = await list_worktrees(repo_path)
    cleaned = []

    for wt in worktrees:
        path = wt.get("path", "")
        if not Path(path).exists() or wt.get("bare"):
            continue
        # Check if it's a zephyrus-managed worktree
        if "/.zephyrus/worktrees/" in path:
            branch = wt.get("branch", "")
            # Check if branch still exists
            code, _, _ = await _run(f"git rev-parse --verify {branch}", cwd=repo_path)
            if code != 0:
                await remove_worktree(repo_path, path)
                cleaned.append(path)

    return cleaned
