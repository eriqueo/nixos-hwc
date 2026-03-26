import { useState } from "react";

const phases = [
  {
    id: "gather",
    label: "Phase 1 — Gather documents",
    badgeText: "Before you start",
    tasks: [
      {
        label: "Locate your EIN",
        note: "Check prior returns or IRS letter",
        fields: [{ key: "ein", label: "EIN", placeholder: "XX-XXXXXXX" }]
      },
      {
        label: "Collect all 1099-NEC forms received",
        note: "Anyone who paid you $600+ must send one; verify against JobTread income",
        tag: "federal form",
        fields: [
          { key: "count", label: "Number of 1099s received", placeholder: "e.g. 3" },
          { key: "total", label: "Total 1099 income", placeholder: "e.g. $82,000" },
        ]
      },
      {
        label: "Pull QuickBooks P&L report (full year)",
        note: "Reports → P&L → Jan 1 – Dec 31",
        tag: "QuickBooks",
        fields: [
          { key: "revenue", label: "Total revenue", placeholder: "e.g. $148,000" },
          { key: "cogs", label: "Cost of goods sold", placeholder: "e.g. $61,000" },
          { key: "expenses", label: "Total operating expenses", placeholder: "e.g. $22,000" },
          { key: "netprofit", label: "Net profit", placeholder: "e.g. $65,000" },
          { key: "location", label: "File saved to", placeholder: "e.g. Google Drive / Desktop" },
        ]
      },
      {
        label: "Pull QuickBooks Balance Sheet (year-end)",
        note: "Shows assets, liabilities, owner equity at Dec 31",
        tag: "QuickBooks",
        fields: [
          { key: "assets", label: "Total assets", placeholder: "e.g. $18,000" },
          { key: "liabilities", label: "Total liabilities", placeholder: "e.g. $4,000" },
          { key: "location", label: "File saved to", placeholder: "e.g. Google Drive / Desktop" },
        ]
      },
      {
        label: "Export Stripe payout report for the year",
        note: "Stripe Dashboard → Payouts → date range export",
        fields: [
          { key: "total", label: "Total Stripe payouts", placeholder: "e.g. $34,000" },
          { key: "fees", label: "Total Stripe fees", placeholder: "e.g. $980" },
        ]
      },
      {
        label: "Collect all business receipts and invoices",
        note: "Materials, subs, tools, supplies — match to QuickBooks categories",
        fields: [
          { key: "status", label: "Storage location", placeholder: "e.g. Dropbox/Receipts folder" },
          { key: "missing", label: "Any missing / gaps noted", placeholder: "e.g. Home Depot March receipts" },
        ]
      },
      {
        label: "Gather vehicle mileage log",
        note: "2024 standard rate: 67c/mile; or track actual expenses",
        fields: [
          { key: "miles", label: "Total business miles", placeholder: "e.g. 4,200" },
          { key: "method", label: "Deduction method", placeholder: "Standard mileage or Actual expenses" },
          { key: "deduction", label: "Estimated deduction", placeholder: "e.g. $2,814" },
        ]
      },
      {
        label: "Collect home office info (if applicable)",
        note: "Dedicated workspace sq ft vs total home sq ft",
        fields: [
          { key: "office_sqft", label: "Office sq ft", placeholder: "e.g. 120" },
          { key: "home_sqft", label: "Total home sq ft", placeholder: "e.g. 1,800" },
          { key: "pct", label: "Business use %", placeholder: "e.g. 6.7%" },
        ]
      },
      {
        label: "Locate any loan or financing statements",
        note: "Interest portion is deductible; need year-end statements",
        fields: [
          { key: "lender", label: "Lender(s)", placeholder: "e.g. Montana Bank, PayPal Working Capital" },
          { key: "interest", label: "Total interest paid", placeholder: "e.g. $1,240" },
        ]
      },
      {
        label: "Collect sub-contractor payment records",
        note: "Paid any subs $600+? You may owe them a 1099-NEC",
        fields: [
          { key: "subs", label: "Sub names + amounts paid", placeholder: "e.g. John Smith $4,200 / ABC Tile $8,500" },
          { key: "w9", label: "W-9s on file?", placeholder: "Yes / No / Partial" },
        ]
      },
    ]
  },
  {
    id: "reconcile",
    label: "Phase 2 — Reconcile & categorize",
    badgeText: "Books cleanup",
    tasks: [
      {
        label: "Reconcile all bank accounts in QuickBooks through Dec 31",
        note: "Every statement balance must match QB",
        fields: [
          { key: "accounts", label: "Accounts reconciled", placeholder: "e.g. Checking, Savings" },
          { key: "discrepancy", label: "Any discrepancies found", placeholder: "e.g. None / $42 difference resolved" },
        ]
      },
      {
        label: "Reconcile credit cards through Dec 31",
        fields: [
          { key: "cards", label: "Cards reconciled", placeholder: "e.g. Chase Ink, Personal Visa" },
        ]
      },
      {
        label: "Review uncategorized transactions",
        note: "Run QB report filtered to uncategorized and clean up",
        fields: [
          { key: "count", label: "Uncategorized transactions resolved", placeholder: "e.g. 12 of 12" },
        ]
      },
      {
        label: "Verify income matches 1099s + cash/check jobs",
        note: "Total QB income should equal or exceed sum of 1099s received",
        fields: [
          { key: "qb_income", label: "QB total income", placeholder: "e.g. $148,000" },
          { key: "total_1099", label: "Sum of all 1099s received", placeholder: "e.g. $82,000" },
          { key: "match", label: "Reconciled?", placeholder: "Yes / No — note any gap" },
        ]
      },
      {
        label: "Confirm material and sub costs coded to COGS vs expenses",
        fields: [
          { key: "cogs_total", label: "Total COGS in QB", placeholder: "e.g. $61,000" },
          { key: "notes", label: "Any reclassifications made", placeholder: "e.g. Moved $3k lumber to COGS" },
        ]
      },
      {
        label: "Flag large or unusual purchases",
        note: "Items over ~$2,500 may need to be capitalized, not expensed",
        fields: [
          { key: "items", label: "Items flagged for depreciation", placeholder: "e.g. Trailer $6,800" },
        ]
      },
    ]
  },
  {
    id: "forms",
    label: "Phase 3 — Identify your forms",
    badgeText: "What you'll file",
    tasks: [
      {
        label: "Schedule C — Profit or Loss from Business",
        note: "Reports all business income and deductions on your 1040",
        tag: "federal form",
        fields: [
          { key: "net", label: "Expected net profit (Line 31)", placeholder: "e.g. $65,000" },
        ]
      },
      {
        label: "Schedule SE — Self-Employment Tax",
        note: "15.3% on net SE income (92.35% of net profit)",
        tag: "federal form",
        fields: [
          { key: "se_tax", label: "Estimated SE tax owed", placeholder: "e.g. $9,183" },
        ]
      },
      {
        label: "Form 1040 — Federal personal return",
        note: "Due April 15 or Oct 15 with extension",
        tag: "federal form",
        fields: [
          { key: "agi", label: "Estimated AGI", placeholder: "e.g. $68,000" },
          { key: "total_tax", label: "Estimated total tax", placeholder: "e.g. $14,200" },
        ]
      },
      {
        label: "Montana Form 2 — Individual income tax return",
        note: "Due April 15 — starts from federal AGI",
        tag: "MT form",
        fields: [
          { key: "mt_tax", label: "Estimated MT tax owed", placeholder: "e.g. $3,400" },
        ]
      },
      {
        label: "Issue 1099-NEC to any sub paid $600+ (if applicable)",
        note: "Due to recipient Jan 31; filed with IRS by Jan 31",
        tag: "federal form",
        fields: [
          { key: "issued", label: "1099-NECs issued to", placeholder: "e.g. John Smith, ABC Tile" },
          { key: "filed", label: "Filed with IRS?", placeholder: "Yes / No / N/A" },
        ]
      },
      {
        label: "Confirm estimated tax payments made (Form 1040-ES)",
        note: "Quarterly payments reduce your balance due",
        tag: "federal form",
        fields: [
          { key: "q1", label: "Q1 payment (Apr)", placeholder: "e.g. $2,500" },
          { key: "q2", label: "Q2 payment (Jun)", placeholder: "e.g. $2,500" },
          { key: "q3", label: "Q3 payment (Sep)", placeholder: "e.g. $2,500" },
          { key: "q4", label: "Q4 payment (Jan)", placeholder: "e.g. $2,500" },
          { key: "total", label: "Total estimated tax paid", placeholder: "e.g. $10,000" },
        ]
      },
      {
        label: "Check Section 179 / bonus depreciation eligibility",
        note: "Major tool or equipment purchases may be fully deductible this year",
        fields: [
          { key: "items", label: "Eligible purchases", placeholder: "e.g. Trailer $6,800" },
          { key: "deduction", label: "Total Section 179 deduction", placeholder: "e.g. $6,800" },
        ]
      },
      {
        label: "Check QBI deduction eligibility (20% of qualified business income)",
        note: "Most sole proprietors qualify — software calculates automatically",
        fields: [
          { key: "qbi", label: "Estimated QBI deduction", placeholder: "e.g. $13,000" },
        ]
      },
    ]
  },
  {
    id: "file",
    label: "Phase 4 — Prepare & file",
    badgeText: "Filing",
    tasks: [
      {
        label: "Choose filing method: DIY software vs CPA",
        note: "TurboTax Self-Employed, TaxSlayer, or local CPA",
        fields: [
          { key: "method", label: "Filing method chosen", placeholder: "e.g. TurboTax / CPA: Jane Doe" },
          { key: "cost", label: "Cost", placeholder: "e.g. $180 / $800" },
        ]
      },
      {
        label: "Enter Schedule C data — income, COGS, deductions",
        fields: [
          { key: "status", label: "Status", placeholder: "In progress / Complete" },
        ]
      },
      {
        label: "Review vehicle deduction method",
        note: "Standard: 67c/mile (2024). Actual: receipts for gas, insurance, repairs, depreciation",
        fields: [
          { key: "method", label: "Method chosen", placeholder: "Standard mileage / Actual expenses" },
          { key: "deduction", label: "Final deduction amount", placeholder: "e.g. $2,814" },
        ]
      },
      {
        label: "Review home office deduction",
        note: "Simplified: $5/sq ft up to 300 sq ft",
        fields: [
          { key: "method", label: "Method chosen", placeholder: "Simplified / Regular" },
          { key: "deduction", label: "Final deduction amount", placeholder: "e.g. $600" },
        ]
      },
      {
        label: "Double-check Montana return matches federal AGI",
        fields: [
          { key: "fed_agi", label: "Federal AGI", placeholder: "e.g. $68,000" },
          { key: "mt_start", label: "MT Form 2 starting income", placeholder: "Should match federal AGI" },
        ]
      },
      {
        label: "Review prior year return for carryovers",
        fields: [
          { key: "carryovers", label: "Carryovers noted", placeholder: "e.g. Depreciation schedule from trailer" },
        ]
      },
      {
        label: "E-file federal and Montana returns",
        fields: [
          { key: "fed_date", label: "Federal filed date", placeholder: "e.g. Mar 28, 2025" },
          { key: "fed_confirm", label: "Federal confirmation number", placeholder: "IRS acknowledgment #" },
          { key: "mt_date", label: "Montana filed date", placeholder: "e.g. Mar 28, 2025" },
          { key: "mt_confirm", label: "Montana confirmation number", placeholder: "MT Revenue acknowledgment #" },
        ]
      },
      {
        label: "Pay any balance due",
        note: "IRS Direct Pay (federal) · MT Revenue online portal (state)",
        fields: [
          { key: "fed_balance", label: "Federal balance due / refund", placeholder: "e.g. -$820 owed / +$340 refund" },
          { key: "mt_balance", label: "Montana balance due / refund", placeholder: "e.g. -$210 owed" },
          { key: "paid_date", label: "Payment date", placeholder: "e.g. Apr 12, 2025" },
        ]
      },
    ]
  },
  {
    id: "post",
    label: "Phase 5 — Post-filing housekeeping",
    badgeText: "After you file",
    tasks: [
      {
        label: "Save copies of all filed returns (PDF) in secure location",
        note: "Keep for minimum 7 years",
        fields: [
          { key: "location", label: "Saved to", placeholder: "e.g. Google Drive / External drive" },
        ]
      },
      {
        label: "Set up 2025 quarterly estimated tax payments",
        note: "Due: Apr 15, Jun 15, Sep 15, Jan 15",
        fields: [
          { key: "amount", label: "Quarterly payment amount", placeholder: "e.g. $2,500/quarter" },
          { key: "method", label: "Payment method", placeholder: "IRS Direct Pay / EFTPS" },
        ]
      },
      {
        label: "Update QuickBooks for new fiscal year",
        fields: [
          { key: "done", label: "Status", placeholder: "Complete / In progress" },
        ]
      },
      {
        label: "Review business structure: stay LLC or elect S-Corp?",
        note: "At ~$50K+ net profit, S-Corp can reduce SE tax — talk to a CPA",
        fields: [
          { key: "decision", label: "Decision / notes", placeholder: "e.g. Revisit end of 2025 if net > $60K" },
        ]
      },
      {
        label: "Note deductions missed this year for next year",
        note: "SEP-IRA contributions, health insurance premiums, etc.",
        fields: [
          { key: "missed", label: "Missed deductions to capture next year", placeholder: "e.g. SEP-IRA, better mileage tracking" },
        ]
      },
    ]
  }
];

const BADGE = {
  "Before you start": { bg: "#dbeafe", color: "#1e40af" },
  "Books cleanup":    { bg: "#fef3c7", color: "#92400e" },
  "What you'll file": { bg: "#dcfce7", color: "#166534" },
  "Filing":           { bg: "#ede9fe", color: "#5b21b6" },
  "After you file":   { bg: "#ccfbf1", color: "#065f46" },
};

const TAG = {
  "federal form": { bg: "#dcfce7", color: "#166534" },
  "MT form":      { bg: "#ede9fe", color: "#5b21b6" },
  "QuickBooks":   { bg: "#fef3c7", color: "#92400e" },
};

export default function TaxChecklist() {
  const [checked, setChecked]     = useState({});
  const [expanded, setExpanded]   = useState({});
  const [collapsed, setCollapsed] = useState({});
  const [fieldData, setFieldData] = useState({});
  const [taskNotes, setTaskNotes] = useState({});

  const tk = (pid, i) => `${pid}-${i}`;

  const toggleCheck = (pid, i, e) => {
    e.stopPropagation();
    const k = tk(pid, i);
    setChecked(c => ({ ...c, [k]: !c[k] }));
  };

  const toggleExpand = (pid, i) => {
    const k = tk(pid, i);
    setExpanded(x => ({ ...x, [k]: !x[k] }));
  };

  const togglePhase = id => setCollapsed(c => ({ ...c, [id]: !c[id] }));

  const setField = (k, fk, v) =>
    setFieldData(d => ({ ...d, [`${k}__${fk}`]: v }));

  const getField = (k, fk) => fieldData[`${k}__${fk}`] || "";

  const hasData = (k, task) =>
    (task.fields || []).some(f => getField(k, f.key)) || !!taskNotes[k];

  const total = phases.reduce((s, p) => s + p.tasks.length, 0);
  const done  = Object.values(checked).filter(Boolean).length;
  const pct   = Math.round(done / total * 100);

  return (
    <div style={{ fontFamily: "system-ui,sans-serif", maxWidth: 720, margin: "0 auto", padding: 16 }}>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: 8, marginBottom: 20 }}>
        {[{ val: done, lbl: "completed" }, { val: total, lbl: "total tasks" }, { val: pct + "%", lbl: "progress" }].map(m => (
          <div key={m.lbl} style={{ background: "#f5f5f4", borderRadius: 8, padding: 12, textAlign: "center" }}>
            <div style={{ fontSize: 22, fontWeight: 500 }}>{m.val}</div>
            <div style={{ fontSize: 11, color: "#888", marginTop: 2 }}>{m.lbl}</div>
          </div>
        ))}
      </div>

      {phases.map(phase => {
        const pDone  = phase.tasks.filter((_, i) => checked[tk(phase.id, i)]).length;
        const pTotal = phase.tasks.length;
        const isColl = collapsed[phase.id];
        const b      = BADGE[phase.badgeText] || {};

        return (
          <div key={phase.id} style={{ border: "1px solid #e5e5e5", borderRadius: 10, marginBottom: 12, overflow: "hidden" }}>
            <div onClick={() => togglePhase(phase.id)} style={{ padding: "10px 14px", display: "flex", alignItems: "center", gap: 10, cursor: "pointer", background: "#fafaf9", userSelect: "none" }}>
              <span style={{ fontSize: 11, color: "#bbb", display: "inline-block", transform: isColl ? "rotate(-90deg)" : "rotate(0deg)", transition: "transform 0.2s" }}>▼</span>
              <span style={{ flex: 1, fontSize: 14, fontWeight: 500 }}>{phase.label}</span>
              <span style={{ fontSize: 11, padding: "2px 8px", borderRadius: 999, fontWeight: 500, background: b.bg, color: b.color }}>{phase.badgeText}</span>
              <span style={{ fontSize: 11, color: "#999" }}>{pDone}/{pTotal}</span>
            </div>
            <div style={{ height: 3, background: "#eee" }}>
              <div style={{ height: 3, background: "#3b82f6", width: `${Math.round(pDone / pTotal * 100)}%`, transition: "width 0.3s" }} />
            </div>

            {!isColl && phase.tasks.map((task, i) => {
              const k        = tk(phase.id, i);
              const isDone   = !!checked[k];
              const isExp    = !!expanded[k];
              const tagStyle = task.tag ? TAG[task.tag] : null;
              const saved    = hasData(k, task);

              return (
                <div key={i} style={{ borderTop: "1px solid #f0f0f0" }}>
                  <div onClick={() => toggleExpand(phase.id, i)} style={{ display: "flex", alignItems: "flex-start", gap: 10, padding: "10px 14px", cursor: "pointer", background: isExp ? "#f9fafb" : isDone ? "#fafaf9" : "white" }}>
                    <div
                      onClick={e => toggleCheck(phase.id, i, e)}
                      style={{ width: 16, height: 16, borderRadius: 4, flexShrink: 0, marginTop: 2, border: isDone ? "none" : "1.5px solid #ccc", background: isDone ? "#3b82f6" : "transparent", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}
                    >
                      {isDone && <svg width="10" height="8" viewBox="0 0 10 8" fill="none"><path d="M1 4l3 3 5-6" stroke="white" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>}
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 13, color: isDone ? "#aaa" : "#111", textDecoration: isDone ? "line-through" : "none", display: "flex", flexWrap: "wrap", alignItems: "center", gap: 4 }}>
                        {task.label}
                        {tagStyle && <span style={{ fontSize: 10, padding: "1px 6px", borderRadius: 4, background: tagStyle.bg, color: tagStyle.color, fontWeight: 500 }}>{task.tag}</span>}
                        {saved && !isExp && <span style={{ fontSize: 10, padding: "1px 6px", borderRadius: 4, background: "#f0fdf4", color: "#166534", fontWeight: 500 }}>data saved</span>}
                      </div>
                      {task.note && <div style={{ fontSize: 11, color: isDone ? "#ccc" : "#888", marginTop: 2 }}>{task.note}</div>}
                    </div>
                    <span style={{ fontSize: 10, color: "#bbb", marginTop: 3, flexShrink: 0 }}>{isExp ? "▲" : "▼"}</span>
                  </div>

                  {isExp && (
                    <div style={{ padding: "0 14px 14px 40px", background: "#f9fafb", borderTop: "1px solid #f0f0f0" }}>
                      {(task.fields || []).length > 0 && (
                        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(190px, 1fr))", gap: 8, marginTop: 10 }}>
                          {task.fields.map(f => (
                            <div key={f.key}>
                              <div style={{ fontSize: 11, color: "#555", marginBottom: 3, fontWeight: 500 }}>{f.label}</div>
                              <input
                                value={getField(k, f.key)}
                                onChange={e => setField(k, f.key, e.target.value)}
                                placeholder={f.placeholder}
                                onClick={e => e.stopPropagation()}
                                style={{ width: "100%", fontSize: 12, padding: "5px 8px", border: "1px solid #e0e0e0", borderRadius: 6, background: "white", color: "#111", outline: "none", boxSizing: "border-box" }}
                              />
                            </div>
                          ))}
                        </div>
                      )}
                      <div style={{ marginTop: 10 }}>
                        <div style={{ fontSize: 11, color: "#555", marginBottom: 3, fontWeight: 500 }}>Notes</div>
                        <textarea
                          value={taskNotes[k] || ""}
                          onChange={e => setTaskNotes(n => ({ ...n, [k]: e.target.value }))}
                          placeholder="Any additional notes, questions, or flags..."
                          onClick={e => e.stopPropagation()}
                          rows={2}
                          style={{ width: "100%", fontSize: 12, padding: "5px 8px", border: "1px solid #e0e0e0", borderRadius: 6, background: "white", color: "#111", outline: "none", resize: "vertical", boxSizing: "border-box", fontFamily: "system-ui,sans-serif" }}
                        />
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        );
      })}

      <p style={{ fontSize: 11, color: "#bbb", marginTop: 8, borderTop: "1px solid #f0f0f0", paddingTop: 8 }}>
        General guidance only — not tax advice. Consult a CPA for your specific situation.
      </p>
    </div>
  );
}
