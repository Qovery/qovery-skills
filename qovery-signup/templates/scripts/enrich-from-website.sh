#!/usr/bin/env bash
# enrich-from-website.sh — derive candidate org profile fields (description, logo, icon)
# from a company's website, for populating a Qovery organization.
#
# Usage: bash enrich-from-website.sh <website-url-or-domain>
# Output: JSON on stdout: { website_url, domain, description, logo_url, icon_url }
#
# These are CANDIDATES — show them to the user and confirm before writing them to the org.
# Extraction is best-effort (og:image / og:description / meta description / icon links from
# the raw HTML) with deterministic fallbacks (Clearbit logo, Google favicon) so there is
# always a usable logo_url and icon_url.
set -euo pipefail

RAW="${1:?usage: enrich-from-website.sh <website-url-or-domain>}"

# Normalize to a URL + bare domain
case "$RAW" in
  http://*|https://*) URL="$RAW" ;;
  *) URL="https://$RAW" ;;
esac
DOMAIN="$(printf '%s' "$URL" | sed -E 's~^https?://~~; s~/.*$~~; s~^www\.~~')"

HTML="$(curl -sL --max-time 20 -A "Mozilla/5.0 (QoverySkill qovery-signup)" "$URL" 2>/dev/null || true)"

# Pull the content="..." value from the first matching meta tag (handles attr order both ways)
meta_content() { # $1 = attr (e.g. property="og:image")
  printf '%s' "$HTML" \
    | tr '\n' ' ' \
    | grep -oiE "<meta[^>]*$1[^>]*>" \
    | head -1 \
    | grep -oiE 'content="[^"]*"' \
    | head -1 \
    | sed -E 's/^content="//I; s/"$//'
}
link_href() { # $1 = rel value (e.g. icon, apple-touch-icon)
  printf '%s' "$HTML" \
    | tr '\n' ' ' \
    | grep -oiE "<link[^>]*rel=\"[^\"]*$1[^\"]*\"[^>]*>" \
    | head -1 \
    | grep -oiE 'href="[^"]*"' \
    | head -1 \
    | sed -E 's/^href="//I; s/"$//'
}
decode() { # decode the few HTML entities that commonly appear in URLs/descriptions
  printf '%s' "${1:-}" | sed -E 's/&amp;/\&/g; s/&#38;/\&/g; s/&quot;/"/g; s/&#39;/'"'"'/g; s/&apos;/'"'"'/g'
}
absolutize() { # $1 = maybe-relative URL
  case "${1:-}" in
    "" ) echo "" ;;
    http://*|https://*) echo "$1" ;;
    //*) echo "https:$1" ;;
    /*) echo "https://$DOMAIN$1" ;;
    *) echo "https://$DOMAIN/$1" ;;
  esac
}

DESC="$(decode "$(meta_content 'property="og:description"')")"
[ -n "$DESC" ] || DESC="$(decode "$(meta_content 'name="description"')")"

OG_IMAGE="$(decode "$(absolutize "$(meta_content 'property="og:image"')")")"
SITE_ICON="$(decode "$(absolutize "$(link_href 'apple-touch-icon')")")"
[ -n "$SITE_ICON" ] || SITE_ICON="$(decode "$(absolutize "$(link_href 'icon')")")"

CLEARBIT="https://logo.clearbit.com/$DOMAIN"
GFAVICON="https://www.google.com/s2/favicons?domain=$DOMAIN&sz=128"

# Best guesses + all discovered candidates so the agent can offer choices.
# Note: og:image is usually a social share card (wide); Clearbit is usually a square logo.
LOGO="${OG_IMAGE:-$CLEARBIT}"
ICON="${SITE_ICON:-$GFAVICON}"

jq -n \
  --arg website_url "$URL" --arg domain "$DOMAIN" --arg description "$DESC" \
  --arg logo_url "$LOGO" --arg icon_url "$ICON" \
  --arg og_image "$OG_IMAGE" --arg site_icon "$SITE_ICON" \
  --arg clearbit "$CLEARBIT" --arg gfavicon "$GFAVICON" \
  '{
     website_url:$website_url, domain:$domain, description:$description,
     logo_url:$logo_url, icon_url:$icon_url,
     candidates: {
       logos:  ([$og_image, $clearbit]  | map(select(. != "")) | unique),
       icons:  ([$site_icon, $gfavicon] | map(select(. != "")) | unique)
     }
   }'
