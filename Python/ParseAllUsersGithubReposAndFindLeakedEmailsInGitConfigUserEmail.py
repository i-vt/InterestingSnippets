#!/usr/bin/env python3
"""
github_leaked_emails.py — find email addresses leaked through git commit
metadata across all public repos of a GitHub account. (async edition)

GitHub can hide your email on your profile, but every commit permanently
embeds whatever was in `git config user.email` at commit time, and the API
serves it to anyone: /repos/{owner}/{repo}/commits  (and the .patch URL of
each commit). This tool walks repos -> branches -> commits concurrently,
dedupes by SHA, and reports every author/committer email that is NOT a
GitHub noreply.

Requires: pip install aiohttp

Usage:
    python3 github_leaked_emails.py <username-or-org>
    python3 github_leaked_emails.py i-vt --no-forks
    GITHUB_TOKEN=ghp_xxx python3 github_leaked_emails.py i-vt --json
    python3 github_leaked_emails.py i-vt --proxy http://user:pass@geo.proxyprovider.com:12321
    python3 github_leaked_emails.py i-vt --proxy ... --concurrency 16

Notes:
    - Set GITHUB_TOKEN to raise the rate limit (60/hr anonymous -> 5000/hr).
    - --proxy accepts any HTTP(S) proxy; rotating residential proxies also
      sidestep GitHub's per-IP anonymous rate limit.
    - Non-default branches are scanned too (leaks often hide there).
    - Concurrency is bounded per HTTP request, not per repo: the event loop
      can fan out freely while at most N requests are in flight.
    - Exit code is 1 if any leaked email is found (CI-friendly), else 0.
"""

import argparse
import asyncio
import json
import os
import sys
import urllib.parse
from collections import defaultdict

import aiohttp

API = "https://api.github.com"
NOREPLY_DOMAIN = "users.noreply.github.com"
NOREPLY_EXACT = {"noreply@github.com"}


class RateLimited(Exception):
    pass


def mask_proxy(proxy_url):
    """Strip credentials from a proxy URL for safe logging."""
    p = urllib.parse.urlsplit(proxy_url)
    host = p.hostname or ""
    if p.port:
        host += f":{p.port}"
    return urllib.parse.urlunsplit((p.scheme, host, "", "", ""))


def is_noreply(email):
    e = (email or "").lower()
    return e in NOREPLY_EXACT or e.endswith("@" + NOREPLY_DOMAIN)


async def http_get_json(session, url, sem, proxy, retries=6):
    """One GET with retries. The semaphore bounds in-flight requests;
    backoff sleeps happen OUTSIDE it so other tasks aren't blocked."""
    for attempt in range(retries):
        try:
            async with sem:
                async with session.get(
                        url, proxy=proxy,
                        timeout=aiohttp.ClientTimeout(total=60)) as r:
                    status, headers = r.status, r.headers
                    body = await r.text()

            if status == 404:
                return None
            if status == 409:                      # empty repo
                return []
            if status == 403 and headers.get("X-RateLimit-Remaining") == "0":
                # rotating proxy: next attempt likely exits a different IP
                if attempt < retries - 1:
                    await asyncio.sleep(3)
                    continue
                raise RateLimited(headers.get("X-RateLimit-Reset", "?"))
            if status in (403, 429) or status >= 500:
                if attempt < retries - 1:
                    wait = headers.get("Retry-After")
                    await asyncio.sleep(float(wait) if wait else 2 * (attempt + 1))
                    continue
                raise RuntimeError(f"HTTP {status} for {url}")
            try:
                return json.loads(body)
            except json.JSONDecodeError:
                # flaky proxies occasionally serve GitHub's HTML error page
                if attempt == retries - 1:
                    raise
                await asyncio.sleep(2 * (attempt + 1))
        except (aiohttp.ClientError, asyncio.TimeoutError):
            if attempt == retries - 1:
                raise
            await asyncio.sleep(2 * (attempt + 1))


async def paged(session, path, sem, proxy, params=None):
    """Async generator yielding every item from a paginated list endpoint."""
    page = 1
    while True:
        q = urllib.parse.urlencode({"per_page": 100, "page": page, **(params or {})})
        data = await http_get_json(session, f"{API}{path}?{q}", sem, proxy)
        if not data:
            return
        for item in data:
            yield item
        if len(data) < 100:
            return
        page += 1


async def scan_branch(full, bname, session, sem, proxy, hits, seen):
    async for c in paged(session, f"/repos/{full}/commits", sem, proxy,
                         {"sha": bname}):
        sha = c["sha"]
        if sha in seen:
            continue
        seen.add(sha)   # no await between check and add -> atomic on the loop

        git = c["commit"]
        for role in ("author", "committer"):
            person = git.get(role) or {}
            email = person.get("email") or ""
            if is_noreply(email):
                continue
            gh_user = (c.get(role) or {}).get("login")  # linked GH account
            hits[email.lower()].append({
                "email": email,
                "github_user": gh_user,
                "role": role,
                "repo": full,
                "branch": bname,
                "sha": sha,
                "date": person.get("date"),
                "message": (git.get("message") or "").splitlines()[0][:80],
                "patch_url": f"https://github.com/{full}/commit/{sha}.patch",
            })


async def scan_repo(repo, session, sem, proxy, hits, seen, failures):
    full = repo["full_name"]
    print(f"[repo] {full}", file=sys.stderr)
    try:
        branches = [b async for b in
                    paged(session, f"/repos/{full}/branches", sem, proxy)]
    except Exception as e:
        print(f"  WARNING: could not scan {full}: {e}", file=sys.stderr)
        failures.append(full)
        return
    results = await asyncio.gather(
        *(scan_branch(full, b["name"], session, sem, proxy, hits, seen)
          for b in branches),
        return_exceptions=True)
    if any(isinstance(r, Exception) for r in results):
        print(f"  WARNING: some branches of {full} failed", file=sys.stderr)
        failures.append(full + " (partial)")


async def scan(account, token, proxy, include_forks, concurrency):
    sem = asyncio.Semaphore(concurrency)
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "github-leaked-emails-scanner",
        **({"Authorization": f"Bearer {token}"} if token else {}),
    }
    async with aiohttp.ClientSession(headers=headers) as session:
        repos = [r async for r in
                 paged(session, f"/users/{account}/repos", sem, proxy,
                       {"type": "all"})]
        if not repos:   # maybe it's an org
            repos = [r async for r in
                     paged(session, f"/orgs/{account}/repos", sem, proxy,
                           {"type": "all"})]
        if not repos:
            sys.exit(f"error: no public repos found for '{account}' "
                     "(typo? private account?)")

        hits, seen, failures = defaultdict(list), set(), []
        tasks = []
        for repo in repos:
            if repo["fork"] and not include_forks:
                print(f"[skip fork] {repo['full_name']}", file=sys.stderr)
                continue
            tasks.append(scan_repo(repo, session, sem, proxy,
                                   hits, seen, failures))
        await asyncio.gather(*tasks)
    return hits, seen, failures


def main():
    ap = argparse.ArgumentParser(
        description="Find emails leaked via git commit metadata on a public "
                    "GitHub account. (async)")
    ap.add_argument("account", help="GitHub username or organization")
    ap.add_argument("--no-forks", action="store_true",
                    help="skip forked repositories")
    ap.add_argument("--json", action="store_true",
                    help="emit machine-readable JSON")
    ap.add_argument("--proxy", metavar="URL",
                    help="route traffic via proxy, e.g. http://user:pass@host:port "
                         "(default: $GITHUB_PROXY or $HTTPS_PROXY)")
    ap.add_argument("--concurrency", type=int, default=8, metavar="N",
                    help="max simultaneous HTTP requests (default: 8)")
    args = ap.parse_args()

    proxy = args.proxy or os.environ.get("GITHUB_PROXY") or \
        os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
    if proxy:
        print(f"note: routing via proxy {mask_proxy(proxy)} "
              "(credentials hidden)", file=sys.stderr)

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        print("note: GITHUB_TOKEN not set — anonymous rate limit is 60 req/hr",
              file=sys.stderr)

    try:
        hits, seen, failures = asyncio.run(
            scan(args.account, token, proxy,
                 include_forks=not args.no_forks,
                 concurrency=max(1, args.concurrency)))
    except RateLimited as e:
        sys.exit(f"error: GitHub rate limit exhausted (resets at epoch {e}). "
                 "Set GITHUB_TOKEN and/or use --proxy, then retry.")

    if args.json:
        print(json.dumps({k: v for k, v in sorted(hits.items())}, indent=2))
    else:
        print(f"\nScanned {len(seen)} unique commits.")
        if not hits:
            print("OK: no leaked emails — every commit uses a GitHub noreply "
                  "address.")
        else:
            print(f"LEAKED: {len(hits)} real email address(es) found in "
                  f"commit metadata:\n")
            for email, occ in sorted(hits.items()):
                users = sorted({o['github_user'] for o in occ
                                if o['github_user']})
                tag = (f"  (GitHub: {', '.join('@' + u for u in users)})"
                       if users else "")
                print(f"  {email}{tag} — {len(occ)} commit(s)")
                for o in occ[:10]:
                    print(f"    [{o['role']:9s}] {o['repo']}@{o['sha'][:10]}  "
                          f"{o['date']}  {o['message']}")
                    print(f"                {o['patch_url']}")
                if len(occ) > 10:
                    print(f"    ... and {len(occ) - 10} more")
            print("\nFix: rewrite history with git filter-repo, force-push, "
                  "enable 'Block command line pushes that expose my email' "
                  "in GitHub settings.")
        if failures:
            print(f"\nWARNING: {len(failures)} repo(s) could not be fully "
                  f"scanned: {', '.join(failures)}", file=sys.stderr)

    sys.exit(1 if hits else 0)


if __name__ == "__main__":
    main()
