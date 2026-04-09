// ─── CalculatorLayout ──────────────────────────────────────────────────────
// Shared responsive wrapper for both calculators.
// Desktop: two-column grid (questions + sidebar). Mobile: single column + sticky bar.

import useIsMobile from "./useIsMobile";
import MobileEstimateBar from "./MobileEstimateBar";
import { T, fonts, fontsUrl } from "./theme";

export default function CalculatorLayout({
  children,
  sidebar,
  lo,
  hi,
  step,
  totalSteps,
  fmt,
  phase,
}) {
  const isMobile = useIsMobile(768);

  return (
    <div style={{ fontFamily: fonts.sans, color: T.text }}>
      <link href={fontsUrl} rel="stylesheet" />

      <div
        style={{
          display: isMobile ? "block" : "grid",
          gridTemplateColumns: isMobile ? undefined : "1fr 320px",
          gap: isMobile ? 0 : 32,
          maxWidth: isMobile ? 600 : 960,
          margin: "0 auto",
          padding: isMobile ? "0 1rem 5rem" : "0 1.5rem 3rem",
          alignItems: "start",
        }}
      >
        {/* Questions column */}
        <div>{children}</div>

        {/* Sidebar — hidden on mobile */}
        {!isMobile && sidebar}
      </div>

      {/* Mobile sticky estimate bar */}
      {isMobile && phase !== "submitted" && (
        <MobileEstimateBar lo={lo} hi={hi} step={step} totalSteps={totalSteps} fmt={fmt} />
      )}

      {/* Footer */}
      <div
        style={{
          maxWidth: isMobile ? 600 : 960,
          margin: "0 auto",
          padding: "20px 1.5rem 0",
          borderTop: `1px solid ${T.border}`,
          textAlign: "center",
          fontSize: 11,
          color: T.textLight,
          lineHeight: 1.7,
        }}
      >
        Heartwood Craft · Bozeman, Montana · 406-551-5061
        <br />
        Ranges based on actual Gallatin Valley project data. Final pricing after site visit.
      </div>
    </div>
  );
}
