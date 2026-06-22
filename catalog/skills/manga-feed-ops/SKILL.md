---
name: manga-feed-ops
description: Use when adding, verifying, quarantining, or troubleshooting manga chapter feeds for FreshRSS through the homelab `manga-feeds` service, especially Gangan ONLINE title IDs, ヤンマガWeb slugs, and routes such as `gangan-online/2619.xml` or `yanmaga/<slug>.xml`. Covers OPML generation/import, K3s service checks, FreshRSS registration checks, the temporary `changedetection.io` quarantine category, and avoiding changedetection.io RSS for chapter-level manga feeds.
---

# Manga Feed Ops

## Overview

Use this skill to add manga chapter feeds to FreshRSS via the homelab `manga-feeds` service. The expected outcome is one FreshRSS feed per manga title, where each chapter appears as a separate RSS item.

Do not use changedetection.io RSS for this workflow; changedetection.io is only for coarse page-change alerts. While manga-feeds is still stabilizing, keep new manga-feeds subscriptions in the FreshRSS `changedetection.io` category as a quarantine area instead of the normal `Comic` category.

## Inputs

Required:

- FreshRSS user, usually `jey3dayo`.
- FreshRSS category. Use `changedetection.io` while the feed is still under observation; move stable feeds to `Comic` later.
- Manga title for the FreshRSS feed name.
- Provider identifier: Gangan ONLINE title ID from `https://www.ganganonline.com/title/2619`, or ヤンマガWeb slug from `https://yanmaga.jp/comics/<slug>`.

For Gangan ONLINE, the FreshRSS subscription URL is:

```text
http://manga-feeds.freshrss.svc.cluster.local:8080/gangan-online/<title-id>.xml
```

For ヤンマガWeb, the FreshRSS subscription URL is:

```text
http://manga-feeds.freshrss.svc.cluster.local:8080/yanmaga/<slug>.xml
```

Provider rule notes:

- Gangan ONLINE: fetch the title page, read `__NEXT_DATA__.buildId`, fetch `/_next/data/<buildId>/title/<title-id>.json`, and emit `chapters[]`.
- ヤンマガWeb: fetch `/comics/<slug>?sort=older`, parse `.mod-episode-item` entries, follow the page's `/episodes` XHR endpoint with `X-Requested-With: XMLHttpRequest` when a `mod-episode-more-button` is present, dedupe by episode URL, then sort by episode date.

## Workflow

1. Verify `manga-feeds` is deployed and reachable:

   ```bash
   kubectl -n freshrss get deployment,svc,pod -l app=manga-feeds
   kubectl -n freshrss run manga-feeds-check --rm -i --restart=Never \
     --image=curlimages/curl:8.11.1 -- \
     curl -fsS http://manga-feeds:8080/<provider>/<identifier>.xml
   ```

2. Check whether the feed is already registered and which category it is in. Show only the matching line and do not dump the full OPML because existing feeds may contain private tokens:

   ```bash
   kubectl -n freshrss exec deployment/freshrss -- sh -lc \
     'php /var/www/FreshRSS/cli/export-opml-for-user.php --user <user> | grep -F "manga-feeds.freshrss.svc.cluster.local:8080/<provider>/<identifier>.xml"'
   ```

3. Generate an OPML import file with `scripts/generate_opml.py`:

   ```bash
   python3 scripts/generate_opml.py \
     --provider <gangan-online|yanmaga> \
     --slug <title-id-or-slug> \
     --feed-title "<manga-title>" \
     --category changedetection.io \
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
   FreshRSS SimplePie GET 200 http://manga-feeds.freshrss.svc.cluster.local:8080/<provider>/<identifier>.xml
   ```

6. Verify registration and article creation with non-secret metadata only. FreshRSS containers may not have `sqlite3`, so use PHP PDO:

   ```bash
   kubectl -n freshrss exec "$pod" -- php -r '$db=new PDO("sqlite:/var/www/FreshRSS/data/users/<user>/db.sqlite"); foreach($db->query("select name,url from feed where url like \"%manga-feeds.freshrss.svc.cluster.local%<identifier>.xml%\"") as $r){echo $r["name"]."|".$r["url"]."\n";}'
   ```

## Category Policy

- Default new or experimental manga-feeds subscriptions to `changedetection.io` as a quarantine category.
- After the feed has stayed stable, the user can move it to `Comic` from the FreshRSS UI.
- Do not automatically move categories in the database unless the user explicitly asks. Category moves are user-facing organization changes.

## Scripts

- `scripts/generate_opml.py`: deterministic OPML generator for FreshRSS import. Use it instead of hand-writing OPML.

## Safety Notes

- Do not print full FreshRSS OPML exports; existing feeds can contain private tokens.
- Do not commit generated OPML files.
- Do not delete existing changedetection.io feeds automatically unless the user explicitly asks. Report that old changedetection feeds are coarse alerts and can be removed from the FreshRSS UI if no longer needed.
- If `kubectl` cannot connect because of sandboxing, rerun the same command with the required approval rather than changing the workflow.
