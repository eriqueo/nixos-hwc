// ─── MobileEstimateBar ─────────────────────────────────────────────────────
// Compact sticky bar shown at the bottom on mobile instead of the sidebar.
// Shows the running estimate + step progress dots.

import { T, fonts } from "./theme";

export default function MobileEstimateBar({ lo, hi, step, totalSteps, fmt, phase }) {
  const showDollars = phase === "results" || phase === "submitted";

  return (
    <div
      style={{
        position: "fixed",
        bottom: 0,
        left: 0,
        right: 0,
        background: T.sidebarBg,
        padding: "14px 20px",
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        zIndex: 100,
        borderTop: "1px solid rgba(255,255,255,0.1)",
        fontFamily: fonts.sans,
      }}
    >
      <div>
        {showDollars ? (
          <div style={{ fontFamily: fonts.serif, fontSize: 24, fontWeight: 700, color: T.white, lineHeight: 1.2 }}>
            {fmt(lo)} – {fmt(hi)}
          </div>
        ) : (
          <div style={{ fontSize: 16, color: T.textOnDarkMuted }}>
            {step > 0 ? `Step ${step} of ${totalSteps}` : "Your selections"}
          </div>
        )}
      </div>
      <div style={{ display: "flex", gap: 5, alignItems: "center" }}>
        {Array.from({ length: totalSteps }).map((_, i) => (
          <div
            key={i}
            style={{
              width: 8,
              height: 8,
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
