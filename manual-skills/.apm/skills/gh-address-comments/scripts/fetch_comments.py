#!/usr/bin/env python3
"""
Fetch all PR conversation comments + reviews + review threads (inline threads)
for a PR (the current branch's PR by default), by shelling out to:

  gh api graphql

Requires:
  - `gh auth login` already set up
  - without arguments, the current branch has an associated (open) PR

Usage:
  python fetch_comments.py [<owner>/<repo>] <number|PR URL> > pr_comments.json
  python fetch_comments.py > pr_comments.json   # PR of the current branch
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from typing import Any

USAGE = "usage: fetch_comments.py [<owner>/<repo>] <number|PR URL>"
PR_URL_RE = re.compile(r"^https://github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)(?:[/?#].*)?$")
REPO_RE = re.compile(r"^([^/\s]+)/([^/\s]+)$")

QUERY = """\
query(
  $owner: String!,
  $repo: String!,
  $number: Int!,
  $commentsCursor: String,
  $reviewsCursor: String,
  $threadsCursor: String
) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      number
      url
      title
      state

      # Top-level "Conversation" comments (issue comments on the PR)
      comments(first: 100, after: $commentsCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          body
          createdAt
          updatedAt
          author { login }
        }
      }

      # Review submissions (Approve / Request changes / Comment), with body if present
      reviews(first: 100, after: $reviewsCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          state
          body
          submittedAt
          author { login }
        }
      }

      # Inline review threads (grouped), includes resolved state
      reviewThreads(first: 100, after: $threadsCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          diffSide
          startLine
          startDiffSide
          originalLine
          originalStartLine
          resolvedBy { login }
          comments(first: 100) {
            nodes {
              id
              body
              createdAt
              updatedAt
              author { login }
            }
          }
        }
      }
    }
  }
}
"""


class GhNotFoundError(RuntimeError):
    pass


def _run(cmd: list[str], stdin: str | None = None) -> str:
    try:
        p = subprocess.run(cmd, input=stdin, capture_output=True, text=True)
    except FileNotFoundError:
        raise GhNotFoundError(f"{cmd[0]} not found on PATH") from None
    if p.returncode != 0:
        raise RuntimeError(f"Command failed: {' '.join(cmd)}\n{p.stderr}")
    return p.stdout


def _run_json(cmd: list[str], stdin: str | None = None) -> dict[str, Any]:
    out = _run(cmd, stdin=stdin)
    try:
        return json.loads(out)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Failed to parse JSON from command output: {e}\nRaw:\n{out}") from e


def _ensure_gh_authenticated() -> None:
    try:
        _run(["gh", "auth", "status"])
    except GhNotFoundError:
        raise
    except RuntimeError:
        raise RuntimeError("gh auth status failed; run `gh auth login` to authenticate the GitHub CLI") from None


def gh_pr_view_json(fields: str) -> dict[str, Any]:
    # fields is a comma-separated list like: "number,headRepositoryOwner,headRepository"
    return _run_json(["gh", "pr", "view", "--json", fields])


def get_current_pr_ref() -> tuple[str, str, int]:
    """
    Resolve the PR for the current branch (whatever gh considers associated).
    Works for cross-repo PRs too, by reading head repository owner/name.
    """
    pr = gh_pr_view_json("number,headRepositoryOwner,headRepository")
    owner = pr["headRepositoryOwner"]["login"]
    repo = pr["headRepository"]["name"]
    number = int(pr["number"])
    return owner, repo, number


def resolve_pr_ref(args: list[str]) -> tuple[str, str, int]:
    """
    Resolve (owner, repo, number) from CLI args:
      []                        -> PR of the current branch
      [<url>]                   -> owner/repo/number from the PR URL
      [<number>]                -> base repo as gh resolves it for the PR
      [<owner>/<repo>, <number>]
    """
    if not args:
        return get_current_pr_ref()
    if len(args) == 1:
        m = PR_URL_RE.match(args[0])
        if m:
            return m.group(1), m.group(2), int(m.group(3))
        if args[0].isdigit():
            # The PR URL carries the base repo, where the PR lives (headRepository would be a fork).
            url = _run_json(["gh", "pr", "view", args[0], "--json", "url"])["url"]
            m = PR_URL_RE.match(url)
            if not m:
                raise ValueError(f"unexpected PR URL from gh: {url}")
            return m.group(1), m.group(2), int(m.group(3))
        raise ValueError(f"not a PR number or URL: {args[0]}")
    if len(args) == 2:
        m = REPO_RE.match(args[0])
        if not m:
            raise ValueError(f"not an <owner>/<repo>: {args[0]}")
        if not args[1].isdigit():
            raise ValueError(f"not a PR number: {args[1]}")
        return m.group(1), m.group(2), int(args[1])
    raise ValueError("too many arguments")


def gh_api_graphql(
    owner: str,
    repo: str,
    number: int,
    comments_cursor: str | None = None,
    reviews_cursor: str | None = None,
    threads_cursor: str | None = None,
) -> dict[str, Any]:
    """
    Call `gh api graphql` using -F variables, avoiding JSON blobs with nulls.
    Query is passed via stdin using query=@- to avoid shell newline/quoting issues.
    """
    cmd = [
        "gh",
        "api",
        "graphql",
        "-F",
        "query=@-",
        "-F",
        f"owner={owner}",
        "-F",
        f"repo={repo}",
        "-F",
        f"number={number}",
    ]
    if comments_cursor:
        cmd += ["-F", f"commentsCursor={comments_cursor}"]
    if reviews_cursor:
        cmd += ["-F", f"reviewsCursor={reviews_cursor}"]
    if threads_cursor:
        cmd += ["-F", f"threadsCursor={threads_cursor}"]

    return _run_json(cmd, stdin=QUERY)


def fetch_all(owner: str, repo: str, number: int) -> dict[str, Any]:
    conversation_comments: list[dict[str, Any]] = []
    reviews: list[dict[str, Any]] = []
    review_threads: list[dict[str, Any]] = []

    comments_cursor: str | None = None
    reviews_cursor: str | None = None
    threads_cursor: str | None = None

    pr_meta: dict[str, Any] | None = None

    while True:
        payload = gh_api_graphql(
            owner=owner,
            repo=repo,
            number=number,
            comments_cursor=comments_cursor,
            reviews_cursor=reviews_cursor,
            threads_cursor=threads_cursor,
        )

        if "errors" in payload and payload["errors"]:
            raise RuntimeError(f"GitHub GraphQL errors:\n{json.dumps(payload['errors'], indent=2)}")

        pr = ((payload.get("data") or {}).get("repository") or {}).get("pullRequest")
        if pr is None:
            raise RuntimeError(f"PR not found: {owner}/{repo}#{number}")
        if pr_meta is None:
            pr_meta = {
                "number": pr["number"],
                "url": pr["url"],
                "title": pr["title"],
                "state": pr["state"],
                "owner": owner,
                "repo": repo,
            }

        c = pr["comments"]
        r = pr["reviews"]
        t = pr["reviewThreads"]

        conversation_comments.extend(c.get("nodes") or [])
        reviews.extend(r.get("nodes") or [])
        review_threads.extend(t.get("nodes") or [])

        comments_cursor = c["pageInfo"]["endCursor"] if c["pageInfo"]["hasNextPage"] else None
        reviews_cursor = r["pageInfo"]["endCursor"] if r["pageInfo"]["hasNextPage"] else None
        threads_cursor = t["pageInfo"]["endCursor"] if t["pageInfo"]["hasNextPage"] else None

        if not (comments_cursor or reviews_cursor or threads_cursor):
            break

    assert pr_meta is not None
    return {
        "pull_request": pr_meta,
        "conversation_comments": conversation_comments,
        "reviews": reviews,
        "review_threads": review_threads,
    }


def main(argv: list[str]) -> int:
    if any(a in ("-h", "--help") for a in argv):
        print(USAGE)
        return 0
    try:
        _ensure_gh_authenticated()
        owner, repo, number = resolve_pr_ref(argv)
        result = fetch_all(owner, repo, number)
    except (RuntimeError, ValueError, KeyError) as e:
        cause = " ".join(str(e).split()) or type(e).__name__
        print(f"{USAGE}\nerror: {cause}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
