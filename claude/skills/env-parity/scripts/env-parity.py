#!/usr/bin/env python3
"""Compare two environments of a GitOps deploy repo, from git and, read-only, from the live clusters.

Usage: env-parity.py dev staging [--repo .] [--ref origin/<default>] [--no-live]
                     [--cluster-path clusters/{env}] [--apps-dir apps] [--context {env}]
Environment <env> maps to <cluster-path>/, <apps-dir>/<app>/values-<env>.yaml, and kube context <context>.
The defaults suit an Argo CD repo with one folder per cluster and per-environment Helm values files.
"""
import argparse
import difflib
import json
import os
import re
import subprocess

VALUE_KEYS = re.compile(r"^\s*(tag|digest|repository|image|enabled|replicas|replicaCount):")


def run(*cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True).stdout


def git_apps(repo, ref, env, cluster_path):
    files = run("git", "ls-tree", "-r", "--name-only", ref, cluster_path.format(env=env).rstrip("/") + "/", cwd=repo).split()
    return {os.path.basename(f)[:-5] for f in files if f.endswith(".yaml") and ("/apps/" in f or "/templates/" in f)}


def value_paths(repo, ref, path):
    text = run("git", "show", f"{ref}:{path}", cwd=repo)
    if not text:
        return None
    out, stack = {}, []
    for line in text.splitlines():
        m = re.match(r"^(\s*)(?:- )?([\w.-]+):\s*(.*?)\s*(#.*)?$", line)
        if not m or line.lstrip().startswith("#"):
            continue
        indent, key, val = len(m.group(1)), m.group(2), m.group(3)
        while stack and stack[-1][0] >= indent:
            stack.pop()
        stack.append((indent, key))
        if val and VALUE_KEYS.match(f"{key}:"):
            out[".".join(k for _, k in stack)] = val.strip('"')
    return out


def kube(ctx, *args):
    out = run("kubectl", "--context", ctx, "--request-timeout=20s", *args, "-o", "json")
    return json.loads(out)["items"] if out else None


def section(title):
    print(f"\n## {title}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--ref", help="git ref to read; default: origin/<remote default branch>")
    ap.add_argument("--cluster-path", default="clusters/{env}")
    ap.add_argument("--apps-dir", default="apps")
    ap.add_argument("--context", default="{env}", help="kube context template")
    ap.add_argument("--no-live", action="store_true")
    args = ap.parse_args()
    a, b, repo, ref = args.a, args.b, args.repo, args.ref
    run("git", "fetch", "--quiet", "origin", cwd=repo)
    if not ref:
        head = run("git", "ls-remote", "--symref", "origin", "HEAD", cwd=repo).split()
        ref = "origin/" + (head[1].removeprefix("refs/heads/") if len(head) > 1 and head[0] == "ref:" else "main")
    print(f"# {a} vs {b}  (git: {ref} {run('git', 'rev-parse', '--short', ref, cwd=repo).strip()})")

    section("Apps deployed (git)")
    ga, gb = git_apps(repo, ref, a, args.cluster_path), git_apps(repo, ref, b, args.cluster_path)
    print(f"only in {a}: {', '.join(sorted(ga - gb)) or 'none'}")
    print(f"only in {b}: {', '.join(sorted(gb - ga)) or 'none'}")

    section("Per-environment values: image, enabled, replicas (git)")
    apps = sorted({p.split("/")[-2] for p in run("git", "ls-tree", "-r", "--name-only", ref, f"{args.apps_dir}/", cwd=repo).split()
                   if re.search(rf"/values-({a}|{b})\.yaml$", p)})
    any_diff = False
    deployed = {n.split("-", 1)[1] for n in ga & gb if "-" in n}
    for app in apps:
        va = value_paths(repo, ref, f"{args.apps_dir}/{app}/values-{a}.yaml")
        vb = value_paths(repo, ref, f"{args.apps_dir}/{app}/values-{b}.yaml")
        if va is None or vb is None:
            if app in deployed:
                print(f"{app}: values-{a if va is None else b}.yaml missing")
                any_diff = True
            continue
        keys = sorted(k for k in set(va) | set(vb) if va.get(k) != vb.get(k))
        if keys:
            any_diff = True
            print(f"{app}:")
            for k in keys:
                print(f"  {k}: {a}={va.get(k, '-')}  {b}={vb.get(k, '-')}")
    if not any_diff:
        print("no differences in tracked keys")

    if args.no_live:
        return
    ca, cb = args.context.format(env=a), args.context.format(env=b)

    section(f"Argo applications (live, {ca} vs {cb})")
    la, lb = kube(ca, "get", "applications.argoproj.io", "-A"), kube(cb, "get", "applications.argoproj.io", "-A")
    if la is None or lb is None:
        print("could not read Argo applications from one of the clusters (check kube context and login)")
    else:
        def state(items):
            return {i["metadata"]["name"]: (i.get("status", {}).get("sync", {}).get("status", "?"),
                                            i.get("status", {}).get("health", {}).get("status", "?")) for i in items}
        sa, sb = state(la), state(lb)
        print(f"only in {a}: {', '.join(sorted(set(sa) - set(sb))) or 'none'}")
        print(f"only in {b}: {', '.join(sorted(set(sb) - set(sa))) or 'none'}")
        for env, s in ((a, sa), (b, sb)):
            bad = [f"{n} ({sy}/{h})" for n, (sy, h) in sorted(s.items()) if (sy, h) != ("Synced", "Healthy")]
            print(f"not Synced/Healthy in {env}: {', '.join(bad) or 'none'}")

    section("Running image digests by namespace/container (live)")
    pa, pb = kube(ca, "get", "pods", "-A"), kube(cb, "get", "pods", "-A")
    if pa is None or pb is None:
        print("could not read pods from one of the clusters")
        return

    def digests(items):
        out = {}
        for p in items:
            for cs in p.get("status", {}).get("containerStatuses", []) or []:
                d = cs.get("imageID", "").rsplit("@", 1)[-1][:19]
                out.setdefault((p["metadata"]["namespace"], cs["name"]), set()).add(d)
        return out
    da, db = digests(pa), digests(pb)
    rows = [(k, da[k], db[k]) for k in sorted(set(da) & set(db)) if da[k] != db[k]]
    for (ns, c), x, y in rows:
        print(f"{ns}/{c}: {a}={','.join(sorted(x))}  {b}={','.join(sorted(y))}")
    print(f"{len(rows)} container(s) differ; {len(set(da) - set(db))} only in {a}; {len(set(db) - set(da))} only in {b}")


if __name__ == "__main__":
    main()
