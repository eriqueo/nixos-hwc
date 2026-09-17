// VENDORED from scout/packages/ui/src/styles/shell.css (HWC Workbench shell).
// Do not edit here: change the canonical file and re-copy. The hwc-ui lint
// (L6) fails when this copy drifts from the canonical body below. Carried as
// a TS module because the board is one esbuild bundle and the tests run tsc
// output under node, neither of which can import a .css file.
export const SHELL_CSS = String.raw`
/* HWC Workbench shell — the ONE producer of the application-shell layout for
   every Workbench area (CRM, Finance, Lead/Home/Research/Event Scout,
   Refinery). Canonical copy: scout/packages/ui/src/styles/shell.css.
   Non-scout apps vendor this file verbatim below a provenance header; the
   hwc-ui lint (L6) fails when a vendored copy drifts. Palette tokens only
   (--color-*, --font-*, --radius-*), so it works wherever palette.css does.

   Markup contract (framework-neutral):
     .wb-shell[data-rail=expanded|collapsed][data-scroll=page|pane]
       aside.wb-rail
         .wb-rail-head  > a.wb-rail-brand(.wb-rail-mark + .wb-rail-brand-copy) + button.wb-rail-toggle
         .wb-rail-area  > .wb-rail-label + select.wb-area-select
         nav.wb-rail-nav > .wb-rail-group(.wb-rail-group-tools)* > .wb-rail-label + .wb-rail-item*
           .wb-rail-item(button|a)[aria-pressed|aria-current] > .wb-rail-icon + .wb-rail-text + .wb-rail-count?
       .wb-body
         header.wb-topbar > .wb-topbar-title(.wb-eyebrow + .wb-title) + .wb-topbar-actions
         .wb-toolbar?  (app-owned strip between header and content)
         main.wb-main
   Desktop (>=1024px): persistent left rail, 248px, collapsible to 68px.
   Mobile: the rail becomes a top strip — mark + area select, then the
   groups as one horizontally scrolling row. Same DOM, no second markup. */

.wb-shell {
  --wb-rail-w: 248px;
  --wb-rail-w-collapsed: 68px;
  display: grid;
  grid-template-columns: var(--wb-rail-w) minmax(0, 1fr);
  min-height: 100dvh;
  background: var(--color-base-800);
  color: var(--color-cream-200);
  font-family: var(--font-body);
}
.wb-shell[data-rail="collapsed"] { grid-template-columns: var(--wb-rail-w-collapsed) minmax(0, 1fr); }
.wb-shell[data-scroll="pane"] { height: 100dvh; min-height: 0; overflow: hidden; }

/* ── Rail ── */
.wb-rail {
  position: sticky; top: 0;
  display: flex; flex-direction: column;
  height: 100dvh; min-width: 0;
  border-right: 1px solid var(--color-base-700);
  background: var(--color-base-900);
  z-index: 20;
}
.wb-rail-head {
  display: flex; align-items: center; gap: 10px;
  padding: 12px 12px;
  border-bottom: 1px solid var(--color-base-700);
}
.wb-rail-brand { display: flex; align-items: center; gap: 10px; min-width: 0; color: inherit; text-decoration: none; }
.wb-rail-mark {
  display: grid; place-items: center;
  width: 40px; height: 40px; flex: 0 0 40px;
  border: 1px solid var(--color-copper-dim);
  border-radius: var(--radius-md);
  background: color-mix(in srgb, var(--color-copper) 12%, transparent);
  color: var(--color-copper);
  font-family: var(--font-display); font-size: 22px; font-weight: 600;
  text-decoration: none;
}
.wb-rail-brand-copy { display: flex; flex-direction: column; min-width: 0; }
.wb-rail-brand-copy strong { overflow: hidden; color: var(--color-cream-100); font-family: var(--font-display); font-size: 15px; font-weight: 600; line-height: 1.2; text-overflow: ellipsis; white-space: nowrap; }
.wb-rail-brand-copy small { margin-top: 2px; color: var(--color-cream-400); font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.1em; text-transform: uppercase; white-space: nowrap; }
.wb-rail-toggle {
  display: grid; place-items: center;
  width: 44px; height: 44px; flex: 0 0 44px; margin-left: auto;
  border: 1px solid var(--color-base-600); border-radius: var(--radius-md);
  background: var(--color-base-800); color: var(--color-cream-300);
  font: inherit; font-size: 18px; cursor: pointer;
}
.wb-rail-toggle:hover { border-color: var(--color-copper); color: var(--color-copper); }

.wb-rail-area { display: flex; flex-direction: column; gap: 6px; padding: 12px; border-bottom: 1px solid var(--color-base-700); }
.wb-rail-label { color: var(--color-cream-400); font-family: var(--font-mono); font-size: 11px; letter-spacing: 0.12em; text-transform: uppercase; }
.wb-area-select {
  min-height: 44px; width: 100%; padding: 0 10px;
  border: 1px solid var(--color-base-600); border-radius: var(--radius-md);
  background: var(--color-base-800); color: var(--color-cream-100);
  font-family: var(--font-display); font-size: 14px; font-weight: 600;
  cursor: pointer;
}
.wb-area-select:focus { outline: none; border-color: var(--color-copper); }

.wb-rail-nav { display: flex; flex: 1; flex-direction: column; gap: 22px; min-height: 0; overflow-y: auto; padding: 14px 10px; }
.wb-rail-group { display: flex; flex-direction: column; gap: 3px; }
.wb-rail-group > .wb-rail-label { padding: 0 10px 6px; }
.wb-rail-group-tools { margin-top: auto; }
.wb-rail-item {
  display: flex; align-items: center; gap: 10px;
  width: 100%; min-height: 44px; padding: 8px 10px;
  border: 0; border-radius: var(--radius-md);
  background: transparent; color: var(--color-cream-300);
  font-family: var(--font-body); font-size: 14px; line-height: 1.3; text-align: left; text-decoration: none;
  cursor: pointer;
}
.wb-rail-item:hover { background: var(--color-base-700); color: var(--color-cream-100); }
.wb-rail-item[aria-pressed="true"], .wb-rail-item[aria-current] {
  box-shadow: inset 2px 0 var(--color-copper);
  background: var(--color-base-700); color: var(--color-cream-100);
}
.wb-rail-item:disabled { cursor: not-allowed; opacity: 0.4; }
.wb-rail-icon { display: inline-flex; align-items: center; justify-content: center; width: 18px; flex: 0 0 18px; color: var(--color-cream-400); font-family: var(--font-mono); font-size: 15px; }
.wb-rail-item[aria-pressed="true"] .wb-rail-icon, .wb-rail-item[aria-current] .wb-rail-icon { color: var(--color-copper); }
.wb-rail-icon[data-busy="true"] { animation: wb-spin 1s linear infinite; }
.wb-rail-text { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.wb-rail-count { min-width: 24px; margin-left: auto; padding: 1px 7px; border: 1px solid var(--color-base-600); border-radius: 999px; color: var(--color-cream-300); font-family: var(--font-mono); font-size: 11px; text-align: center; }
.wb-rail-empty { padding: 6px 10px; color: var(--color-cream-400); font-family: var(--font-mono); font-size: 12px; }

/* ── Body ── */
.wb-body { display: flex; flex-direction: column; min-width: 0; }
.wb-shell[data-scroll="pane"] .wb-body { min-height: 0; overflow: hidden; }
.wb-topbar {
  display: flex; flex: 0 0 auto; align-items: center; justify-content: space-between; gap: 16px;
  min-height: 64px; padding: 12px 20px;
  border-bottom: 1px solid var(--color-base-700);
  background: var(--color-base-800);
}
.wb-topbar-title { min-width: 0; }
.wb-eyebrow { display: block; color: var(--color-cream-400); font-family: var(--font-mono); font-size: 11px; letter-spacing: 0.1em; text-transform: uppercase; }
.wb-title { margin: 2px 0 0; overflow: hidden; color: var(--color-cream-100); font-family: var(--font-display); font-size: 20px; font-weight: 600; line-height: 1.2; text-overflow: ellipsis; white-space: nowrap; }
.wb-topbar-actions { display: flex; flex: 0 0 auto; flex-wrap: wrap; align-items: center; gap: 8px; }
.wb-toolbar { flex: 0 0 auto; }
.wb-main { min-width: 0; flex: 1; }
.wb-shell[data-scroll="pane"] .wb-main { min-height: 0; overflow-y: auto; }

/* ── Collapsed rail (desktop only) ── */
@media (min-width: 1024px) {
  .wb-shell[data-rail="collapsed"] .wb-rail-head { flex-direction: column; justify-content: center; gap: 8px; padding: 10px; }
  .wb-shell[data-rail="collapsed"] .wb-rail-brand-copy,
  .wb-shell[data-rail="collapsed"] .wb-rail-area,
  .wb-shell[data-rail="collapsed"] .wb-rail-label,
  .wb-shell[data-rail="collapsed"] .wb-rail-text,
  .wb-shell[data-rail="collapsed"] .wb-rail-count,
  .wb-shell[data-rail="collapsed"] .wb-rail-empty { display: none; }
  .wb-shell[data-rail="collapsed"] .wb-rail-toggle { margin-left: 0; }
  .wb-shell[data-rail="collapsed"] .wb-rail-nav { padding-inline: 8px; }
  .wb-shell[data-rail="collapsed"] .wb-rail-item { justify-content: center; padding-inline: 0; }
  .wb-shell[data-rail="collapsed"] .wb-rail-icon { width: auto; }
}

/* ── Mobile: rail becomes a top strip ── */
@media (max-width: 1023px) {
  .wb-shell, .wb-shell[data-rail="collapsed"] { display: flex; flex-direction: column; }
  .wb-shell[data-scroll="pane"] .wb-body { flex: 1; }
  .wb-rail {
    position: static; height: auto; flex: 0 0 auto;
    display: grid; grid-template-columns: auto minmax(0, 1fr); align-items: center;
    border-right: 0; border-bottom: 1px solid var(--color-base-700);
  }
  .wb-rail-head { border-bottom: 0; padding: 8px 8px 8px 12px; }
  .wb-rail-brand-copy, .wb-rail-toggle, .wb-rail-label { display: none; }
  .wb-rail-mark { width: 36px; height: 36px; flex-basis: 36px; font-size: 20px; }
  .wb-rail-area { padding: 8px 12px 8px 0; border-bottom: 0; }
  .wb-rail-nav { grid-column: 1 / -1; flex: 0 0 auto; flex-direction: row; gap: 6px; overflow-x: auto; overflow-y: hidden; padding: 4px 8px 8px; border-top: 1px solid var(--color-base-700); scrollbar-width: thin; }
  .wb-rail-group { flex-direction: row; gap: 4px; }
  .wb-rail-group + .wb-rail-group { margin-left: 4px; padding-left: 8px; border-left: 1px solid var(--color-base-700); }
  .wb-rail-group-tools { margin-top: 0; }
  .wb-rail-item { width: auto; flex: 0 0 auto; padding: 8px 12px; white-space: nowrap; }
  .wb-rail-item[aria-pressed="true"], .wb-rail-item[aria-current] { box-shadow: inset 0 -2px var(--color-copper); }
  .wb-rail-empty { white-space: nowrap; }
  .wb-topbar { flex-wrap: wrap; min-height: 56px; padding: 10px 14px; gap: 8px; }
  .wb-area-select, .wb-rail-item, .wb-rail-toggle { touch-action: manipulation; }
}

@keyframes wb-spin { to { transform: rotate(360deg); } }
@media (prefers-reduced-motion: reduce) {
  .wb-rail-icon[data-busy="true"] { animation: none; }
}
`;
