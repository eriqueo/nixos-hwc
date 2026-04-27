import { useState } from 'react';
import { C, GROUP_COLORS, mono } from '../styles/theme.js';
import { Box } from './Section.jsx';
import { buildParameters } from '../engine/assembler.js';
import jtMappings from '../data/jtMappings.json';

const WEBHOOK_URL = import.meta.env.VITE_WEBHOOK_URL ?? localStorage.getItem('hwc-webhook-url') ?? '';
const API_KEY = import.meta.env.VITE_API_KEY ?? localStorage.getItem('hwc-api-key') ?? '';

const COL = '1fr 54px 70px 70px 80px 80px 30px';

function Row({ children, style, isMobile = false }) {
  if (isMobile) {
    return <div style={style}>{children}</div>;
  }
  return (
    <div style={{ display: 'grid', gridTemplateColumns: COL, gap: 6, ...style }}>
      {children}
    </div>
  );
}

export function EstimateTab({ groups, totals, overrides, setOverrides, removed, setRemoved, onBack, onDetails, state, isMobile = false }) {
  const [pushMsg, setPushMsg] = usePushMsg();
  const [pushResult, setPushResult] = useState(null);

  const buildJtPayload = () => {
    const items = Object.values(groups).flat();
    return items.map(i => {
      const item = {
        name:        i.name,
        groupName:   i.group,
        costCodeId:  jtMappings.codes[i.code],
        costTypeId:  jtMappings.types[i.type],
        unitId:      jtMappings.units[i.unit],
        unitCost:    i.uc,
        unitPrice:   i.up,
      };
      // Items with JT formulas get quantityFormula; others get numeric quantity
      if (i.quantityFormula) {
        item.quantityFormula = i.quantityFormula;
      } else {
        item.quantity = i.qty;
      }
      return item;
    });
  };

  const copyPayload = async () => {
    const payload = { parameters: buildParameters(state), items: buildJtPayload() };
    await navigator.clipboard.writeText(JSON.stringify(payload, null, 2));
    setPushMsg('copied');
  };

  const canPush = () => {
    if (!state) return false;
    if (state.mode === 'existing') return !!state.customerId && !!state.jobId;
    if (state.mode === 'new_job') return !!state.customerId && !!state.jobName;
    if (state.mode === 'new_customer') return !!state.newCustomerName && !!state.jobName;
    return false;
  };

  const pushToWebhook = async () => {
    if (!WEBHOOK_URL) { setPushMsg('no-url'); return; }
    if (!API_KEY) { setPushMsg('no-key'); return; }
    if (!canPush()) { setPushMsg('no-job'); return; }

    try {
      setPushMsg('pushing');
      setPushResult(null);

      const payload = {
        action: 'push_estimate',
        mode: state.mode,
        projectType: state.projectType,

        // Job identification
        jobId: state.jobId || null,
        jobNumber: state.jobNumber || null,
        jobName: state.jobName || null,
        customerId: state.customerId || null,
        customerName: state.customerName || state.newCustomerName || null,

        // For new job creation (new_job and new_customer both need a new job)
        newJob: (state.mode === 'new_job' || state.mode === 'new_customer') ? {
          customerId: state.customerId || null,
          customerName: state.customerName || state.newCustomerName,
          locationId: state.locationId || null,
          jobName: state.jobName,
          address: state.address || '',
        } : null,

        // For new customer creation
        newCustomer: state.mode === 'new_customer' ? {
          name: state.newCustomerName,
          phone: state.newCustomerPhone,
          email: state.newCustomerEmail,
          street: state.newCustomerStreet,
          city: state.newCustomerCity,
          state: state.newCustomerState,
          zip: state.newCustomerZip,
        } : null,

        // JT parameters array — pushed to createJob
        parameters: buildParameters(state),

        // Full state for change order tracking
        projectState: state,

        // Line items (with quantityFormula where available)
        estimate: Object.values(groups).flat(),
        jtPayload: buildJtPayload(),
        totals: {
          ...totals,
          margin: totals.margin,
        },

        timestamp: new Date().toISOString(),
      };

      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': API_KEY,
        },
        body: JSON.stringify(payload),
      });

      const result = await response.json();
      setPushResult(result);

      if (result.success && result.jtPushSuccess) {
        setPushMsg('pushed');
      } else if (result.success && !result.jtPushSuccess) {
        setPushMsg('archived');
      } else {
        setPushMsg('error');
      }
    } catch (err) {
      setPushResult({ error: err.message });
      setPushMsg('error');
    }
  };

  const MobileItemCard = ({ item, gc }) => (
    <div style={{
      padding: '10px 12px',
      borderBottom: `1px solid ${C.brd}22`,
      backgroundColor: item._edited ? 'rgba(201,149,107,0.04)' : 'transparent',
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 6 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, flex: 1, minWidth: 0 }}>
          <div style={{ width: 3, height: 14, borderRadius: 1, backgroundColor: gc, flexShrink: 0 }} />
          <span style={{ color: C.tx, fontSize: 12, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {item.name}
          </span>
        </div>
        <button onClick={() => setRemoved(r => ({ ...r, [item.id]: true }))}
          style={{ background: 'none', border: 'none', color: C.txD, cursor: 'pointer', fontSize: 14, fontFamily: mono, padding: '0 0 0 8px' }}>x</button>
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <input type="number" value={item.qty}
            onChange={e => setOverrides(o => ({ ...o, [item.id]: parseFloat(e.target.value) || 0 }))}
            style={{ width: 56, padding: '6px 8px', borderRadius: 4,
              border: `1px solid ${C.brd}`, backgroundColor: C.card2, color: C.txB,
              fontSize: 13, textAlign: 'right', fontFamily: 'inherit', outline: 'none', minHeight: 36 }} />
          <span style={{ color: C.txD, fontSize: 11 }}>{item.unit}</span>
        </div>
        <div style={{ textAlign: 'right' }}>
          <div style={{ color: C.txD, fontSize: 10 }}>${item.uc.toFixed(2)}/{item.unit}</div>
          <div style={{ color: C.acc, fontSize: 14, fontWeight: 600 }}>${Math.round(item.extP).toLocaleString()}</div>
        </div>
      </div>
      {item.quantityFormula && (
        <div style={{ marginTop: 4, fontSize: 9, color: C.txD, fontFamily: mono, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          JT: {item.quantityFormula}
        </div>
      )}
    </div>
  );

  return (
    <div>
      <Box style={{ padding: 0, overflow: 'hidden' }}>
        {!isMobile && (
          <Row style={{ padding: '7px 10px', backgroundColor: C.card2, borderBottom: `1px solid ${C.brd}`,
            fontSize: 9, color: C.txD, textTransform: 'uppercase', letterSpacing: '0.1em', fontWeight: 600 }}>
            <span>Item</span>
            <span style={{ textAlign: 'right' }}>Qty</span>
            <span style={{ textAlign: 'right' }}>Unit</span>
            <span style={{ textAlign: 'right' }}>$/Unit</span>
            <span style={{ textAlign: 'right' }}>Cost</span>
            <span style={{ textAlign: 'right' }}>Price</span>
            <span />
          </Row>
        )}

        {Object.entries(groups).map(([gn, items]) => {
          const base  = gn.split(' > ')[0];
          const gc    = GROUP_COLORS[base] ?? C.txD;
          const gCost  = items.reduce((a, i) => a + i.extC, 0);
          const gPrice = items.reduce((a, i) => a + i.extP, 0);

          return (
            <div key={gn}>
              {isMobile ? (
                <div style={{
                  padding: '10px 12px',
                  backgroundColor: 'rgba(255,255,255,0.015)',
                  borderBottom: `1px solid ${C.brd}`,
                  borderTop: `1px solid ${C.brd}`,
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                }}>
                  <span style={{ color: gc, fontSize: 12, fontWeight: 700 }}>{gn}</span>
                  <span style={{ color: gc, fontSize: 12, fontWeight: 600 }}>${Math.round(gPrice).toLocaleString()}</span>
                </div>
              ) : (
                <Row style={{ padding: '6px 10px', backgroundColor: 'rgba(255,255,255,0.015)',
                  borderBottom: `1px solid ${C.brd}`, borderTop: `1px solid ${C.brd}` }}>
                  <span style={{ color: gc, fontSize: 11, fontWeight: 700 }}>{gn}</span>
                  <span /><span /><span />
                  <span style={{ color: C.txD, fontSize: 10, textAlign: 'right' }}>${Math.round(gCost).toLocaleString()}</span>
                  <span style={{ color: gc, fontSize: 10, textAlign: 'right', fontWeight: 600 }}>${Math.round(gPrice).toLocaleString()}</span>
                  <span />
                </Row>
              )}

              {isMobile ? (
                items.map(item => <MobileItemCard key={item.id} item={item} gc={gc} />)
              ) : (
                items.map(item => (
                  <Row key={item.id} style={{ padding: '5px 10px', alignItems: 'center',
                    borderBottom: `1px solid ${C.brd}22`, fontSize: 11,
                    backgroundColor: item._edited ? 'rgba(201,149,107,0.04)' : 'transparent' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, overflow: 'hidden' }}>
                      <div style={{ width: 2, height: 12, borderRadius: 1, backgroundColor: gc, flexShrink: 0 }} />
                      <span style={{ color: C.tx, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                        {item.name}
                        {item.quantityFormula && <span style={{ color: C.txD, fontSize: 8, marginLeft: 4 }}>f(x)</span>}
                      </span>
                    </div>
                    <input type="number" value={item.qty}
                      onChange={e => setOverrides(o => ({ ...o, [item.id]: parseFloat(e.target.value) || 0 }))}
                      style={{ width: 48, padding: '2px 4px', borderRadius: 3,
                        border: `1px solid ${C.brd}`, backgroundColor: C.card2, color: C.txB,
                        fontSize: 11, textAlign: 'right', fontFamily: 'inherit', outline: 'none' }} />
                    <span style={{ color: C.txD, textAlign: 'right', fontSize: 10 }}>{item.unit}</span>
                    <span style={{ color: C.tx,  textAlign: 'right' }}>${item.uc.toFixed(2)}</span>
                    <span style={{ color: C.tx,  textAlign: 'right' }}>${Math.round(item.extC).toLocaleString()}</span>
                    <span style={{ color: C.acc, textAlign: 'right', fontWeight: 600 }}>${Math.round(item.extP).toLocaleString()}</span>
                    <button onClick={() => setRemoved(r => ({ ...r, [item.id]: true }))}
                      style={{ background: 'none', border: 'none', color: C.txD, cursor: 'pointer', fontSize: 10, fontFamily: mono, padding: 0 }}>x</button>
                  </Row>
                ))
              )}
            </div>
          );
        })}

        {/* Totals */}
        {isMobile ? (
          <div style={{ padding: '12px', backgroundColor: C.card2, borderTop: `2px solid ${C.acc}` }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
              <span style={{ color: C.txD, fontSize: 11 }}>{totals.items} items · {Math.round(totals.laborHrs)}h labor</span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <span style={{ color: C.txB, fontSize: 12 }}>Cost: ${Math.round(totals.cost).toLocaleString()}</span>
              <span style={{ color: C.acc, fontSize: 18, fontWeight: 700 }}>${Math.round(totals.price).toLocaleString()}</span>
            </div>
          </div>
        ) : (
          <Row style={{ padding: '10px 10px', backgroundColor: C.card2, borderTop: `2px solid ${C.acc}` }}>
            <span style={{ color: C.txB, fontSize: 12, fontWeight: 700 }}>
              TOTAL · {totals.items} items · {Math.round(totals.laborHrs)}h labor
            </span>
            <span /><span /><span />
            <span style={{ color: C.txB, fontSize: 13, fontWeight: 700, textAlign: 'right' }}>${Math.round(totals.cost).toLocaleString()}</span>
            <span style={{ color: C.acc, fontSize: 13, fontWeight: 700, textAlign: 'right' }}>${Math.round(totals.price).toLocaleString()}</span>
            <span />
          </Row>
        )}
      </Box>

      {/* Action buttons */}
      <div style={{
        display: 'flex',
        flexDirection: isMobile ? 'column' : 'row',
        gap: 10,
        marginTop: 14,
        justifyContent: isMobile ? 'stretch' : 'flex-end',
        flexWrap: 'wrap',
      }}>
        {isMobile ? (
          <>
            <div style={{ display: 'flex', gap: 10 }}>
              <button onClick={onBack} style={{ ...ghostBtn, flex: 1 }}>Scope</button>
              <button onClick={onDetails} style={{ ...ghostBtn, flex: 1 }}>Allowances</button>
            </div>
            <button
              onClick={pushToWebhook}
              disabled={!canPush() || pushMsg === 'pushing'}
              style={{
                ...accentBtn,
                width: '100%',
                padding: '14px 18px',
                fontSize: 13,
                opacity: canPush() ? 1 : 0.5,
                cursor: canPush() ? 'pointer' : 'not-allowed',
              }}
            >
              {pushLabel(pushMsg)}
            </button>
          </>
        ) : (
          <>
            <button onClick={onBack} style={ghostBtn}>Edit Scope</button>
            <button onClick={onDetails} style={ghostBtn}>Allowances</button>
            <button onClick={copyPayload} style={accentBtn}>{pushMsg === 'copied' ? 'Copied' : 'Copy Payload'}</button>
            <button
              onClick={pushToWebhook}
              disabled={!canPush() || pushMsg === 'pushing'}
              style={{
                ...accentBtn,
                opacity: canPush() ? 1 : 0.5,
                cursor: canPush() ? 'pointer' : 'not-allowed',
              }}
            >
              {pushLabel(pushMsg)}
            </button>
          </>
        )}
      </div>

      {/* Status messages */}
      {pushMsg === 'no-url' && <StatusBox>No webhook URL. Set <code>VITE_WEBHOOK_URL</code> or localStorage.</StatusBox>}
      {pushMsg === 'no-key' && <StatusBox>No API key. Set <code>VITE_API_KEY</code> or localStorage.</StatusBox>}
      {pushMsg === 'no-job' && <StatusBox>Select a job, or fill in new job/customer details in Scope tab.</StatusBox>}

      {pushResult && (
        <div style={{
          marginTop: 10, padding: 10, borderRadius: 5,
          backgroundColor: pushResult.jtPushSuccess ? 'rgba(107,203,119,0.1)' : 'rgba(238,107,110,0.1)',
          border: `1px solid ${pushResult.jtPushSuccess ? C.grn : C.red}`
        }}>
          {pushResult.jtPushSuccess ? (
            <div style={{ fontSize: 11, color: C.grn }}>
              <div style={{ fontWeight: 600, marginBottom: 4 }}>Pushed to JobTread</div>
              <div style={{ color: C.tx }}>
                Job #{pushResult.jobNumber} · {pushResult.itemsPushed} items
                {pushResult.accountCreated && ' · New customer created'}
                {pushResult.jobCreated && ' · New job created'}
              </div>
            </div>
          ) : pushResult.archived ? (
            <div style={{ fontSize: 11, color: C.ylw }}>
              <div style={{ fontWeight: 600, marginBottom: 4 }}>Archived (JT Push Failed)</div>
              <div style={{ color: C.tx }}>Error: {pushResult.jtPushError}</div>
            </div>
          ) : pushResult.error ? (
            <div style={{ fontSize: 11, color: C.red }}>
              <div style={{ fontWeight: 600 }}>Error: {pushResult.error}</div>
            </div>
          ) : null}
        </div>
      )}
    </div>
  );
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function usePushMsg() {
  const [msg, setMsg] = useState(null);
  const set = (v) => { setMsg(v); if (v !== 'pushing') setTimeout(() => setMsg(null), 2500); };
  return [msg, set];
}

function pushLabel(msg) {
  if (msg === 'pushing') return '...';
  if (msg === 'pushed') return 'Pushed to JT';
  if (msg === 'archived') return 'Archived (JT failed)';
  if (msg === 'error') return 'Error';
  return 'Push to JT';
}

function StatusBox({ children }) {
  return (
    <div style={{ marginTop: 10, padding: 10, backgroundColor: C.card, borderRadius: 5, border: `1px solid ${C.brd}` }}>
      <span style={{ color: C.txD, fontSize: 10 }}>{children}</span>
    </div>
  );
}

const ghostBtn = {
  padding: '9px 18px', borderRadius: 5,
  border: `1px solid ${C.brd}`, cursor: 'pointer',
  backgroundColor: 'transparent', color: C.txD,
  fontSize: 11, fontWeight: 600, fontFamily: mono,
};
const accentBtn = {
  padding: '9px 18px', borderRadius: 5,
  border: 'none', cursor: 'pointer',
  backgroundColor: C.acc, color: C.bg,
  fontSize: 11, fontWeight: 700, fontFamily: mono,
};
