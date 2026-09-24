#!/bin/bash
# Зовнішні перевірки sneco.ua. Кожна перевірка з повтором; Telegram лише при збої (антиспам 60 хв) і при відновленні.
set -u
UA='Mozilla/5.0 (X11; Linux x86_64) Chrome/128 sneco-uptime/1.0'
MUA='Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1 sneco-uptime/1.0'
GB='Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'
B=https://sneco.ua
fail=''
add(){ fail="$fail
❌ $*"; }
chk(){  # url, маркер, [UA]
  local code=000 out
  for t in 1 2; do
    out=$(curl -sS -L --max-redirs 3 -A "${3:-$UA}" --compressed --max-time 30 -w '\n__%{http_code}' "$1" 2>&1 || true)
    code=${out##*__}
    if [ "$code" = 200 ] && grep -qF -- "$2" <<<"$out"; then return 0; fi
    sleep 20
  done
  add "$1 → HTTP $code або немає «$2»"
}
# 1) ключові сторінки (UA, каталог, товар, EU-вітрини) і доступ Google
chk $B/ 'snEco'
chk $B/shop/ 'add_to_cart_button'
chk $B/shop/gauda/ 'single_add_to_cart_button'
chk $B/en/ 'snEco'
chk $B/pl/shop/ '€'
chk $B/ 'snEco' "$GB"
chk $B/sitemap_index.xml 'sitemap'
chk $B/llms.txt 'snEco'
chk https://brand.sneco.ua/ 'snEco'
# 2) швидкість (TTFB головної, дві спроби)
slow=1; s=99
for t in 1 2; do
  s=$(curl -sS -o /dev/null -A "$UA" --max-time 30 -w '%{time_starttransfer}' $B/ || echo 99)
  if awk -v s="$s" 'BEGIN{exit !(s<4)}'; then slow=0; break; fi
  sleep 10
done
[ $slow = 1 ] && add "Головна відповідає повільно: TTFB ${s} с (> 4 с)"
# 3) індексація й аналітика
rb=$(curl -sS --max-time 20 $B/robots.txt || true)
if awk 'BEGIN{ua=0;f=0} /^User-agent:[ \t]*\*/{ua=1;next} /^User-agent:/{ua=0} ua && /^Disallow:[ \t]*\/[ \t]*$/{f=1} END{exit !f}' <<<"$rb"; then add "robots.txt закриває весь сайт (Disallow: /)"; fi
home=$(curl -sS -L -A "$UA" --compressed --max-time 30 $B/ || true)
grep -qiE '<meta[^>]+name="robots"[^>]+noindex' <<<"$home" && add "На головній стоїть noindex"
grep -qi 'rel="canonical"' <<<"$home" || add "На головній зник canonical"
grep -q 'GTM-PD4PGXZB' <<<"$home" || add "На головній немає GTM-PD4PGXZB (аналітика і реклама не рахують)"
css=0
for c in $(grep -oE 'wp-content/cache/min/[^"]+\.css' <<<"$home" | sort -u | head -3); do
  sz=$(curl -sS -A "$UA" -H 'Accept-Encoding: identity' --max-time 30 -o /dev/null -w '%{size_download}' "$B/$c" || echo 0)
  [ "${sz:-0}" -gt "$css" ] && css=$sz
done
[ "$css" -gt 20000 ] || add "CSS-бандл головної лише ${css} Б: сайт без стилів?"
# 4) шлях покупця: у кошик (Гауда 28 г) → кошик → оформлення
J=$(mktemp)
curl -sS -A "$UA" -c $J -b $J -o /dev/null --max-time 30 "$B/?add-to-cart=3474&quantity=1" || true
cart=$(curl -sS -L -A "$UA" -c $J -b $J --compressed --max-time 30 $B/cart/ || true)
if ! grep -q 'Гауда' <<<"$cart" || ! grep -q 'cart_item' <<<"$cart"; then add "Кошик не показує доданий товар (додавання в кошик зламане?)"; fi
co=$(curl -sS -L -A "$UA" -c $J -b $J --compressed --max-time 40 -w '\n__%{http_code}' $B/checkout/ || true)
if [ "${co##*__}" != 200 ] || ! grep -q 'billing_' <<<"$co"; then add "Сторінка оформлення замовлення: HTTP ${co##*__} або без форми"; fi
rm -f $J
# 5) EU-вітрини показують ціни в євро і на телефоні (кеш «отруювався» гривнями)
for u in /en/shop/ /de/shop/; do
  p=$(curl -sS -L -A "$MUA" --compressed --max-time 30 "$B$u" || true)
  ne=$(grep -o '€\|&euro;' <<<"$p" | wc -l); nu=$(grep -o '&#8372;\|₴\|грн' <<<"$p" | wc -l)
  [ "$ne" -ge 3 ] && [ "$nu" -eq 0 ] || add "$u (телефон): цін у € ${ne}, у гривнях ${nu} — валюта EU-вітрини зламалась"
done
# 6) фід каталогу Meta
fs=$(curl -sS -o /dev/null -A "$UA" -H 'Accept-Encoding: identity' --max-time 60 -w '%{http_code} %{size_download}' $B/facebook-feed.xml || echo '000 0')
[ "${fs% *}" = 200 ] && [ "${fs#* }" -gt 50000 ] || add "Фід Meta /facebook-feed.xml: HTTP ${fs% *}, ${fs#* } Б (реклама каталогу під загрозою)"
# 7) пульс сервера: серверні алерти (cron кожні 5 хв) живі
al=$(curl -sS -A "$UA" --max-time 20 "$B/sneco-alive.txt?t=$(date +%s)" | tr -dc '0-9')
if [ -n "$al" ]; then ag=$(( ($(date +%s) - al) / 60 )); [ "$ag" -gt 20 ] && add "Серверні алерти мовчать ${ag} хв (cron або сервер не працює)"
else add "Немає пульсу серверних алертів (sneco-alive.txt)"; fi
# 8) безпека: службові файли закриті, захист вебхука МойСклад працює
for u in /wp-content/sneco-fatal.log /wp-config.php /.htaccess; do
  c=$(curl -sS -o /dev/null -A "$UA" --max-time 20 -w '%{http_code}' "$B$u" || echo 000)
  [ "$c" = 403 ] || [ "$c" = 404 ] || add "$u відповідає HTTP $c (має бути 403/404)"
done
wg=$(curl -sS -o /dev/null -A "$UA" --max-time 20 -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
     --data '{"events":[{"meta":{"href":"https://example.invalid/"},"accountId":"x"}]}' "$B/?rest_route=/wooms/v1/order-update/" || echo 000)
[ "$wg" = 403 ] || add "Захист вебхука МойСклад: HTTP $wg замість 403"
# 9) сертифікат і адмінка
exp=$(echo | openssl s_client -servername sneco.ua -connect sneco.ua:443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
if [ -n "$exp" ]; then days=$(( ( $(date -d "$exp" +%s) - $(date +%s) ) / 86400 )); [ "$days" -lt 14 ] && add "Сертифікат sneco.ua спливає через ${days} дн."
else add "Не вдалось прочитати сертифікат sneco.ua"; fi
ad=$(curl -sS -o /dev/null -A "$UA" --max-time 30 -w '%{http_code}' $B/wp-admin/ || echo 000)
case "$ad" in 5*|000) add "Адмінка /wp-admin/ → HTTP $ad";; esac

# ---- повідомлення (антиспам через state/ з кешу Actions) ----
mkdir -p state; now=$(date +%s)
tg(){ [ -n "${TG_TOKEN:-}" ] && curl -sS -o /dev/null --data-urlencode "chat_id=$TG_CHAT" --data-urlencode "text=$1" \
      --data-urlencode "disable_web_page_preview=true" "https://api.telegram.org/bot${TG_TOKEN}/sendMessage"; }
if [ -n "$fail" ]; then
  h=$(printf '%s' "$fail" | sha1sum | cut -c1-12); read -r ph pt < state/last 2>/dev/null || { ph=''; pt=0; }
  if [ "$h" != "$ph" ] || [ $((now - pt)) -ge 3600 ]; then tg "🔴 [sneco uptime]$fail"; echo "$h $now" > state/last; fi
  printf 'FAILED:%s\n' "$fail"; exit 1
fi
if [ -s state/last ]; then tg "✅ [sneco uptime] усі зовнішні перевірки знову зелені"; rm -f state/last; fi
echo "all green (TTFB ${s}s, CSS ${css} B, feed ${fs#* } B, pulse ${ag:-?} min, cert ${days:-?} d)"
