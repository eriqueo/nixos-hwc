// Heartwood color palette — gruvbox-inspired dark theme
export const C = {
  bg:   'var(--surface-page)',
  card: 'var(--surface-card)',
  card2:'var(--surface-elevated)',
  brd:  'var(--border-default)',
  tx:   'var(--text-body)',
  txB:  'var(--text-heading)',
  txD:  'var(--text-muted)',
  acc:  'var(--interactive-accent)',
  accD: 'var(--interactive-accent-hover)',
  grn:  'var(--color-teal)',
  red:  'var(--color-red)',
  blu:  'var(--color-blue)',
  pur:  'var(--color-gold)',
  pnk:  'var(--color-coral)',
  teal: 'var(--color-teal)',
  ylw:  'var(--color-gold)',
};

// Phase/group accent colors
export const GROUP_COLORS = {
  'Preconstruction':  C.txD,
  'Demo':             C.red,
  'Rough Carpentry':  C.ylw,
  'Plumbing':         C.blu,
  'Electrical':       C.ylw,
  'Waterproofing':    C.teal,
  'Tilework':         C.pur,
  'Drywall':          C.pnk,
  'Painting':         C.grn,
  'Finish Carpentry': C.teal,
  'Allowances':       C.acc,
  'Additional':       C.txD,
};

export const mono = "'JetBrains Mono','SF Mono','Fira Code',monospace";
