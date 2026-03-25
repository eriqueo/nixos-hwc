import { useState } from 'react';
import { C, mono } from '../styles/theme.js';
import { Box, Label } from './Section.jsx';
import { NumInput } from './NumInput.jsx';
import { deriveGeometry } from '../engine/assembler.js';
import tradeRates from '../data/tradeRates.json';
import { tradeRate } from '../engine/pricing.js';

export function DetailsTab({ s, set, isMobile = false }) {
  const { fl, wallTile } = deriveGeometry(s);
  const [newItem, setNewItem] = useState({
    name: '', group: 'Additional Items', qty: 1,
    cost: 0, type: 'Materials', unit: 'Each',
  });

  const addCustomItem = () => {
    if (!newItem.name) return;
    set('custom_items', [...(s.custom_items ?? []), { ...newItem }]);
    setNewItem({ name: '', group: 'Additional Items', qty: 1, cost: 0, type: 'Materials', unit: 'Each' });
  };

  const removeCustomItem = idx => {
    set('custom_items', s.custom_items.filter((_, i) => i !== idx));
  };

  const inp = (overrides) => ({
    padding: isMobile ? '10px 10px' : '6px 8px',
    borderRadius: isMobile ? 4 : 3,
    border: `1px solid ${C.brd}`,
    backgroundColor: C.card2, color: C.txB,
    fontSize: isMobile ? 14 : 12, fontFamily: mono, outline: 'none',
    minHeight: isMobile ? 44 : 'auto',
    ...overrides,
  });

  return (
    <div style={{ display: 'grid', gridTemplateColumns: isMobile ? '1fr' : '1fr 1fr', gap: isMobile ? 10 : 14 }}>

      {/* Allowances */}
      <Box>
        <Label color={C.acc}>Allowance Amounts</Label>
        <NumInput label="Bathtub"      value={s.tub_allowance}          onChange={v => set('tub_allowance',          v)} unit="$" show={s.has_tub}    step={100} />
        <NumInput label="Shower Trim"  value={s.shower_trim_allowance}  onChange={v => set('shower_trim_allowance',  v)} unit="$" show={s.has_shower} step={100} />
        <NumInput label="Toilet"       value={s.toilet_allowance}       onChange={v => set('toilet_allowance',       v)} unit="$" step={100} />
        <NumInput label="Vanity"       value={s.vanity_allowance}       onChange={v => set('vanity_allowance',       v)} unit="$" step={100} />
        <NumInput label="Accessories"  value={s.accessory_allowance}    onChange={v => set('accessory_allowance',    v)} unit="$" step={100} />
        <div style={{ marginTop: 8, padding: 8, backgroundColor: C.card2, borderRadius: 4 }}>
          <span style={{ color: C.txD, fontSize: 10 }}>
            Tile allowances are auto-calculated from sqft.
            Floor: ${Math.max(400, Math.round(fl * 10)).toLocaleString()} ·
            Shower: ${Math.max(800, Math.round(wallTile * 12)).toLocaleString()}
          </span>
        </div>
      </Box>

      {/* Custom Line Items */}
      <Box>
        <Label color={C.txD}>Add Custom Line Item</Label>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <input placeholder="Item name" value={newItem.name}
            onChange={e => setNewItem(p => ({ ...p, name: e.target.value }))}
            style={inp({ width: '100%' })} />
          <div style={{ display: 'flex', gap: 6 }}>
            <input placeholder="Group" value={newItem.group}
              onChange={e => setNewItem(p => ({ ...p, group: e.target.value }))}
              style={inp({ flex: 1 })} />
            <select value={newItem.type} onChange={e => setNewItem(p => ({ ...p, type: e.target.value }))}
              style={inp({ padding: '6px' })}>
              <option value="Materials">Materials</option>
              <option value="Labor">Labor</option>
              <option value="Other">Other</option>
            </select>
          </div>
          <div style={{ display: 'flex', gap: 6, flexWrap: isMobile ? 'wrap' : 'nowrap' }}>
            <input type="number" placeholder="Qty" value={newItem.qty}
              onChange={e => setNewItem(p => ({ ...p, qty: parseFloat(e.target.value) || 0 }))}
              style={inp({ width: isMobile ? '30%' : 60, textAlign: 'right', flex: isMobile ? '1' : 'none' })} />
            <input type="number" placeholder="Unit Cost" value={newItem.cost || ''}
              onChange={e => setNewItem(p => ({ ...p, cost: parseFloat(e.target.value) || 0 }))}
              style={inp({ width: isMobile ? '50%' : 80, textAlign: 'right', flex: isMobile ? '2' : 'none' })} />
            <button onClick={addCustomItem} style={{
              padding: isMobile ? '12px 18px' : '6px 14px',
              borderRadius: isMobile ? 4 : 3, border: 'none', cursor: 'pointer',
              backgroundColor: C.acc, color: C.bg,
              fontSize: isMobile ? 13 : 11, fontWeight: 700, fontFamily: mono,
              flex: isMobile ? '1' : 'none',
              minHeight: isMobile ? 44 : 'auto',
            }}>+ Add</button>
          </div>
        </div>

        {(s.custom_items?.length ?? 0) > 0 && (
          <div style={{ marginTop: 10 }}>
            {s.custom_items.map((ci, idx) => (
              <div key={idx} style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0', borderBottom: `1px solid ${C.brd}` }}>
                <span style={{ color: C.tx, fontSize: 11 }}>{ci.name} ({ci.qty}× ${ci.cost})</span>
                <button onClick={() => removeCustomItem(idx)}
                  style={{ background: 'none', border: 'none', color: C.red, cursor: 'pointer', fontSize: 11, fontFamily: mono }}>×</button>
              </div>
            ))}
          </div>
        )}
      </Box>

      {/* Trade Rate Reference */}
      <Box style={{ gridColumn: '1/-1' }}>
        <Label>Trade Labor Rates (reference — edit in catalog DB)</Label>
        <div style={{ display: 'grid', gridTemplateColumns: isMobile ? 'repeat(3, 1fr)' : 'repeat(5, 1fr)', gap: 8 }}>
          {Object.keys(tradeRates).map(trade => {
            const r = tradeRate(trade);
            return (
              <div key={trade} style={{ padding: 8, backgroundColor: C.card2, borderRadius: 4, textAlign: 'center' }}>
                <div style={{ color: C.txD, fontSize: 9, textTransform: 'uppercase', marginBottom: 2 }}>{trade}</div>
                <div style={{ color: C.txB, fontSize: 13, fontWeight: 600 }}>${r.cost.toFixed(2)}</div>
                <div style={{ color: C.acc, fontSize: 10 }}>${r.price.toFixed(2)}/hr</div>
              </div>
            );
          })}
        </div>
      </Box>
    </div>
  );
}
