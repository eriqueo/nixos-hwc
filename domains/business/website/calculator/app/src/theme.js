// ─── Heartwood Craft Design Tokens ─────────────────────────────────────────
// Matches the site's warm cream/copper palette instead of dark Gruvbox.
// Used by both BathroomCalculator and DeckCalculator.

export const T = {
  // Brand
  copper: "#cf995f",
  copperDark: "#b8864e",
  copperLight: "#F5EDE4",
  copperMid: "#E8D5C4",
  copperBorder: "rgba(207,153,95,0.3)",
  copperGlow: "rgba(207,153,95,0.08)",

  // Backgrounds
  pageBg: "#E8E1D5",       // site's cream background
  cardBg: "#ffffff",
  surfaceBg: "#f7f5f0",    // subtle warm off-white
  sidebarBg: "#23282d",    // dark charcoal for estimate sidebar

  // Text
  heading: "#23282d",
  text: "#2d2d2d",
  textMuted: "#6b7280",
  textLight: "#9ca3af",
  textOnDark: "#e8e4df",
  textOnDarkMuted: "#9ca3af",

  // Borders
  border: "#e5e7eb",
  borderHover: "#d1d5db",
  borderSelected: "#cf995f",

  // Interactive
  white: "#ffffff",
  charcoal: "#23282d",
  success: "#059669",
  successBg: "#ecfdf5",

  // Shadows
  cardShadow: "0 1px 3px rgba(0,0,0,0.06), 0 1px 2px rgba(0,0,0,0.04)",
  cardShadowHover: "0 4px 12px rgba(0,0,0,0.08), 0 2px 4px rgba(0,0,0,0.04)",
};

// Font stacks
export const fonts = {
  sans: "'DM Sans', 'Helvetica Neue', Arial, sans-serif",
  serif: "'Playfair Display', Georgia, serif",
};

// Google Fonts URL (load once in the root component)
export const fontsUrl =
  "https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=Playfair+Display:wght@600;700&display=swap";
