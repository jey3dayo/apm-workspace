# Manga RSS Bridge Usage

Manga RSS Bridge turns public manga work and chapter metadata into RSS feeds for self-hosted use. Users subscribe to provider-specific XML routes from an RSS reader such as FreshRSS.

## Quick Start

Install dependencies and start the local server:

```bash
pnpm install
pnpm dev
```

Open or request a feed:

```bash
curl http://localhost:8080/gangan-online/2061.xml
```

## Provider Routes

```text
http://localhost:8080/gangan-online/2061.xml
http://localhost:8080/kadocomi/KC_000733_S.xml
http://localhost:8080/comic-days/10834108156754578626.xml
http://localhost:8080/yanmaga/%E3%81%AD%E3%81%9A%E3%81%BF%E3%81%AE%E5%88%9D%E6%81%8B.xml
http://localhost:8080/manga-one/157056.xml
http://localhost:8080/gaugau/5f500f137765618260000000.xml
http://localhost:8080/firecross/331.xml
http://localhost:8080/jump-rookie/zGZPbQ9GPgM.xml
http://localhost:8080/hayacomic/a947a3d0ec0a1.xml
http://localhost:8080/mangabox/251785.xml
```

## Docker

Build and run locally:

```bash
docker build -t manga-rss-bridge .
docker run --rm -p 8080:8080 manga-rss-bridge
```

Run the GHCR image:

```bash
docker pull ghcr.io/jey3dayo/manga-rss-bridge:latest
docker run --rm -p 8080:8080 ghcr.io/jey3dayo/manga-rss-bridge:latest
```

## Common Checks

```bash
pnpm check
pnpm test
pnpm build
```

When mise is available, prefer:

```bash
mise run check
mise run ci
```

## Policy

This is an unofficial bridge for personal self-hosted use. It must not bypass authentication, paid content, DRM, or access controls. It should only read publicly available work or chapter metadata, and users should set reasonable fetch intervals.

## FreshRSS Homelab Operations

Use this section when adding, verifying, quarantining, or troubleshooting manga chapter feeds for FreshRSS through the homelab `manga-feeds` service.

Expected outcome: one FreshRSS feed per manga title, where each chapter appears as a separate RSS item. Do not use changedetection.io RSS for chapter-level manga feeds; changedetection.io is only for coarse page-change alerts.

Default new or experimental `manga-feeds` subscriptions to the FreshRSS `changedetection.io` category as a quarantine area. Move stable feeds to `Comic` later from the UI. Do not move categories in the database unless explicitly asked.

FreshRSS subscription URLs:

```text
http://manga-feeds.freshrss.svc.cluster.local:8080/gangan-online/<title-id>.xml
http://manga-feeds.freshrss.svc.cluster.local:8080/yanmaga/<slug>.xml
```

Provider notes:

- Gangan ONLINE: title ID comes from `https://www.ganganonline.com/title/<title-id>`.
- ヤンマガWeb: slug comes from `https://yanmaga.jp/comics/<slug>`.

Check service reachability:

```bash
kubectl -n freshrss get deployment,svc,pod -l app=manga-feeds
kubectl -n freshrss run manga-feeds-check --rm -i --restart=Never \
  --image=curlimages/curl:8.11.1 -- \
  curl -fsS http://manga-feeds:8080/<provider>/<identifier>.xml
```

Check whether a feed is already registered. Show only the matching line and do not dump full OPML because existing feeds may contain private tokens:

```bash
kubectl -n freshrss exec deployment/freshrss -- sh -lc \
  'php /var/www/FreshRSS/cli/export-opml-for-user.php --user <user> | grep -F "manga-feeds.freshrss.svc.cluster.local:8080/<provider>/<identifier>.xml"'
```

Generate OPML with the bundled script:

```bash
python3 scripts/generate_freshrss_opml.py \
  --provider <gangan-online|yanmaga> \
  --slug <title-id-or-slug> \
  --feed-title "<manga-title>" \
  --category changedetection.io \
  --output /tmp/manga-feed.opml
```

Import into FreshRSS:

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

Refresh and verify:

```bash
kubectl -n freshrss exec "$pod" -- \
  php /var/www/FreshRSS/cli/actualize-user.php --user=<user>
kubectl -n freshrss exec "$pod" -- php -r '$db=new PDO("sqlite:/var/www/FreshRSS/data/users/<user>/db.sqlite"); foreach($db->query("select name,url from feed where url like \"%manga-feeds.freshrss.svc.cluster.local%<identifier>.xml%\"") as $r){echo $r["name"]."|".$r["url"]."\n";}'
```

Safety notes:

- Do not print full FreshRSS OPML exports.
- Do not commit generated OPML files.
- Do not delete existing changedetection.io feeds automatically.
