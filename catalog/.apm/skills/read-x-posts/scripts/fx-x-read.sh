#!/usr/bin/env bash
# Read a public X post / profile / feed via FxTwitter (no API key).
# Usage:
#   fx-x-read.sh status <id-or-url>
#   fx-x-read.sh thread <id-or-url>
#   fx-x-read.sh profile <handle>
#   fx-x-read.sh feed <handle>
set -euo pipefail
cmd="${1:-}"
arg="${2:-}"
id_from() { echo "$1" | sed -E 's#.*/status/([0-9]+).*#\1#; s#.*/article/([0-9]+).*#\1#'; }
case "$cmd" in
  status) id=$(id_from "$arg"); curl -s "https://api.fxtwitter.com/2/status/$id" ;;
  thread) id=$(id_from "$arg"); curl -s "https://api.fxtwitter.com/2/thread/$id" ;;
  profile) h="${arg#@}"; curl -s "https://api.fxtwitter.com/2/profile/$h" ;;
  feed) h="${arg#@}"; curl -sL "https://fxtwitter.com/$h/feed.xml" ;;
  *) echo "usage: $0 {status|thread|profile|feed} <id|url|handle>" >&2; exit 2 ;;
esac
echo
