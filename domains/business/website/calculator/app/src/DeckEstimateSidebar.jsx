// ─── DeckEstimateSidebar ───────────────────────────────────────────────────
// Same layout as bathroom EstimateSidebar but reads from deck steps.

import { useState, useEffect, useRef } from "react";
import { T, fonts } from "./theme";
import { STEPS, getLabel, fmt, calculateRange } from "./deckData";

function AnimatedNumber({ value, duration = 600 }) {
  const [display, setDisplay] = useState(value);
  const rafRef = useRef(null);
  const prevRef = useRef(value);

  useEffect(() => {
    const from = prevRef.current;
    const to = value;
    prevRef.current = value;
    if (from === to) return;

    const start = performance.now();
    const tick = (now) => {
      const t = Math.min((now - start) / duration, 1);
      const ease = 1 - Math.pow(1 - t, 3);
      setDisplay(Math.round(from + (to - from) * ease));
      if (t < 1) rafRef.current = requestAnimationFrame(tick);
    };
    rafRef.current = requestAnimationFrame(tick);
    return () => rafRef.current && cancelAnimationFrame(rafRef.current);
  }, [value, duration]);

  return <>{display.toLocaleString()}</>;
}

export default function DeckEstimateSidebar({ state, step }) {
  const hasSelections = Object.keys(state).filter((k) => k !== "features" || (state.features && state.features.length > 0)).length > 0;
  const [lo, hi] = hasSelections ? calculateRange(state) : [0, 0];

  const selections = [];
  const stepOrder = ["project_type", "deck_size", "deck_height", "material", "railing", "features", "timeline"];
  const labelMap = {
    project_type: "Project",
    deck_size: "Size",
    deck_height: "Height",
    material: "Material",
    railing: "Railing",
    features: "Extras",
    timeline: "Timeline",
  };

  stepOrder.forEach((id) => {
    if (id === "features") {
      if (state.features && state.features.length > 0) {
        selections.push({
          label: "Extras",
          value: state.features.map((f) => getLabel("features", f)).join(", "),
        });
      }
    } else if (state[id]) {
      selections.push({
        label: labelMap[id],
        value: getLabel(id, state[id]),
      });
    }
  });

  return (
    <div
      style={{
        background: T.sidebarBg,
        borderRadius: 16,
        padding: "28px 24px",
        fontFamily: fonts.sans,
        color: T.textOnDark,
        position: "sticky",
        top: 24,
      }}
    >
      <div style={{ marginBottom: 20 }}>
        <div
          style={{
            fontSize: 11,
            fontWeight: 600,
            letterSpacing: "0.1em",
            textTransform: "uppercase",
            color: T.copper,
            marginBottom: 8,
          }}
        >
          Your estimate
        </div>
        {hasSelections && lo > 0 ? (
          <div
            style={{
              fontFamily: fonts.serif,
              fontSize: 32,
              fontWeight: 700,
              color: T.white,
              lineHeight: 1.1,
            }}
          >
            $<AnimatedNumber value={lo} /> – $<AnimatedNumber value={hi} />
          </div>
        ) : (
          <div style={{ fontSize: 15, color: T.textOnDarkMuted, lineHeight: 1.4 }}>
            Answer the questions to see your estimate build in real time.
          </div>
        )}
      </div>

      <div style={{ height: 1, background: "rgba(255,255,255,0.08)", margin: "0 0 16px" }} />

      {selections.length > 0 ? (
        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          {selections.map((s) => (
            <div key={s.label} style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
              <span style={{ fontSize: 12, color: T.textOnDarkMuted, fontWeight: 500 }}>{s.label}</span>
              <span style={{ fontSize: 13, color: T.textOnDark, fontWeight: 500, textAlign: "right", maxWidth: "60%" }}>{s.value}</span>
            </div>
          ))}
        </div>
      ) : (
        <div style={{ fontSize: 12, color: "rgba(255,255,255,0.25)" }}>
          Your selections will appear here as you go.
        </div>
      )}

      <div style={{ marginTop: 20, display: "flex", gap: 6, justifyContent: "center" }}>
        {STEPS.map((s, i) => (
          <div
            key={s.id}
            style={{
              width: 8,
              height: 8,
              borderRadius: "50%",
              background: i < step ? T.copper : i === step ? T.copperDark : "rgba(255,255,255,0.12)",
              transition: "background 0.3s ease",
            }}
          />
        ))}
      </div>

      <div
        style={{
          marginTop: 24,
          paddingTop: 16,
          borderTop: "1px solid rgba(255,255,255,0.08)",
          textAlign: "center",
          fontSize: 12,
          color: T.textOnDarkMuted,
          lineHeight: 1.5,
        }}
      >
        Prefer a quick call?
        <br />
        <a href="tel:4065515061" style={{ color: T.copper, textDecoration: "none", fontWeight: 600, fontSize: 14 }}>
          406-551-5061
        </a>
      </div>
    </div>
  );
}
