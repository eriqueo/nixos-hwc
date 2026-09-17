// VENDORED from scout/packages/ui/src/styles/palette.css (HWC palette).
// Do not edit here: change the canonical file and re-copy. The hwc-ui lint
// (L6) fails when this copy drifts from the canonical body below. Carried as
// a TS module because the board is one esbuild bundle and the tests run tsc
// output under node, neither of which can import a .css file.
// (A backtick in a palette comment is escaped here; the evaluated CSS is verbatim.)
export const PALETTE_CSS = `
:root {
  /* ── Surfaces ── */
  --color-base-900: #1d2021;
  --color-base-800: #23282d;
  --color-base-700: #2a2f34;
  --color-base-600: #3a3f44;
  --color-base-500: #4a4f54;

  /* ── Text ── */
  --color-cream-100: #ebdbb2;
  --color-cream-200: #d5c4a1;
  --color-cream-300: #a7aaad;
  --color-cream-400: #6b7075;

  /* ── Accents ── */
  --color-copper: #cf995f;
  --color-copper-dim: #a67a4a;
  --color-red: #9d0006;
  --color-blue: #0085ba;
  --color-gold: #d79921;
  --color-teal: #4ec9b0;
  --color-coral: #cc4444;
  --color-green: #a3be8c; /* sage success — matches nixos hwc.nix \`success\` */

  /* ── Typography ── */
  --font-display: 'Playfair Display', Georgia, serif;
  --font-body: 'DM Sans', system-ui, sans-serif;
  --font-mono: 'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace;

  /* ── Spacing ── */
  --space-xs: 4px;
  --space-sm: 8px;
  --space-md: 12px;
  --space-lg: 16px;
  --space-xl: 24px;
  --space-2xl: 32px;

  /* ── Radii ── */
  --radius-sm: 4px;
  --radius-md: 6px;
  --radius-lg: 8px;

  /* ── Shadows ── */
  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.3);
  --shadow-md: 0 2px 8px rgba(0, 0, 0, 0.4);
}
`;
