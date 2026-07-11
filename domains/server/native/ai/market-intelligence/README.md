# Market Intelligence

Construction-sector earnings research. Monitors 12 public companies, runs
DeepSeek V4 analysis on earnings transcripts, logs deterministically-graded
directional signals, and serves a static dashboard. Independent of the hermes
agent and the market-trials dashboard, but reuses the hermes DeepSeek key.

- **Namespace:** `hwc.server.ai.marketIntelligence`
- **App code / state:** `/var/lib/hwc/market-intelligence` (Python package tree,
  SQLite DB, dashboard) — managed outside nix, like `hermes-agent/scripts`.
- **Dashboard:** Caddy static `vhost` file_server at
  `https://market-intelligence.hwc.iheartwoodcraft.com` over the tailnet
  (was port `:25445`; market-trials is `market-dashboard.hwc.iheartwoodcraft.com`).
- **Runtime:** `pkgs.python3.withPackages [ yfinance ]`; everything else stdlib.

## Schedule (systemd timers, America/Denver)

| Timer | When | Runs |
|-------|------|------|
| `market-intelligence-daily`  | Mon–Fri 15:00 | prices → new-earnings poll → grade due signals → rebuild dashboard → notify |
| `market-intelligence-weekly` | Fri 16:00     | daily + FRED macro panel + weekly digest |

## Secrets

| Env var | agenix secret | Notes |
|---------|---------------|-------|
| `DEEPSEEK_API_KEY`        | `hermes-deepseek-key` | reused from hermes (assertion requires hermes enabled) |
| `MARKET_INTEL_FMP_KEY`    | `market-intelligence-fmp-key`  | Financial Modeling Prep |
| `MARKET_INTEL_FRED_KEY`   | `market-intelligence-fred-key` | FRED (macro) |
| `MARKET_INTEL_DISCORD_WEBHOOK` | *(optional)* `discordWebhookSecret` | unset → jobs log a summary instead |

The job wrappers run as `eric` (who is in the `secrets` group) and `cat` the
keys from `/run/agenix` at runtime — no plaintext env file is written.

## Ops

```bash
# manual runs (as eric, on the server)
systemctl start market-intelligence-daily
journalctl -u market-intelligence-daily -f
systemctl list-timers 'market-intelligence-*'

# direct CLI (uses the same nix python the timers use)
cd /var/lib/hwc/market-intelligence
nix shell nixpkgs#python3.withPackages --impure --expr \
  'p: p.python3.withPackages(ps:[ps.yfinance])' -c python3 -m jobs.run status
```

Adding the FRED/FMP secrets (one-time): add the two `publicKeys` rules to
`secrets.nix`, then `sudo agenix -e domains/secrets/parts/services/market-intelligence-{fred,fmp}-key.age`.

## Changelog

- 2026-07-11: mkJobService — `User = lib.mkForce "eric"` per the native-services Architecture Law (was bare; covers market-intelligence-daily/-weekly; no-op today, verified by before/after eval).
- 2026-06-09: Dashboard access moved from static tailnet port `:25445` to name-based vhost `market-intelligence.hwc.iheartwoodcraft.com` under the shared `*.hwc.iheartwoodcraft.com` wildcard cert (rendered through the vhost `static` renderer; assets cached immutably). See `domains/networking/README.md`.
