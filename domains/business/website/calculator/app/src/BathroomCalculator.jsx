// ─── BathroomCalculator v2.1 ───────────────────────────────────────────────
// Two-column desktop, single-column mobile with sticky estimate bar.
// Warm cream/copper theme matching heartwoodcraft.me.

import { useState } from "react";
import { T, fonts } from "./theme";
import { STEPS, calculateRange, getLabel, getAttribution, fireEvent, fmt, WEBHOOK } from "./bathroomData";
import EstimateSidebar from "./EstimateSidebar";
import CalculatorLayout from "./CalculatorLayout";

// ─── Shared styles ─────────────────────────────────────────────────────────
const inputStyle = {
  width: "100%", padding: "12px 14px", borderRadius: 10,
  border: `1.5px solid ${T.border}`, background: T.white, fontSize: 14,
  fontFamily: "inherit", outline: "none", color: T.text,
  boxSizing: "border-box", transition: "border-color 0.15s",
};

const btnPrimary = {
  width: "100%", padding: "14px 0", borderRadius: 10, cursor: "pointer",
  border: "none", background: T.copper, color: T.white,
  fontSize: 15, fontWeight: 600, fontFamily: "inherit", transition: "opacity 0.15s",
};

// ─── Image Card ────────────────────────────────────────────────────────────
function ImageCard({ option, selected, onClick }) {
  const [imgError, setImgError] = useState(false);
  return (
    <button onClick={onClick} style={{
      flex: "1 1 calc(50% - 6px)", minWidth: 160, borderRadius: 12, cursor: "pointer",
      textAlign: "left", border: selected ? `2px solid ${T.copper}` : `1.5px solid ${T.border}`,
      background: selected ? T.copperLight : T.white, transition: "all 0.15s ease",
      fontFamily: "inherit", overflow: "hidden", padding: 0, boxShadow: T.cardShadow,
    }}
      onMouseEnter={(e) => { if (!selected) { e.currentTarget.style.borderColor = T.copperMid; e.currentTarget.style.boxShadow = T.cardShadowHover; } }}
      onMouseLeave={(e) => { if (!selected) { e.currentTarget.style.borderColor = T.border; e.currentTarget.style.boxShadow = T.cardShadow; } }}
    >
      {option.image && !imgError ? (
        <div style={{ width: "100%", height: 140, overflow: "hidden", borderBottom: `1px solid ${selected ? T.copperBorder : T.border}` }}>
          <img src={option.image} alt={option.label} onError={() => setImgError(true)} style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }} />
        </div>
      ) : null}
      <div style={{ padding: "12px 14px" }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: T.heading, marginBottom: 2 }}>{option.label}</div>
        <div style={{ fontSize: 12, color: T.textMuted, lineHeight: 1.4 }}>{option.desc}</div>
      </div>
    </button>
  );
}

// ─── Compact Card ──────────────────────────────────────────────────────────
function CompactCard({ option, selected, onClick }) {
  return (
    <button onClick={onClick} style={{
      padding: "14px 16px", borderRadius: 10, cursor: "pointer", textAlign: "left",
      border: selected ? `2px solid ${T.copper}` : `1.5px solid ${T.border}`,
      background: selected ? T.copperLight : T.white, transition: "all 0.15s ease",
      fontFamily: "inherit", display: "flex", alignItems: "center", gap: 14, width: "100%", boxShadow: T.cardShadow,
    }}
      onMouseEnter={(e) => { if (!selected) { e.currentTarget.style.borderColor = T.copperMid; e.currentTarget.style.boxShadow = T.cardShadowHover; } }}
      onMouseLeave={(e) => { if (!selected) { e.currentTarget.style.borderColor = T.border; e.currentTarget.style.boxShadow = T.cardShadow; } }}
    >
      <div style={{ width: 38, height: 38, borderRadius: 8, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, fontSize: 13, fontWeight: 700, color: T.copper, background: T.copperLight, border: `1px solid ${T.copperBorder}` }}>
        {option.icon}
      </div>
      <div>
        <div style={{ fontSize: 14, fontWeight: 600, color: T.heading }}>{option.label}</div>
        <div style={{ fontSize: 12, color: T.textMuted, lineHeight: 1.3 }}>{option.desc}</div>
      </div>
    </button>
  );
}

// ─── CheckboxItem ──────────────────────────────────────────────────────────
function CheckboxItem({ option, checked, onClick }) {
  return (
    <button onClick={onClick} style={{
      padding: "12px 14px", borderRadius: 8, cursor: "pointer", textAlign: "left",
      border: checked ? `2px solid ${T.copper}` : `1.5px solid ${T.border}`,
      background: checked ? T.copperLight : T.white, transition: "all 0.15s ease",
      fontFamily: "inherit", display: "flex", alignItems: "center", gap: 10, width: "100%",
    }}>
      <div style={{ width: 20, height: 20, borderRadius: 4, flexShrink: 0, border: checked ? `2px solid ${T.copper}` : `2px solid #d1d5db`, background: checked ? T.copper : "transparent", display: "flex", alignItems: "center", justifyContent: "center", color: T.white, fontSize: 12, fontWeight: 700, transition: "all 0.15s" }}>
        {checked && "✓"}
      </div>
      <span style={{ fontSize: 14, fontWeight: 500, color: T.text }}>{option.label}</span>
      <span style={{ fontSize: 12, color: T.textMuted, marginLeft: "auto", flexShrink: 0 }}>+${option.add.toLocaleString()}</span>
    </button>
  );
}

// ─── WhyToggle ─────────────────────────────────────────────────────────────
function WhyToggle({ text }) {
  const [open, setOpen] = useState(false);
  return (
    <div style={{ marginBottom: 16 }}>
      <button onClick={() => setOpen(!open)} style={{ background: "none", border: "none", cursor: "pointer", padding: 0, fontSize: 12, fontWeight: 600, color: T.copper, fontFamily: "inherit", display: "flex", alignItems: "center", gap: 5 }}>
        <span style={{ display: "inline-flex", alignItems: "center", justifyContent: "center", width: 18, height: 18, borderRadius: "50%", border: `1.5px solid ${T.copper}`, fontSize: 11, fontWeight: 700, color: T.copper, lineHeight: 1 }}>?</span>
        {open ? "Got it" : "Why do we ask this?"}
      </button>
      {open && (
        <div style={{ marginTop: 8, padding: "12px 14px", borderRadius: 8, background: T.copperLight, fontSize: 13, color: T.text, lineHeight: 1.6, borderLeft: `3px solid ${T.copper}` }}>
          {text}
        </div>
      )}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN COMPONENT
// ═══════════════════════════════════════════════════════════════════════════
export default function BathroomCalculator() {
  const [step, setStep] = useState(0);
  const [state, setState] = useState({});
  const [contact, setContact] = useState({ name: "", email: "", phone: "", notes: "", preferred_date: "", preferred_time: "" });
  const [phase, setPhase] = useState("quiz");
  const [fading, setFading] = useState(false);
  const [reportUrl, setReportUrl] = useState(null);
  const [submitting, setSubmitting] = useState(false);

  const cur = STEPS[step];
  const [lo, hi] = calculateRange(state);
  const hasContact = contact.name.trim() && contact.phone.trim() && contact.email.trim();

  const fade = (cb) => { setFading(true); setTimeout(() => { cb(); setTimeout(() => setFading(false), 30); }, 200); };
  const goNext = () => fade(() => { const n = step + 1; setStep(n); if (n >= STEPS.length) setPhase("results"); fireEvent("calculator_step", { step_number: step + 1, step_id: cur?.id }); });
  const goBack = () => { if (step > 0) fade(() => setStep((s) => s - 1)); };
  const pick = (id, v) => { setState((p) => ({ ...p, [id]: v })); setTimeout(goNext, 200); };
  const toggle = (v) => setState((p) => { const f = p.features || []; return { ...p, features: f.includes(v) ? f.filter((x) => x !== v) : [...f, v] }; });
  const reset = () => fade(() => { setStep(0); setState({}); setContact({ name: "", email: "", phone: "", notes: "", preferred_date: "", preferred_time: "" }); setPhase("quiz"); setReportUrl(null); });

  const submitLead = async () => {
    if (!hasContact) return;
    setSubmitting(true);
    fireEvent("calculator_lead_full", { estimate_low: lo, estimate_high: hi });
    const payload = { action: "calculator_lead_full", contact, projectState: state, estimate: { low: lo, high: hi }, timestamp: new Date().toISOString(), source: "website_calculator", calculator: "bathroom", source_page: window.location.pathname, ...getAttribution() };
    try { const res = await fetch(WEBHOOK, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) }); const data = await res.json(); setReportUrl(data.reportUrl || null); } catch { setReportUrl(null); }
    setSubmitting(false);
    fade(() => setPhase("submitted"));
  };

  const progress = Math.min((step / STEPS.length) * 100, 100);

  return (
    <CalculatorLayout sidebar={<EstimateSidebar state={state} step={step} />} lo={lo} hi={hi} step={step} totalSteps={STEPS.length} fmt={fmt} phase={phase}>
      {/* Progress bar */}
      {phase === "quiz" && (
        <div style={{ height: 3, background: T.border, borderRadius: 2, margin: "0 0 2rem", overflow: "hidden" }}>
          <div style={{ height: "100%", background: T.copper, borderRadius: 2, width: `${progress}%`, transition: "width 0.4s ease" }} />
        </div>
      )}

      <div style={{ opacity: fading ? 0 : 1, transform: fading ? "translateY(6px)" : "translateY(0)", transition: "all 0.2s ease" }}>
        {/* QUIZ */}
        {phase === "quiz" && cur && (
          <div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 6 }}>
              <div style={{ fontSize: 11, fontWeight: 600, color: T.textLight, letterSpacing: "0.08em", textTransform: "uppercase" }}>Step {step + 1} of {STEPS.length}</div>
              {step > 0 && <button onClick={reset} style={{ background: "none", border: "none", cursor: "pointer", fontSize: 12, fontWeight: 500, color: T.textLight, fontFamily: "inherit" }}>Start over</button>}
            </div>
            <h2 style={{ fontFamily: fonts.serif, fontSize: 24, fontWeight: 700, color: T.heading, margin: "0 0 6px", lineHeight: 1.3 }}>{cur.question}</h2>
            <p style={{ fontSize: 14, color: T.textMuted, margin: "0 0 12px", lineHeight: 1.5 }}>{cur.subtitle}</p>
            {cur.why && <WhyToggle text={cur.why} />}

            {cur.type === "image-cards" && (
              <div style={{ display: "flex", flexWrap: "wrap", gap: 12 }}>
                {cur.options.map((o) => <ImageCard key={o.value} option={o} selected={state[cur.id] === o.value} onClick={() => pick(cur.id, o.value)} />)}
              </div>
            )}
            {cur.type === "cards" && (
              <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                {cur.options.map((o) => <CompactCard key={o.value} option={o} selected={state[cur.id] === o.value} onClick={() => pick(cur.id, o.value)} />)}
              </div>
            )}
            {cur.type === "multi" && (
              <div>
                <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                  {cur.options.map((o) => <CheckboxItem key={o.value} option={o} checked={(state.features || []).includes(o.value)} onClick={() => toggle(o.value)} />)}
                </div>
                <button onClick={goNext} style={{ ...btnPrimary, marginTop: 16 }}>
                  {(state.features || []).length === 0 ? "None of these — continue" : `Continue with ${(state.features || []).length} selected`}
                </button>
              </div>
            )}
            {step > 0 && cur.type !== "multi" && (
              <button onClick={goBack} style={{ marginTop: 16, padding: "8px 0", background: "none", border: "none", cursor: "pointer", fontSize: 13, color: T.textLight, fontFamily: "inherit", fontWeight: 500 }}>← Back</button>
            )}
          </div>
        )}

        {/* RESULTS */}
        {phase === "results" && (
          <div>
            <div style={{ textAlign: "center", marginBottom: 24 }}>
              <div style={{ fontSize: 13, color: T.textMuted, marginBottom: 8, fontWeight: 500 }}>Your bathroom remodel estimate</div>
              <div style={{ fontFamily: fonts.serif, fontSize: 44, fontWeight: 700, color: T.heading, lineHeight: 1 }}>{fmt(lo)} – {fmt(hi)}</div>
              <div style={{ fontSize: 12, color: T.textLight, marginTop: 10, maxWidth: 440, margin: "10px auto 0", lineHeight: 1.5 }}>
                Based on real Heartwood Craft projects in Bozeman — not national averages.
              </div>
            </div>

            <div style={{ background: T.surfaceBg, border: `1px solid ${T.border}`, borderRadius: 12, padding: "20px 24px", marginBottom: 24 }}>
              <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 12, paddingBottom: 10, borderBottom: `1px solid ${T.border}` }}>
                <div style={{ fontFamily: fonts.serif, fontSize: 14, fontWeight: 600, color: T.copper }}>Heartwood Craft</div>
                <div style={{ fontSize: 11, color: T.textLight }}>{new Date().toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })}</div>
              </div>
              {[["Project", "project_type"], ["Size", "bathroom_size"], ["Layout", "shower_tub"], ["Tile", "tile_level"], ["Fixtures", "fixtures"], ["Timeline", "timeline"]].map(([label, id]) => (
                <div key={id} style={{ display: "flex", justifyContent: "space-between", padding: "7px 0", fontSize: 13, borderBottom: `1px solid ${T.border}` }}>
                  <span style={{ color: T.textMuted }}>{label}</span>
                  <span style={{ color: T.text, fontWeight: 500 }}>{getLabel(id, state[id])}</span>
                </div>
              ))}
              {state.features && state.features.length > 0 && (
                <div style={{ display: "flex", justifyContent: "space-between", padding: "7px 0", fontSize: 13 }}>
                  <span style={{ color: T.textMuted }}>Extras</span>
                  <span style={{ color: T.text, fontWeight: 500 }}>{state.features.map((f) => getLabel("features", f)).join(", ")}</span>
                </div>
              )}
              <div style={{ textAlign: "center", padding: "16px 0 0" }}>
                <div style={{ fontSize: 12, color: T.textMuted, marginBottom: 4 }}>Estimated range</div>
                <div style={{ fontFamily: fonts.serif, fontSize: 28, fontWeight: 700, color: T.copper }}>{fmt(lo)} – {fmt(hi)}</div>
              </div>
            </div>

            <div style={{ background: T.copperLight, border: `1px solid ${T.copperMid}`, borderRadius: 12, padding: 24 }}>
              <div style={{ fontSize: 17, fontWeight: 700, color: T.heading, marginBottom: 4 }}>Get your project summary</div>
              <div style={{ fontSize: 13, color: T.textMuted, marginBottom: 18, lineHeight: 1.6 }}>A detailed breakdown of your selections, what drives the cost, and what to expect next. Eric will be in touch to answer any questions.</div>
              <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
                <input type="text" placeholder="Your name" value={contact.name} onChange={(e) => setContact((c) => ({ ...c, name: e.target.value }))} style={inputStyle} onFocus={(e) => (e.target.style.borderColor = T.copper)} onBlur={(e) => (e.target.style.borderColor = T.border)} />
                <input type="tel" placeholder="Phone number" value={contact.phone} onChange={(e) => setContact((c) => ({ ...c, phone: e.target.value }))} style={inputStyle} onFocus={(e) => (e.target.style.borderColor = T.copper)} onBlur={(e) => (e.target.style.borderColor = T.border)} />
                <input type="email" placeholder="Email address" value={contact.email} onChange={(e) => setContact((c) => ({ ...c, email: e.target.value }))} style={inputStyle} onFocus={(e) => (e.target.style.borderColor = T.copper)} onBlur={(e) => (e.target.style.borderColor = T.border)} />
                <div>
                  <div style={{ fontSize: 13, fontWeight: 600, color: T.text, marginBottom: 8 }}>Preferred call time (optional)</div>
                  <div style={{ display: "flex", gap: 8 }}>
                    <input type="date" value={contact.preferred_date || ""} onChange={(e) => setContact((c) => ({ ...c, preferred_date: e.target.value }))} min={new Date().toISOString().split("T")[0]} style={{ ...inputStyle, flex: 1 }} />
                    <select value={contact.preferred_time || ""} onChange={(e) => setContact((c) => ({ ...c, preferred_time: e.target.value }))} style={{ ...inputStyle, flex: 1 }}>
                      <option value="">Time...</option>
                      <option value="morning">Morning (9–12)</option>
                      <option value="afternoon">Afternoon (12–5)</option>
                      <option value="evening">Evening (5–7)</option>
                    </select>
                  </div>
                </div>
                <button onClick={submitLead} disabled={!hasContact || submitting} style={{ ...btnPrimary, background: hasContact && !submitting ? T.charcoal : "#d1d5db", cursor: hasContact && !submitting ? "pointer" : "not-allowed" }}>
                  {submitting ? "Sending..." : "Send me the project summary"}
                </button>
              </div>
            </div>
            <button onClick={reset} style={{ display: "block", margin: "20px auto 0", background: "none", border: "none", cursor: "pointer", fontSize: 12, color: T.textLight, fontFamily: "inherit" }}>← Start over with different options</button>
          </div>
        )}

        {/* SUBMITTED */}
        {phase === "submitted" && (
          <div style={{ textAlign: "center", padding: "32px 0" }}>
            <div style={{ width: 56, height: 56, borderRadius: "50%", background: T.successBg, display: "flex", alignItems: "center", justifyContent: "center", margin: "0 auto 16px", fontSize: 24, color: T.success }}>✓</div>
            <h3 style={{ fontFamily: fonts.serif, fontSize: 24, fontWeight: 700, color: T.heading, margin: "0 0 8px" }}>You're all set, {contact.name.split(" ")[0]}</h3>
            <p style={{ fontSize: 14, color: T.textMuted, maxWidth: 400, margin: "0 auto", lineHeight: 1.6 }}>
              Your project summary is on its way to <strong>{contact.email}</strong>. Your ballpark of{" "}
              <strong style={{ color: T.copper }}>{fmt(lo)}–{fmt(hi)}</strong> is based on real Bozeman project costs — Eric will be in touch to discuss your project.
            </p>
            <div style={{ margin: "24px auto 0", padding: "16px 20px", borderRadius: 12, background: T.copperLight, display: "inline-block", textAlign: "left" }}>
              <div style={{ fontSize: 12, fontWeight: 700, color: T.copper, marginBottom: 8 }}>What happens next</div>
              <div style={{ fontSize: 13, color: T.text, lineHeight: 1.8 }}>1. Project summary lands in your inbox<br />2. Eric calls to discuss your project<br />3. Site visit — scope, conditions, measurements<br />4. Detailed estimate</div>
            </div>
            {reportUrl && (
              <a href={reportUrl} target="_blank" rel="noopener noreferrer" style={{ display: "inline-flex", alignItems: "center", gap: 8, padding: "12px 24px", borderRadius: 10, marginTop: 20, background: T.copper, color: T.white, fontSize: 14, fontWeight: 600, textDecoration: "none" }}>
                View your project summary →
              </a>
            )}
          </div>
        )}
      </div>
    </CalculatorLayout>
  );
}
