import { useState, useCallback } from 'react';
import { C, mono } from './styles/theme.js';
import { Stat } from './components/Section.jsx';
import { ScopeTab }    from './components/ScopeTab.jsx';
import { DetailsTab }  from './components/DetailsTab.jsx';
import { EstimateTab } from './components/EstimateTab.jsx';
import { useProjectState } from './hooks/useProjectState.js';
import { useCatalog }      from './hooks/useCatalog.js';

const TABS = [
  { id: 'scope',    label: 'Scope' },
  { id: 'details',  label: 'Details' },
  { id: 'estimate', label: 'Budget' },
];

export default function App() {
  const [state, set, reset] = useProjectState();
  const [overrides, setOverrides] = useState({});
  const [removed,   setRemoved]   = useState({});
  const [view,      setView]      = useState('scope');

  const { totals, groups } = useCatalog(state, overrides, removed);

  const assemble = useCallback(() => {
    setOverrides({});
    setRemoved({});
    setView('estimate');
  }, []);

  const tabLabel = id => id === 'estimate' ? `Budget (${totals.items})` : TABS.find(t => t.id === id)?.label;

  return (
    <div style={{ minHeight: '100vh', backgroundColor: C.bg, color: C.tx, fontFamily: mono }}>

      {/* ── HEADER ─────────────────────────────────────────────────────────── */}
      <div style={{ padding: '16px 20px 0', borderBottom: `1px solid ${C.brd}` }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
          <div>
            <span style={{ color: C.acc, fontSize: 15, fontWeight: 800 }}>⬡ Heartwood</span>
            <span style={{ color: C.txD, fontSize: 11, marginLeft: 8 }}>Estimate Assembler v2</span>
          </div>
          <div style={{ display: 'flex', gap: 16 }}>
            <Stat label="Cost"   value={`$${Math.round(totals.cost).toLocaleString()}`} />
            <Stat label="Price"  value={`$${Math.round(totals.price).toLocaleString()}`} color={C.acc} />
            <Stat label="Margin" value={`${totals.margin.toFixed(1)}%`} color={C.grn} />
            <Stat label="Labor"  value={`${Math.round(totals.laborHrs)}h`} color={C.blu} />
          </div>
        </div>

        {/* Tab bar */}
        <div style={{ display: 'flex', gap: 0 }}>
          {TABS.map(t => (
            <button key={t.id} onClick={() => setView(t.id)} style={{
              padding: '7px 18px', border: 'none', cursor: 'pointer',
              fontSize: 11, fontWeight: 600, fontFamily: mono,
              letterSpacing: '0.06em', textTransform: 'uppercase', transition: 'all 0.1s',
              borderRadius: '4px 4px 0 0',
              backgroundColor: view === t.id ? C.card : 'transparent',
              color: view === t.id ? C.acc : C.txD,
              borderBottom: view === t.id ? `2px solid ${C.acc}` : '2px solid transparent',
            }}>
              {tabLabel(t.id)}
            </button>
          ))}
          <div style={{ flex: 1 }} />
          <button onClick={reset} title="Reset all fields" style={{
            padding: '7px 12px', border: 'none', cursor: 'pointer',
            background: 'transparent', color: C.txD, fontSize: 10, fontFamily: mono,
          }}>
            ↺ reset
          </button>
        </div>
      </div>

      {/* ── TAB CONTENT ────────────────────────────────────────────────────── */}
      <div style={{ padding: 16, maxWidth: 980, margin: '0 auto' }}>
        {view === 'scope' && (
          <ScopeTab s={state} set={set} onAssemble={assemble} />
        )}
        {view === 'details' && (
          <DetailsTab s={state} set={set} />
        )}
        {view === 'estimate' && (
          <EstimateTab
            groups={groups}
            totals={totals}
            overrides={overrides}
            setOverrides={setOverrides}
            removed={removed}
            setRemoved={setRemoved}
            onBack={() => setView('scope')}
            onDetails={() => setView('details')}
          />
        )}
      </div>
    </div>
  );
}
