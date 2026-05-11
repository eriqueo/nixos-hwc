// ─── CalculatorLayout v3 ──────────────────────────────────────────────────
// Full-page calculator experience. Larger type, more breathing room.
// Desktop: two-column grid (questions + sidebar). Mobile: single column.

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
  title,
}) {
  const isMobile = useIsMobile(768);

  return (
    <div
      style={{
        background: T.pageBg,
        fontFamily: fonts.sans,
        color: T.text,
        padding: isMobile ? "2rem 0" : "3rem 0",
        margin: isMobile ? "0 -1rem" : "0",
      }}
    >
      <link href={fontsUrl} rel="stylesheet" />

      {/* Page title — built into the calculator, not the host page */}
      {title && (
        <div
          style={{
            maxWidth: isMobile ? 640 : 1120,
            margin: "0 auto",
            padding: isMobile ? "0 1.25rem 1.5rem" : "0 2rem 2rem",
          }}
        >
          <h1
            style={{
              fontFamily: fonts.serif,
              fontSize: isMobile ? 28 : 40,
              fontWeight: 700,
              color: T.heading,
              margin: 0,
              lineHeight: 1.15,
            }}
          >
            {title}
          </h1>
        </div>
      )}

      <div
        style={{
          display: isMobile ? "block" : "grid",
          gridTemplateColumns: isMobile ? undefined : "1fr 360px",
          gap: isMobile ? 0 : 48,
          maxWidth: isMobile ? 640 : 1120,
          margin: "0 auto",
          padding: isMobile ? "0 1.25rem 5rem" : "0 2rem 3rem",
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
        <MobileEstimateBar lo={lo} hi={hi} step={step} totalSteps={totalSteps} fmt={fmt} phase={phase} />
      )}

      {/* Footer */}
      <div
        style={{
          maxWidth: isMobile ? 640 : 1120,
          margin: "0 auto",
          padding: "24px 2rem 0",
          borderTop: `1px solid ${T.border}`,
          textAlign: "center",
          fontSize: 13,
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
