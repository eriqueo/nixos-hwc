#!/usr/bin/env bash
# web-speed — Lighthouse CLI wrapper for iheartwoodcraft.com
# Usage: web-speed --mobile | web-speed --desktop

set -euo pipefail

URL="https://iheartwoodcraft.com"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LIGHTHOUSE="$HOME/.npm-global/bin/lighthouse"

# Find chromium binary (playwright in nix store, or system chromium)
find_chrome() {
  # Check PATH first
  if command -v chromium &>/dev/null; then
    echo "$(command -v chromium)"
    return
  fi
  if command -v google-chrome-stable &>/dev/null; then
    echo "$(command -v google-chrome-stable)"
    return
  fi
  # Playwright chromium in nix store
  local pw_chrome
  pw_chrome=$(ls /nix/store/*-playwright-chromium/chrome-linux/chrome 2>/dev/null | head -1)
  if [[ -n "$pw_chrome" ]]; then
    echo "$pw_chrome"
    return
  fi
  echo ""
}

CHROME_PATH=$(find_chrome)
if [[ -z "$CHROME_PATH" ]]; then
  echo "ERROR: No chromium binary found. Install chromium or ensure playwright-chromium is in nix store."
  exit 1
fi

export CHROME_PATH

case "${1:-}" in
  --mobile)
    echo "Running Lighthouse MOBILE audit on $URL..."
    echo "Chrome: $CHROME_PATH"
    echo ""
    "$LIGHTHOUSE" "$URL" \
      --form-factor=mobile \
      --screenEmulation.mobile \
      --throttling-method=simulate \
      --output=json --output=html \
      --output-path="/tmp/lighthouse-mobile-$TIMESTAMP" \
      --chrome-flags='--headless --no-sandbox --disable-gpu'
    echo ""
    echo "Reports saved to:"
    echo "  /tmp/lighthouse-mobile-$TIMESTAMP.report.html"
    echo "  /tmp/lighthouse-mobile-$TIMESTAMP.report.json"
    echo ""
    jq -r '
      (.categories.performance.score * 100 | tostring | "Performance Score: " + . + "/100"),
      (.audits["largest-contentful-paint"].displayValue | "LCP: " + .),
      (.audits["first-contentful-paint"].displayValue | "FCP: " + .),
      (.audits["total-blocking-time"].displayValue | "TBT: " + .),
      (.audits["cumulative-layout-shift"].displayValue | "CLS: " + .)
    ' "/tmp/lighthouse-mobile-$TIMESTAMP.report.json"
    ;;
  --desktop)
    echo "Running Lighthouse DESKTOP audit on $URL..."
    echo "Chrome: $CHROME_PATH"
    echo ""
    "$LIGHTHOUSE" "$URL" \
      --form-factor=desktop \
      --screenEmulation.disabled \
      --throttling-method=simulate \
      --output=json --output=html \
      --output-path="/tmp/lighthouse-desktop-$TIMESTAMP" \
      --chrome-flags='--headless --no-sandbox --disable-gpu'
    echo ""
    echo "Reports saved to:"
    echo "  /tmp/lighthouse-desktop-$TIMESTAMP.report.html"
    echo "  /tmp/lighthouse-desktop-$TIMESTAMP.report.json"
    echo ""
    jq -r '
      (.categories.performance.score * 100 | tostring | "Performance Score: " + . + "/100"),
      (.audits["largest-contentful-paint"].displayValue | "LCP: " + .),
      (.audits["first-contentful-paint"].displayValue | "FCP: " + .),
      (.audits["total-blocking-time"].displayValue | "TBT: " + .),
      (.audits["cumulative-layout-shift"].displayValue | "CLS: " + .)
    ' "/tmp/lighthouse-desktop-$TIMESTAMP.report.json"
    ;;
  *)
    echo "Usage: web-speed --mobile | web-speed --desktop"
    exit 1
    ;;
esac
