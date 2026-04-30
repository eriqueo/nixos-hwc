# Heartwood Craft — Website UI Kit

The single product surface: a marketing website for Heartwood Craft. Recreates the brand's intended web presence based on `brand-guide.md` and the token set.

**No source codebase or Figma was provided.** This kit is a written-spec extrapolation, not a 1:1 recreation.

## Files

- `index.html` — interactive multi-page mock. Renders a clickable site with home, services detail, about, and contact routes. Uses JSX + Babel.
- `Header.jsx` — fixed header with logo, nav, and primary CTA.
- `Footer.jsx` — service areas + contact strip.
- `Hero.jsx` — full-bleed dark hero with editorial display type.
- `Services.jsx` — 4-up services grid card.
- `Process.jsx` — numbered 4-step process stack.
- `Testimonial.jsx` — pulled-quote treatment.
- `ContactForm.jsx` — consultation form matching CTA voice rules.
- `Button.jsx`, `Field.jsx`, `Eyebrow.jsx`, `Rule.jsx` — primitives.

## How to run

Open `index.html` directly — no build step. React + Babel from unpkg CDN.

## What's deliberately omitted

- Real photography — brand forbids stock. Placeholder panels used.
- Final logo lockup — uses `/assets/logo-wordmark-cream.svg` placeholder.
- Calculator tool mentioned in the brand guide (no detail provided).
- Blog / case-studies index (not scoped in brand guide).

## Iconography

Lucide via CDN (`https://unpkg.com/lucide@latest`). Stroke weight 1.75, `currentColor` fill rules. Flagged substitution — the brand guide doesn't specify an icon library.
