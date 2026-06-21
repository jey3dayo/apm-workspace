---
name: manga-feed-ops
description: Use when adding, verifying, or troubleshooting manga chapter feeds for FreshRSS through the homelab `manga-feeds` service, especially Gangan ONLINE title IDs and routes such as `gangan-online/2619.xml`. Covers OPML generation/import, K3s service checks, FreshRSS registration checks, and avoiding changedetection.io for chapter-level manga feeds.
---

# Manga Feed Ops

## Overview

Use this skill to add manga chapter feeds to FreshRSS via the homelab `manga-feeds` service. The expected outcome is one FreshRSS feed per manga title, where each chapter appears as a separate RSS item.

Do not use changedetection.io RSS for this workflow; changedetection.io is only for coarse page-change alerts.

## Inputs

Required:

- FreshRSS user, usually `jey3dayo`.
- FreshRSS category, usually `Comic`.
- Manga title for the FreshRSS feed name.
- Gangan ONLINE title ID from a URL like `https://www.ganganonline.com/title/2619`.

For Gangan ONLINE, the FreshRSS subscription URL is:

```text
http://manga-feeds.freshrss.svc.cluster.local:8080/gangan-online/<title-id>.xml
```

## Workflow

1. Verify `manga-feeds` is deployed and reachable:

   ```bash
   kubectl -n freshrss get deployment,svc,pod -l app=manga-feeds
   kubectl -n freshrss run manga-feeds-check --rm -i --restart=Never \
     --image=curlimages/curl:8.11.1 -- \
     curl -fsS http://manga-feeds:8080/gangan-online/<title-id>.xml
   ```

2. Check whether the feed is already registered. Show only the matching line and do not dump the full OPML because existing feeds may contain private tokens:

   ```bash
   kubectl -n freshrss exec deployment/freshrss -- sh -lc \
     'php /var/www/FreshRSS/cli/export-opml-for-user.php --user <user> | grep -F "manga-feeds.freshrss.svc.cluster.local:8080/gangan-online/<title-id>.xml"'
   ```

3. Generate an OPML import file with `scripts/generate_opml.py`:

   ```bash
   python3 scripts/generate_opml.py \
     --title-id <title-id> \
     --feed-title "<manga-title>" \
     --category Comic \
     --output /tmp/manga-feed.opml
   ```

4. Copy the OPML into the running FreshRSS Pod and import it:

   ```bash
   pod=$(kubectl -n freshrss get pod -l app=freshrss \
     --field-selector=status.phase=Running \
     -o jsonpath='{.items[0].metadata.name}')
   kubectl -n freshrss cp /tmp/manga-feed.opml "$pod:/tmp/manga-feed.opml"
   kubectl -n freshrss exec "$pod" -- \
     php /var/www/FreshRSS/cli/import-for-user.php \
       --user=<user> \
       --filename=/tmp/manga-feed.opml
   ```

5. Refresh FreshRSS and confirm the new feed was fetched:

   ```bash
   kubectl -n freshrss exec "$pod" -- \
     php /var/www/FreshRSS/cli/actualize-user.php --user=<user>
   ```

   Look for a log line like:

   ```text
   FreshRSS SimplePie GET 200 http://manga-feeds.freshrss.svc.cluster.local:8080/gangan-online/<title-id>.xml
   ```

6. Verify registration and article creation with non-secret metadata only. FreshRSS containers may not have `sqlite3`, so use PHP PDO:

   ```bash
   kubectl -n freshrss exec "$pod" -- php -r '$db=new PDO("sqlite:/var/www/FreshRSS/data/users/<user>/db.sqlite"); foreach($db->query("select name,url from feed where url like \"%manga-feeds.freshrss.svc.cluster.local%<title-id>.xml%\"") as $r){echo $r["name"]."|".$r["url"]."\n";}'
   ```

## Scripts

- `scripts/generate_opml.py`: deterministic OPML generator for FreshRSS import. Use it instead of hand-writing OPML.

## Safety Notes

- Do not print full FreshRSS OPML exports; existing feeds can contain private tokens.
- Do not commit generated OPML files.
- Do not delete existing changedetection.io feeds automatically unless the user explicitly asks. Report that old changedetection feeds are coarse alerts and can be removed from the FreshRSS UI if no longer needed.
- If `kubectl` cannot connect because of sandboxing, rerun the same command with the required approval rather than changing the workflow.
