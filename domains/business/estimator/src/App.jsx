import { useState, useCallback } from 'react';
import { C, mono } from './styles/theme.js';
import { Stat } from './components/Section.jsx';
import { ScopeTab }    from './components/ScopeTab.jsx';
import { DetailsTab }  from './components/DetailsTab.jsx';
import { EstimateTab } from './components/EstimateTab.jsx';
import { CatalogBrowser } from './components/CatalogBrowser.jsx';
import { useProjectState } from './hooks/useProjectState.js';
import { useCatalog }      from './hooks/useCatalog.js';
import { useIsMobile }     from './hooks/useIsMobile.js';
import { calculatorMeasurementIssues } from './engine/geometry.js';

const TABS = [
  { id: 'scope',    label: 'Scope' },
  { id: 'details',  label: 'Details' },
  { id: 'estimate', label: 'Budget' },
];

export default function App() {
  const [state, set, reset, storageError, restore, selectJob, prefill] = useProjectState();
  const overrides = state.budget_overrides;
  const removed = state.budget_removed;
  const setOverrides = useCallback(value => set('budget_overrides', value), [set]);
  const setRemoved = useCallback(value => set('budget_removed', value), [set]);
  const [draftError, setDraftError] = useState('');
  const [view,      setView]      = useState('scope');
  const [browserOpen, setBrowserOpen] = useState(false);
  const isMobile = useIsMobile();

  const { totals, groups } = useCatalog(state, overrides, removed);
  const awaitingMeasurements = calculatorMeasurementIssues(state).length > 0 || ['pending','failed'].includes(state.calculator_input_status);

  const assemble = useCallback(() => {
    setView('estimate');
  }, []);

  const handleAddPicks = useCallback((picks) => {
    const existing = state.catalog_picks || [];
    set('catalog_picks', [...existing, ...picks.map(p => ({ ...p, draftId: crypto.randomUUID() }))]);
  }, [state.catalog_picks, set]);

  const tabLabel = id => id === 'estimate' ? `Budget (${totals.items})` : TABS.find(t => t.id === id)?.label;

  return (
    <div className="estimator-app" style={{ minHeight: '100dvh', backgroundColor: C.bg, color: C.tx, fontFamily: mono }}>

      {/* ── HEADER ─────────────────────────────────────────────────────────── */}
      <div style={{
        padding: isMobile ? '12px 12px 0' : '16px 20px 0',
        borderBottom: `1px solid ${C.brd}`,
        position: isMobile ? 'sticky' : 'static',
        top: 0,
        backgroundColor: C.bg,
        zIndex: 100,
      }}>
        {/* Title + Stats row */}
        <div style={{
          display: 'flex',
          flexDirection: isMobile ? 'column' : 'row',
          justifyContent: 'space-between',
          alignItems: isMobile ? 'stretch' : 'center',
          gap: isMobile ? 10 : 0,
          marginBottom: 12,
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <span style={{ color: C.acc, fontSize: isMobile ? 14 : 15, fontWeight: 800 }}>⬡ Heartwood</span>
              {!isMobile && <span style={{ color: C.txD, fontSize: 11, marginLeft: 8 }}>Estimate Assembler v2</span>}
            </div>
            {isMobile && (
              <button onClick={reset} title="Reset all fields" style={{
                padding: '6px 10px', border: 'none', cursor: 'pointer',
                background: 'transparent', color: C.txD, fontSize: 10, fontFamily: mono,
              }}>
                ↺ reset
              </button>
            )}
          </div>
          {/* Stats bar - horizontal scroll on mobile */}
          <div style={{
            display: 'flex',
            gap: isMobile ? 12 : 16,
            justifyContent: isMobile ? 'space-between' : 'flex-end',
            padding: isMobile ? '8px 0' : 0,
            backgroundColor: isMobile ? C.card : 'transparent',
            borderRadius: isMobile ? 6 : 0,
            paddingLeft: isMobile ? 12 : 0,
            paddingRight: isMobile ? 12 : 0,
          }}>
            <Stat label="Cost"   value={awaitingMeasurements ? '—' : `$${Math.round(totals.cost).toLocaleString()}`} compact={isMobile} />
            <Stat label="Price"  value={awaitingMeasurements ? '—' : `$${Math.round(totals.price).toLocaleString()}`} color={C.acc} compact={isMobile} />
            <Stat label="Margin" value={awaitingMeasurements ? '—' : `${totals.margin.toFixed(1)}%`} color={C.grn} compact={isMobile} />
            <Stat label="Labor"  value={awaitingMeasurements ? '—' : `${Math.round(totals.laborHrs)}h`} color={C.blu} compact={isMobile} />
          </div>
        </div>

        {/* Tab bar */}
        <div style={{ display: 'flex', gap: 0 }}>
          {TABS.map(t => (
            <button key={t.id} onClick={() => setView(t.id)} style={{
              padding: isMobile ? '10px 12px' : '7px 18px',
              border: 'none', cursor: 'pointer',
              fontSize: isMobile ? 10 : 11, fontWeight: 600, fontFamily: mono,
              letterSpacing: '0.06em', textTransform: 'uppercase', transition: 'all 0.1s',
              borderRadius: '4px 4px 0 0',
              backgroundColor: view === t.id ? C.card : 'transparent',
              color: view === t.id ? C.acc : C.txD,
              borderBottom: view === t.id ? `2px solid ${C.acc}` : '2px solid transparent',
              flex: isMobile ? 1 : 'none',
              minHeight: isMobile ? 44 : 'auto',
            }}>
              {tabLabel(t.id)}
            </button>
          ))}
          {!isMobile && <div style={{ flex: 1 }} />}
          {!isMobile && (
            <button onClick={reset} title="Reset all fields" style={{
              padding: '7px 12px', border: 'none', cursor: 'pointer',
              background: 'transparent', color: C.txD, fontSize: 10, fontFamily: mono,
            }}>
              ↺ reset
            </button>
          )}
        </div>
      </div>

      {/* ── TAB CONTENT ────────────────────────────────────────────────────── */}
      <div className="app-content" style={{ padding: isMobile ? 10 : 16, maxWidth: 1400, margin: '0 auto' }}>
        <div className="draft-tools">
          <span>{state.jobName || 'Working draft'} · saved on this device</span>
          <button onClick={() => {
            const url = URL.createObjectURL(new Blob([JSON.stringify(state, null, 2)], { type: 'application/json' }));
            const link = document.createElement('a'); link.href = url;
            link.download = `estimate-${state.jobNumber || 'draft'}.json`; link.click();
            URL.revokeObjectURL(url);
          }}>Download draft</button>
          <label className="import-draft">Import draft<input type="file" accept="application/json,.json" onChange={async e => {
            try {
              const file = e.target.files[0]; if (!file) return;
              if (file.size > 2000000) throw new Error('Draft is too large');
              restore(JSON.parse(await file.text())); setDraftError('');
            } catch (error) { setDraftError(error.message); }
            e.target.value = '';
          }} /></label>
        </div>
        {(storageError || draftError) && <p role="alert">{storageError || draftError}</p>}
        {view === 'scope' && (
          <ScopeTab s={state} set={set} selectJob={selectJob} prefill={prefill} onAssemble={assemble} isMobile={isMobile} />
        )}
        {view === 'details' && (
          <DetailsTab s={state} set={set} isMobile={isMobile} />
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
            onOpenBrowser={() => setBrowserOpen(true)}
            state={state}
            set={set}
            isMobile={isMobile}
          />
        )}
      </div>

      <CatalogBrowser
        open={browserOpen}
        onClose={() => setBrowserOpen(false)}
        onAdd={handleAddPicks}
        isMobile={isMobile}
      />
    </div>
  );
}
