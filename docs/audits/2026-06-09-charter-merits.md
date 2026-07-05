# Charter Merit Audit — does each law earn its place?

2026-06-09. Companion to `2026-06-09-server-audit.md` (which audited
*compliance*) and `CHARTER-v12-DRAFT.md` (which fixed *drift*). This document
audits the charter **on its merits**: not "does the repo follow the law" but
"is the law right, and is a law the right tool".

## Verdict in one paragraph

The charter's core bet — *architecture rules should be mechanically checkable*
— is correct and has demonstrably paid off (this audit was only possible
because namespaces map to folders and READMEs were current). Its failures are
all the same failure in different costumes: **rules that exist only as prose**.
Every law that shipped with a working lint held; every law that shipped with
aspiration (Law 8's taxonomy, Law 4's identity.nix, Law 12's readme-butler)
rotted. The charter also over-legislates *form* (three separate laws about
module shape) while leaving *behavior* ungoverned (exposure, updates, restore,
rotation) — it polices what is cheap to check rather than what is expensive to
get wrong.

## Law-by-law merit assessment

| Law | Merit | Assessment |
|---|---|---|
| 1 Handshake | **Strong** | Solves a real problem (dual HM activation, non-NixOS hosts). Lint exists, compliance is 100%. Keep. |
| 2 Namespace=folder | **Strong, was over-claimed** | The single highest-value rule in the repo: error message → file path in O(1), and it's what makes AI-agent navigation reliable. But "No exceptions permitted, never" was hubris — absolutism guaranteed the self-contradiction the audit found (`hwc.networking`). A law should be an invariant plus the §4 exception protocol; opting out of the protocol is how charters end up lying. |
| 3 Path abstraction | **Strong** | Real portability + single source of truth for storage layout. 35 violations is an adoption gap, not a design flaw. Keep; wire the lint into CI. |
| 4 Permission model | **Useful, but it's a trade-off wearing a principle's clothes** | UID-1000 monoculture buys permission simplicity at a real cost: any compromised service reaches *all* user data — and this box runs internet-adjacent services (vaultwarden, authentik). The law should state the trade-off honestly and define an isolation carve-out for exposed/credential-holding services rather than celebrating uniformity. The never-implemented `identity.nix` shows the abstraction wasn't actually needed — literals + a lint were enough. |
| 5 mkContainer | **Marginal** | The helper's payload (PUID/PGID/TZ/healthcheck) is small versus its indirection cost, and the "justification comment" escape hatch is unlintable in practice. Keep because it exists and works; don't expand it. |
| 6 Module structure | **Merged-merit** | See 9/10. |
| 7 sys.nix purity | **Good** | A genuinely clever answer to HM/system lane separation with co-location. The orphaned-sys.nix failure mode (protonmail-bridge) was a gap, now covered in v12. |
| 8 Retention | **Right idea, wrong altitude — currently a dead letter** | One match repo-wide. Nobody applies the CRITICAL/REPLACEABLE/AUTO-MANAGED taxonomy, and no lint checks it. Meanwhile the *actual* retention system that works is borg's exclude list + the cleanup timers. A law nobody follows actively damages the charter (it teaches readers that laws are optional). Either ship the lint and adopt, or demote to guideline and let v12 Law 15 (Runtime Hygiene) carry the enforceable part. |
| 9+10 Shape/locality | **One law in three coats** | Laws 6, 9, 10 all police the same concern: "module structure is predictable; options live in one place." Three numbered laws = three violation types, three exception protocols, three things to remember — for one outcome. Merge into a single Module Anatomy law next major version. The 16 leftover options.nix files survived three months *because* the rule's surface area was spread across three laws and none owned the lint. |
| 11 Evaluation order | **Documentation, not law** | Nothing enforces the DAG; Nix itself errors on true cycles. Useful as an architecture diagram; costless to keep, but it shouldn't count as a "law" since it has no violation a lint can catch that Nix wouldn't. |
| 12 README contract | **Strong — proven by use** | The audit traversed 16 domains quickly because READMEs were current; deletion rationales from May cleanups were recoverable from changelogs. This is the rare *process* law that held — because hooks nag. Note what made it work: enforcement, not virtue. |

## The three structural critiques

### 1. Prose rules rot; executable rules hold
The charter's own history is the proof. Every aspirational element — `identity.nix
(to be implemented)`, `readme-butler`, Law 8's taxonomy, v11.0's "eliminated 37
options.nix files" — decayed into fiction. Every linted element stayed true.
**Proposed constitutional rule for v12+: a law may enter the charter only
accompanied by its check** (flake check, eval assertion, or pre-commit hook).
If it can't be checked, it's labeled GUIDELINE and nobody pretends otherwise.

### 2. The charter governs form, not behavior
What the charter regulates: where files live, what they're named, where options
are declared. What it doesn't regulate: **what may be exposed to the internet
and under what hardening; when and how the system gets updated; whether backups
restore; when secrets rotate.** The expensive failures all live in the second
list. File-layout rules are valuable for maintainability, but the charter's
authority budget is being spent on the cheap-to-check. v12's Laws 13–15 start
correcting this; the exposure-tier and restore-drill rules (below) would finish it.

### 3. Know your reader
The charter's primary consumer today is not future-Eric skimming for fun — it's
**AI agents loaded with it on every session**, plus future-Eric debugging at
11pm. Both readers want: short laws, exact lint commands, a domain table that
matches `ls`. Neither benefits from rhetorical emphasis ("**No exceptions
permitted**") or sedimentary version archaeology. This argues for the charter
being *regenerated* each major version (structure rewritten, history appended)
— the duplicate "Section 5" was a sediment scar, not a typo.

## Beyond compliance: what would actually make this better

Ranked by expected value:

1. **Exposure tiers as data.** One attrset in Nix: `service → tier`
   (`local | tailnet | lan | public`). Firewall rules, Caddy route eligibility,
   cloudflared publication, and systemd hardening presets all *derive* from it.
   This converts the biggest ungoverned risk (what's reachable from where) into
   reviewable data — and it's exactly the data-driven pattern the rest of the
   config already follows. A new service can't accidentally become public; it
   has to declare a tier.
2. **Charter as flake checks.** `checks.x86_64-linux.charter-law<N>` wrapping
   §3 lints. `nix flake check` becomes the gate; CI runs it on push along with
   dry-builds for both hosts. This is the enforcement spine everything else
   hangs from.
3. **A tested restore path, not just backups.** Borg runs nightly, but
   "backups exist" and "restore works" are different facts. Adopt disko
   (declarative partitioning) + nixos-anywhere so bare-metal → running server
   is one command + borg restore, and do one restore drill (restore postgres
   dump + a service state dir to a scratch dir, diff). Write the runbook to
   `docs/runbooks/`.
4. **Secret rotation hygiene.** Known gap (rotation doesn't restart consumers
   — services cache secrets at startup). Mechanical fix: generator emits
   `restartTriggers = [ <age file hash> ]` for each service consuming a secret.
   One-time change in `domains/secrets/parts/lib.nix`, permanent payoff.
5. **Update cadence with a soak.** Scheduled monthly `nix flake update` branch
   → CI dry-builds both hosts → laptop switches first → server follows after a
   few quiet days. Today updates are ad-hoc, which is why pins accumulate
   without expiry (Law 14 now requires removal conditions; the cadence makes
   checking them routine).
6. **VM tests for the 2–3 services whose failure actually hurts.** NixOS's
   `nixosTest` can boot a VM and assert "caddy serves the routes", "postgres
   accepts the dump format borg stages". Expensive to write, so only for the
   pain points — but it converts "rebuild and pray" into "rebuild and know".
7. **Config observability.** Export to the existing Prometheus: charter-lint
   pass/fail, generation count, image staleness (days since pull), flake input
   age. The Grafana dashboard you already glance at becomes the place where
   drift shows up — instead of a manual audit nine months later (today's
   findings are mostly "nothing watched this").
8. **Decide where application source lives.** ~800 MB of node_modules inside
   `domains/` is the symptom; the cause is that TS *application source* lives
   inside the *system configuration* tree. Options: (a) keep co-location but
   formally exempt `src/` dirs and accept the weight; (b) move app source to a
   sibling repo (or repos) consumed as flake inputs with `buildNpmPackage` —
   config repo gets small and pure, apps get their own CI. (b) is the cleaner
   architecture; it costs multi-repo friction. Worth a deliberate ADR either
   way — right now it's an accident, not a decision.

## What NOT to change

- **agenix + the parts/**.age generator** — now a genuine strength; sops-nix
  migration would be motion without progress.
- **Dual-channel strategy** (laptop unstable / server stable) — correct and
  deliberate; the `-stable` input pair that the compliance audit initially
  flagged as duplication is in fact the right wiring.
- **Podman + mkContainer** — boring and working. Resist the k8s siren.
- **Preserve-first doctrine** — the May cleanup entries (eval-hash-verified
  deletions) show the discipline working exactly as designed. v12 keeps it
  verbatim.
