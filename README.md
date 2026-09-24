# sneco-uptime

External monitor for https://sneco.ua every 15 minutes (GitHub Actions, public repo = free minutes). On failure the owner gets a Telegram message (same failure at most once per hour, plus a recovery message).

Checks: key pages (UA, catalog, product, EN/PL, Googlebot, brand book), TTFB, robots/noindex/canonical/GTM, CSS bundle, add-to-cart → cart → checkout, EUR prices on EU storefronts (mobile), Meta catalog feed, server alert heartbeat, closed service files, MoySklad webhook guard, TLS certificate, admin reachability.

Server-side alerts live on the server (`/usr/local/sbin/sneco_alerts.sh`, source: private repo `dreamcarua/sneco`, `wp-fix/monitoring/`).

Secrets: `TG_TOKEN`, `TG_CHAT`. Nothing sensitive is printed to logs.
