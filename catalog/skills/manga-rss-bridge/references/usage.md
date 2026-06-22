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
