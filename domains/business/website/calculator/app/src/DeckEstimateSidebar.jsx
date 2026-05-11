// ─── DeckEstimateSidebar v3 ───────────────────────────────────────────────
// During quiz: contextual educational content matched to the current step.
// During gate: project summary (no dollars).
// During results/submitted: project summary with revealed estimate.

import { useState, useEffect, useRef } from "react";
import { T, fonts } from "./theme";
import { STEPS, getLabel, calculateRange } from "./deckData";
import { deckSidebarContent } from "./sidebarContent";

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

function SelectionsSummary({ state }) {
  const stepOrder = ["project_type", "deck_size", "deck_height", "material", "railing", "features", "timeline"];
  const labelMap = {
    project_type: "Project", deck_size: "Size", deck_height: "Height",
    material: "Material", railing: "Railing", features: "Extras", timeline: "Timeline",
  };

  const selections = [];
  stepOrder.forEach((id) => {
    if (id === "features") {
      if (state.features && state.features.length > 0) {
        selections.push({ label: "Extras", value: state.features.length + " selected" });
      }
    } else if (state[id]) {
      selections.push({ label: labelMap[id], value: getLabel(id, state[id]) });
    }
  });

  if (selections.length === 0) return (
    <div style={{ fontSize: 14, color: "rgba(255,255,255,0.25)" }}>
      Your selections will appear here as you go.
    </div>
  );

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      {selections.map((s) => (
        <div key={s.label} style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <span style={{ fontSize: 14, color: T.textOnDarkMuted, fontWeight: 500 }}>{s.label}</span>
          <span style={{ fontSize: 15, color: T.textOnDark, fontWeight: 500, textAlign: "right", maxWidth: "60%" }}>{s.value}</span>
        </div>
      ))}
    </div>
  );
}

function EducationalPanel({ stepId, fading }) {
  const content = deckSidebarContent[stepId];
  if (!content) return null;

  return (
    <div style={{
      opacity: fading ? 0 : 1,
      transform: fading ? "translateY(4px)" : "translateY(0)",
      transition: "all 0.25s ease",
    }}>
      <div style={{
        fontSize: 15, fontWeight: 700, color: T.copper,
        marginBottom: 16, fontFamily: fonts.serif,
      }}>
        {content.title}
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
        {content.tips.map((tip, i) => (
          <div key={i}>
            <div style={{ fontSize: 13, fontWeight: 600, color: T.textOnDark, marginBottom: 3 }}>
              {tip.heading}
            </div>
            <div style={{ fontSize: 13, color: T.textOnDarkMuted, lineHeight: 1.6 }}>
              {tip.text}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default function DeckEstimateSidebar({ state, step, phase }) {
  const hasSelections = Object.keys(state).filter((k) => k !== "features" || (state.features && state.features.length > 0)).length > 0;
  const [lo, hi] = hasSelections ? calculateRange(state) : [0, 0];
  const [contentFading, setContentFading] = useState(false);
  const prevStep = useRef(step);

  useEffect(() => {
    if (step !== prevStep.current) {
      setContentFading(true);
      const timer = setTimeout(() => {
        prevStep.current = step;
        setContentFading(false);
      }, 200);
      return () => clearTimeout(timer);
    }
  }, [step]);

  const currentStepId = STEPS[step]?.id;
  const isQuiz = phase === "quiz";
  const isRevealed = phase === "results" || phase === "submitted";

  return (
    <div style={{
      background: T.sidebarBg,
      borderRadius: 16,
      padding: "32px 28px",
      fontFamily: fonts.sans,
      color: T.textOnDark,
      position: "sticky",
      top: 24,
    }}>
      {/* Header */}
      <div style={{ marginBottom: 20 }}>
        <div style={{
          fontSize: 13, fontWeight: 600, letterSpacing: "0.1em",
          textTransform: "uppercase", color: T.copper, marginBottom: 8,
        }}>
          {isQuiz ? "Good to know" : "Your estimate"}
        </div>

        {isRevealed && lo > 0 ? (
          <div style={{
            fontFamily: fonts.serif, fontSize: 36, fontWeight: 700,
            color: T.white, lineHeight: 1.1,
          }}>
            $<AnimatedNumber value={lo} /> – $<AnimatedNumber value={hi} />
          </div>
        ) : !isQuiz ? (
          <div style={{ fontSize: 15, color: T.textOnDarkMuted, lineHeight: 1.4 }}>
            Complete all questions to see your range.
          </div>
        ) : null}
      </div>

      <div style={{ height: 1, background: "rgba(255,255,255,0.08)", margin: "0 0 20px" }} />

      {isQuiz
        ? <EducationalPanel stepId={currentStepId} fading={contentFading} />
        : <SelectionsSummary state={state} />
      }

      {/* Step progress dots */}
      <div style={{ marginTop: 24, display: "flex", gap: 6, justifyContent: "center" }}>
        {STEPS.map((s, i) => (
          <div key={s.id} style={{
            width: 8, height: 8, borderRadius: "50%",
            background: i < step ? T.copper : i === step ? T.copperDark : "rgba(255,255,255,0.12)",
            transition: "background 0.3s ease",
          }} />
        ))}
      </div>

      {/* Phone CTA */}
      <div style={{
        marginTop: 24, paddingTop: 16,
        borderTop: "1px solid rgba(255,255,255,0.08)",
        textAlign: "center", fontSize: 14, color: T.textOnDarkMuted, lineHeight: 1.5,
      }}>
        Prefer a quick call?<br />
        <a href="tel:4065515061" style={{
          color: T.copper, textDecoration: "none", fontWeight: 600, fontSize: 16,
        }}>
          406-551-5061
        </a>
      </div>
    </div>
  );
}
