// ─── CalculatorRuntime v1 ──────────────────────────────────────────────────
// Single data-driven calculator shell. Replaces Bathroom/DeckCalculator.jsx
// (which were 90% duplicated). Per-calc copy, results-table fields, sidebar
// step order — all read from the JSON config now lives in the calc
// data file (calculator-<kind>.json).
//
// The runtime is unchanged from the previous per-calc components:
// 4 phases (quiz / gate / results / submitted), 3 input types
// (image-cards / cards / multi), gate→appointment funnel, dataLayer
// analytics fired on the same hooks the GA tagging already expects.

import { useState } from "react";
import { T, fonts } from "./theme";
import { buildSteps, makeCalculator, makeHelpers } from "./calcData";
import CalculatorLayout from "./CalculatorLayout";

// ─── Shared styles ─────────────────────────────────────────────────────────
const inputStyle = {
  width: "100%", padding: "14px 16px", borderRadius: 10,
  border: `1.5px solid ${T.border}`, background: T.white, fontSize: 16,
  fontFamily: "inherit", outline: "none", color: T.text,
  boxSizing: "border-box", transition: "border-color 0.15s",
};

const btnPrimary = {
  width: "100%", padding: "16px 0", borderRadius: 10, cursor: "pointer",
  border: "none", background: T.copper, color: T.white,
  fontSize: 17, fontWeight: 600, fontFamily: "inherit", transition: "opacity 0.15s",
};

const blurStyle = {
  filter: "blur(8px)",
  userSelect: "none",
  WebkitUserSelect: "none",
  pointerEvents: "none",
};

// ─── Image Card v2 ────────────────────────────────────────────────────────
function ImageCard({ option, selected, onClick }) {
  const [imgError, setImgError] = useState(false);
  const isSvg = typeof option.image === "string" && option.image.toLowerCase().endsWith(".svg");

  const mediaContainerStyle = {
    width: "100%",
    height: 180,
    overflow: "hidden",
    borderBottom: `1px solid ${selected ? T.copperBorder : T.border}`,
    background: isSvg ? T.surfaceBg : "transparent",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
  };

  const imgStyle = isSvg
    ? { width: "82%", height: "82%", objectFit: "contain", display: "block" }
    : { width: "100%", height: "100%", objectFit: "cover", display: "block" };

  return (
    <button
      onClick={onClick}
      style={{
        flex: "1 1 calc(50% - 6px)",
        minWidth: 160,
        borderRadius: 12,
        cursor: "pointer",
        textAlign: "left",
        border: selected ? `2px solid ${T.copper}` : `1.5px solid ${T.border}`,
        background: selected ? T.copperLight : T.white,
        transition: "all 0.15s ease",
        fontFamily: "inherit",
        overflow: "hidden",
        padding: 0,
        boxShadow: T.cardShadow,
      }}
      onMouseEnter={(e) => {
        if (!selected) {
          e.currentTarget.style.borderColor = T.copperMid;
          e.currentTarget.style.boxShadow = T.cardShadowHover;
        }
      }}
      onMouseLeave={(e) => {
        if (!selected) {
          e.currentTarget.style.borderColor = T.border;
          e.currentTarget.style.boxShadow = T.cardShadow;
        }
      }}
    >
      {option.image && !imgError ? (
        <div style={mediaContainerStyle}>
          <img
            src={option.image}
            alt={option.label}
            onError={() => setImgError(true)}
            style={imgStyle}
          />
        </div>
      ) : (
        <div
          style={{
            ...mediaContainerStyle,
            background: T.surfaceBg,
            color: T.textLight,
            fontSize: 11,
            fontWeight: 600,
            letterSpacing: "0.05em",
            textTransform: "uppercase",
          }}
        >
          {option.icon || ""}
        </div>
      )}
      <div style={{ padding: "14px 16px" }}>
        <div style={{ fontSize: 16, fontWeight: 600, color: T.heading, marginBottom: 4 }}>
          {option.label}
        </div>
        <div style={{ fontSize: 14, color: T.textMuted, lineHeight: 1.5 }}>
          {option.desc}
        </div>
      </div>
    </button>
  );
}

// ─── Compact Card ──────────────────────────────────────────────────────────
function CompactCard({ option, selected, onClick }) {
  return (
    <button onClick={onClick} style={{
      padding: "16px 20px", borderRadius: 10, cursor: "pointer", textAlign: "left",
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
        <div style={{ fontSize: 16, fontWeight: 600, color: T.heading }}>{option.label}</div>
        <div style={{ fontSize: 14, color: T.textMuted, lineHeight: 1.4 }}>{option.desc}</div>
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
      <span style={{ fontSize: 16, fontWeight: 500, color: T.text }}>{option.label}</span>
    </button>
  );
}

// ─── WhyToggle ─────────────────────────────────────────────────────────────
function WhyToggle({ text }) {
  const [open, setOpen] = useState(false);
  return (
    <div style={{ marginBottom: 16 }}>
      <button onClick={() => setOpen(!open)} style={{ background: "none", border: "none", cursor: "pointer", padding: 0, fontSize: 14, fontWeight: 600, color: T.copper, fontFamily: "inherit", display: "flex", alignItems: "center", gap: 5 }}>
        <span style={{ display: "inline-flex", alignItems: "center", justifyContent: "center", width: 18, height: 18, borderRadius: "50%", border: `1.5px solid ${T.copper}`, fontSize: 11, fontWeight: 700, color: T.copper, lineHeight: 1 }}>?</span>
        {open ? "Got it" : "Why do we ask this?"}
      </button>
      {open && (
        <div style={{ marginTop: 8, padding: "12px 14px", borderRadius: 8, background: T.copperLight, fontSize: 15, color: T.text, lineHeight: 1.6, borderLeft: `3px solid ${T.copper}` }}>
          {text}
        </div>
      )}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN COMPONENT
// ═══════════════════════════════════════════════════════════════════════════
export default function CalculatorRuntime({ data, sidebar: SidebarComponent }) {
  // Derived once at module-load equivalent — the data prop is stable across renders.
  const STEPS = buildSteps(data);
  const calculateRange = makeCalculator(data);
  const { getLabel, getAttribution, fireEvent, fmt } = makeHelpers(data);
  const calculatorId = data.calculator;
  // Late-binding endpoints — prefer NixOS-injected env (via hwc.business.
  // website.leadsWebhookUrl) over the JSON fallback. The fallback only
  // covers `npm run dev` outside the NixOS service path.
  const webhookUrl = import.meta.env.VITE_LEADS_WEBHOOK_URL || data.webhook;
  const webhookApptUrl = import.meta.env.VITE_LEADS_WEBHOOK_APPT_URL || data.webhookAppointment;
  const sizeStateKey = data.sidebar?.stepOrder?.[1] ?? "size";
  const summaryFields = data.results?.summaryFields ?? [];
  const gateEstimateLabel = data.copy?.gateEstimateLabel ?? "Your estimate";
  const resultsEstimateLabel = data.copy?.resultsEstimateLabel ?? "Your estimate";
  const footerCopy = data.copy?.footerCopy ?? "Based on real Heartwood Craft projects in Bozeman — not national averages.";

  const [step, setStep] = useState(0);
  const [state, setState] = useState({});
  const [contact, setContact] = useState({ name: "", email: "", phone: "", notes: "", preferred_date: "", preferred_time: "" });
  const [phase, setPhase] = useState("quiz");
  const [fading, setFading] = useState(false);
  const [reportUrl, setReportUrl] = useState(null);
  const [reportId, setReportId] = useState(null);
  const [submitting, setSubmitting] = useState(false);

  const cur = STEPS[step];
  const [lo, hi] = calculateRange(state);
  const hasGateInfo = contact.name.trim() && contact.email.trim();
  const hasPhone = contact.phone.trim();

  const fade = (cb) => { setFading(true); setTimeout(() => { cb(); setTimeout(() => setFading(false), 30); }, 200); };
  const goNext = () => fade(() => {
    const n = step + 1;
    setStep(n);
    fireEvent("calculator_step", { step_number: step + 1, step_id: cur?.id });
    if (n >= STEPS.length) {
      setPhase("gate");
      fireEvent("calculator_complete", {
        estimate_low: lo,
        estimate_high: hi,
        project_type: state.project_type,
        [sizeStateKey]: state[sizeStateKey],
      });
      fireEvent("gate_viewed", {
        estimate_low: lo,
        estimate_high: hi,
        project_type: state.project_type,
        [sizeStateKey]: state[sizeStateKey],
      });
    }
  });
  const goBack = () => { if (step > 0) fade(() => setStep((s) => s - 1)); };
  const pick = (id, v) => {
    if (step === 0 && Object.keys(state).length === 0) {
      fireEvent("calculator_started", { calculator_type: calculatorId });
    }
    setState((p) => ({ ...p, [id]: v }));
    setTimeout(goNext, 200);
  };
  const toggle = (v) => setState((p) => { const f = p.features || []; return { ...p, features: f.includes(v) ? f.filter((x) => x !== v) : [...f, v] }; });
  const reset = () => fade(() => { setStep(0); setState({}); setContact({ name: "", email: "", phone: "", notes: "", preferred_date: "", preferred_time: "" }); setPhase("quiz"); setReportUrl(null); setReportId(null); });

  const unlockGate = async () => {
    if (!hasGateInfo) return;
    fireEvent("gate_email_submitted", {
      estimate_low: lo,
      estimate_high: hi,
      project_type: state.project_type,
      [sizeStateKey]: state[sizeStateKey],
    });
    const payload = {
      action: "calculator_gate_submit",
      contact: { name: contact.name, email: contact.email },
      projectState: state,
      estimate: { low: lo, high: hi },
      timestamp: new Date().toISOString(),
      source: "website_calculator",
      calculator: calculatorId,
      source_page: window.location.pathname,
      ...getAttribution()
    };
    try {
      const res = await fetch(webhookUrl, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) });
      const respData = await res.json();
      setReportUrl(respData.reportUrl || null);
      setReportId(respData.reportId || null);
    } catch {
      setReportUrl(null);
    }
    fade(() => setPhase("results"));
  };

  const submitLead = async () => {
    if (!hasPhone) return;
    setSubmitting(true);
    fireEvent("calculator_appointment_request", {
      calculator_type: calculatorId,
      estimate_low: lo,
      estimate_high: hi,
    });
    const payload = {
      action: "calculator_appointment_request",
      report_id: reportId,
      contact: { name: contact.name, email: contact.email, phone: contact.phone, preferred_date: contact.preferred_date, preferred_time: contact.preferred_time },
      calculator: calculatorId,
      estimate: { low: lo, high: hi },
      timestamp: new Date().toISOString(),
      source: "website_calculator",
      source_page: window.location.pathname,
      ...getAttribution()
    };
    // Cross-origin fire-and-forget: no-cors + text/plain is a "simple" request
    // (no CORS preflight), so it reaches crm.iheartwoodcraft.com/hooks/appointment
    // even though we can't read the opaque response.
    try { await fetch(webhookApptUrl, { method: "POST", mode: "no-cors", headers: { "Content-Type": "text/plain" }, body: JSON.stringify(payload) }); } catch {}
    setSubmitting(false);
    fade(() => setPhase("submitted"));
  };

  const progress = Math.min((step / STEPS.length) * 100, 100);

  return (
    <CalculatorLayout sidebar={<SidebarComponent data={data} state={state} step={step} phase={phase} />} lo={lo} hi={hi} step={step} totalSteps={STEPS.length} fmt={fmt} phase={phase} title={data.title}>
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
              <div style={{ fontSize: 13, fontWeight: 600, color: T.textLight, letterSpacing: "0.08em", textTransform: "uppercase" }}>Step {step + 1} of {STEPS.length}</div>
              {step > 0 && <button onClick={reset} style={{ background: "none", border: "none", cursor: "pointer", fontSize: 12, fontWeight: 500, color: T.textLight, fontFamily: "inherit" }}>Start over</button>}
            </div>
            <h2 style={{ fontFamily: fonts.serif, fontSize: 28, fontWeight: 700, color: T.heading, margin: "0 0 6px", lineHeight: 1.3 }}>{cur.question}</h2>
            <p style={{ fontSize: 16, color: T.textMuted, margin: "0 0 12px", lineHeight: 1.5 }}>{cur.subtitle}</p>
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

        {/* GATE */}
        {phase === "gate" && (
          <div style={{ maxWidth: 480, margin: "0 auto" }}>
            <div style={{ textAlign: "center", marginBottom: 32 }}>
              <div style={{ fontSize: 13, fontWeight: 600, color: T.textMuted, letterSpacing: "0.06em", textTransform: "uppercase", marginBottom: 12 }}>{gateEstimateLabel}</div>
              <div style={blurStyle}>
                <div style={{ fontFamily: fonts.serif, fontSize: 52, fontWeight: 700, color: T.heading, lineHeight: 1 }}>{fmt(lo)} – {fmt(hi)}</div>
              </div>
              <div style={{ fontSize: 13, color: T.textLight, marginTop: 12, lineHeight: 1.5 }}>
                {footerCopy}
              </div>
            </div>

            <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
              <input type="text" placeholder="Your name" value={contact.name} onChange={(e) => setContact((c) => ({ ...c, name: e.target.value }))} style={inputStyle} onFocus={(e) => (e.target.style.borderColor = T.copper)} onBlur={(e) => (e.target.style.borderColor = T.border)} />
              <input type="email" placeholder="Email address" value={contact.email} onChange={(e) => setContact((c) => ({ ...c, email: e.target.value }))} style={inputStyle} onFocus={(e) => (e.target.style.borderColor = T.copper)} onBlur={(e) => (e.target.style.borderColor = T.border)} onKeyDown={(e) => e.key === "Enter" && unlockGate()} />
              <button onClick={unlockGate} disabled={!hasGateInfo} style={{ ...btnPrimary, background: hasGateInfo ? T.charcoal : "#d1d5db", cursor: hasGateInfo ? "pointer" : "not-allowed" }}>
                Show my estimate
              </button>
              <div style={{ fontSize: 11, color: T.textLight, textAlign: "center", marginTop: 2 }}>We'll send your project summary to this email. No spam.</div>
            </div>
            <button onClick={reset} style={{ display: "block", margin: "24px auto 0", background: "none", border: "none", cursor: "pointer", fontSize: 12, color: T.textLight, fontFamily: "inherit" }}>← Start over with different options</button>
          </div>
        )}

        {/* RESULTS */}
        {phase === "results" && (
          <div>
            <div style={{ textAlign: "center", marginBottom: 24 }}>
              <div style={{ fontSize: 13, color: T.textMuted, marginBottom: 8, fontWeight: 500 }}>{resultsEstimateLabel}</div>
              <div style={{ fontFamily: fonts.serif, fontSize: 44, fontWeight: 700, color: T.heading, lineHeight: 1 }}>{fmt(lo)} – {fmt(hi)}</div>
              <div style={{ fontSize: 12, color: T.textLight, marginTop: 10, maxWidth: 440, margin: "10px auto 0", lineHeight: 1.5 }}>
                {footerCopy}
              </div>
            </div>

            <div style={{ background: T.surfaceBg, border: `1px solid ${T.border}`, borderRadius: 12, padding: "20px 24px", marginBottom: 24 }}>
              <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 12, paddingBottom: 10, borderBottom: `1px solid ${T.border}` }}>
                <div style={{ fontFamily: fonts.serif, fontSize: 14, fontWeight: 600, color: T.copper }}>Heartwood Craft</div>
                <div style={{ fontSize: 11, color: T.textLight }}>{new Date().toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })}</div>
              </div>
              {summaryFields.map(({ label, id }) => (
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

            <div style={{ fontSize: 12, color: T.textLight, textAlign: "center", marginBottom: 16 }}>
              Project summary sent to <strong>{contact.email}</strong>
            </div>

            <div style={{ background: T.copperLight, border: `1px solid ${T.copperMid}`, borderRadius: 12, padding: 24 }}>
              <div style={{ fontSize: 17, fontWeight: 700, color: T.heading, marginBottom: 4 }}>Schedule a call with Eric</div>
              <div style={{ fontSize: 13, color: T.textMuted, marginBottom: 18, lineHeight: 1.6 }}>Add your phone number and we'll send a calendar invite for your preferred time.</div>
              <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
                <input type="text" placeholder="Your name" value={contact.name} onChange={(e) => setContact((c) => ({ ...c, name: e.target.value }))} style={inputStyle} onFocus={(e) => (e.target.style.borderColor = T.copper)} onBlur={(e) => (e.target.style.borderColor = T.border)} />
                <input type="email" placeholder="Email address" value={contact.email} onChange={(e) => setContact((c) => ({ ...c, email: e.target.value }))} style={inputStyle} onFocus={(e) => (e.target.style.borderColor = T.copper)} onBlur={(e) => (e.target.style.borderColor = T.border)} />
                <input type="tel" placeholder="Phone number" value={contact.phone} onChange={(e) => setContact((c) => ({ ...c, phone: e.target.value }))} style={inputStyle} onFocus={(e) => (e.target.style.borderColor = T.copper)} onBlur={(e) => (e.target.style.borderColor = T.border)} />
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
                <button onClick={submitLead} disabled={!hasPhone || submitting} style={{ ...btnPrimary, background: hasPhone && !submitting ? T.charcoal : "#d1d5db", cursor: hasPhone && !submitting ? "pointer" : "not-allowed" }}>
                  {submitting ? "Sending..." : "Request a call"}
                </button>
              </div>
            </div>
            <button onClick={reset} style={{ display: "block", margin: "16px auto 0", background: "none", border: "none", cursor: "pointer", fontSize: 12, color: T.textLight, fontFamily: "inherit" }}>← Start over with different options</button>
          </div>
        )}

        {/* SUBMITTED */}
        {phase === "submitted" && (
          <div style={{ textAlign: "center", padding: "32px 0" }}>
            <div style={{ width: 56, height: 56, borderRadius: "50%", background: T.successBg, display: "flex", alignItems: "center", justifyContent: "center", margin: "0 auto 16px", fontSize: 24, color: T.success }}>✓</div>
            <h3 style={{ fontFamily: fonts.serif, fontSize: 24, fontWeight: 700, color: T.heading, margin: "0 0 8px" }}>Call request sent, {contact.name.split(" ")[0]}</h3>
            <p style={{ fontSize: 14, color: T.textMuted, maxWidth: 400, margin: "0 auto", lineHeight: 1.6 }}>
              {contact.preferred_date
                ? <>A calendar invite is on its way to <strong>{contact.email}</strong>. Eric will call <strong>{contact.phone}</strong> — check your inbox to confirm the time.</>
                : <>Request received. Eric will reach out at <strong>{contact.phone}</strong> to find a time that works.</>
              }
            </p>
            <div style={{ margin: "24px auto 0", padding: "16px 20px", borderRadius: 12, background: T.copperLight, display: "inline-block", textAlign: "left" }}>
              <div style={{ fontSize: 12, fontWeight: 700, color: T.copper, marginBottom: 8 }}>What happens next</div>
              <div style={{ fontSize: 13, color: T.text, lineHeight: 1.8 }}>1. Eric confirms your call time<br />2. Site visit — scope, conditions, measurements<br />3. Detailed estimate, walked through together</div>
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
