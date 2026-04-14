// ─── MobileEstimateBar ─────────────────────────────────────────────────────
// Compact sticky bar shown at the bottom on mobile instead of the sidebar.
// Shows the running estimate + step progress dots.

import { T, fonts } from "./theme";

export default function MobileEstimateBar({ lo, hi, step, totalSteps, fmt }) {
  const hasEstimate = lo > 0;

  return (
    <div
      style={{
        position: "fixed",
        bottom: 0,
        left: 0,
        right: 0,
        background: T.sidebarBg,
        padding: "12px 20px",
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        zIndex: 100,
        borderTop: "1px solid rgba(255,255,255,0.1)",
        fontFamily: fonts.sans,
      }}
    >
      <div>
        {hasEstimate ? (
          <div style={{ fontFamily: fonts.serif, fontSize: 20, fontWeight: 700, color: T.white, lineHeight: 1.2 }}>
            {fmt(lo)} – {fmt(hi)}
          </div>
        ) : (
          <div style={{ fontSize: 13, color: T.textOnDarkMuted }}>Your estimate</div>
        )}
      </div>
      <div style={{ display: "flex", gap: 5, alignItems: "center" }}>
        {Array.from({ length: totalSteps }).map((_, i) => (
          <div
            key={i}
            style={{
              width: 7,
              height: 7,
              borderRadius: "50%",
              background: i < step ? T.copper : i === step ? T.copperDark : "rgba(255,255,255,0.15)",
              transition: "background 0.3s ease",
            }}
          />
        ))}
      </div>
    </div>
  );
}
