import { useState } from 'react';
import { C, mono } from '../styles/theme.js';
import { Box, Label } from './Section.jsx';
import { deriveGeometry } from '../engine/assembler.js';
import tradeRates from '../data/tradeRates.json';
import { tradeRate } from '../engine/pricing.js';
import { NumInput } from './NumInput.jsx';
import jtMappings from '../data/jtMappings.json';

const EMPTY_CUSTOM_ITEM = {
  name: '', group: 'Additional Items', qty: 1, cost: 0,
  type: 'Materials', unit: 'Each', code: '3100', trade: null,
};

function AllowanceRow({ label, value, onChange, enabled, onToggle, show = true }) {
  if (!show) return null;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0' }}>
      <button
        onClick={() => onToggle(!enabled)}
        style={{
          width: 44, height: 44, borderRadius: 3, border: `1px solid ${C.brd}`,
          backgroundColor: enabled ? C.acc : 'transparent', cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 11, color: enabled ? C.bg : 'transparent', fontWeight: 700, flexShrink: 0,
        }}
        aria-label={`HWC supplies ${label}`} aria-pressed={enabled}
      >{enabled ? '\u2713' : ''}</button>
      <span style={{ color: enabled ? C.tx : C.txD, fontSize: 12, fontFamily: mono, flex: 1,
        textDecoration: enabled ? 'none' : 'line-through' }}>{label}</span>
      <input
        aria-label={`${label} material cost`}
        type="number"
        value={value ?? ''}
        onChange={e => onChange(parseFloat(e.target.value) || 0)}
        disabled={!enabled}
        step={100}
        style={{
          width: 80, padding: '3px 6px', borderRadius: 3,
          border: `1px solid ${C.brd}`,
          backgroundColor: enabled ? C.card2 : C.bg, color: enabled ? C.txB : C.txD,
          fontSize: 13, textAlign: 'right', fontFamily: mono, outline: 'none',
          opacity: enabled ? 1 : 0.4,
        }}
      />
      <span style={{ color: C.txD, fontSize: 10, width: 14 }}>$</span>
    </div>
  );
}

export function DetailsTab({ s, set, isMobile = false }) {
  const { fl, wallTile } = deriveGeometry(s);
  const yn = v => v === 'yes';

  const [editor, setEditor] = useState({ mode: 'add', item: EMPTY_CUSTOM_ITEM });
  const [itemError, setItemError] = useState('');
  const updateItem = patch => setEditor(current => ({ ...current, item: { ...current.item, ...patch } }));
  const resetEditor = () => { setEditor({ mode: 'add', item: EMPTY_CUSTOM_ITEM }); setItemError(''); };
  const editItem = item => {
    setItemError('');
    setEditor({ mode: 'edit', item: { ...EMPTY_CUSTOM_ITEM, ...item,
      qty: s.budget_overrides?.[`custom:${item.draftId}`] ?? item.qty,
    } });
  };
  const clearQuantityEdit = draftId => set('budget_overrides', current => {
    const next = { ...current }; delete next[`custom:${draftId}`]; return next;
  });
  const saveItem = event => {
    event.preventDefault();
    const name = editor.item.name.trim();
    if (!name) { setItemError('Enter an item name.'); return; }
    const item = { ...editor.item, name, group: editor.item.group.trim() || EMPTY_CUSTOM_ITEM.group };
    if (editor.mode === 'edit') {
      set('custom_items', items => items.map(current => current.draftId === item.draftId ? item : current));
      // Details edits the effective quantity; an earlier Budget override must not undo it.
      clearQuantityEdit(item.draftId);
    } else {
      const added = { ...item, draftId: crypto.randomUUID() };
      set('custom_items', items => [...items, added]);
    }
    resetEditor();
  };
  const removeItem = draftId => {
    set('custom_items', items => items.filter(item => item.draftId !== draftId));
    clearQuantityEdit(draftId);
    set('budget_removed', current => { const next = { ...current }; delete next[`custom:${draftId}`]; return next; });
    if (editor.mode === 'edit' && editor.item.draftId === draftId) resetEditor();
  };
  const item = editor.item;

  return (
    <div className="form-grid">

      {/* Allowances with toggles */}
      <Box>
        <Label color={C.acc}>Project budget</Label>
        <NumInput label="Target budget (all purchases)" value={s.target_budget} onChange={v => set('target_budget', v)} unit="$" step={100} max={999999} />
        <NumInput label="Customer purchases total" value={s.owner_purchase_cost} onChange={v => set('owner_purchase_cost', v)} unit="$" step={100} max={999999} />
        {s.projectType === 'flooring' && <p className="site-help">Enter flooring product costs and area work in Scope.</p>}
        {s.projectType === 'bathroom' && <>
        <div style={{ color: C.txD, fontSize: 10, marginBottom: 8 }}>
          Checked: HWC buys materials. Unchecked: customer supplies materials. Installation stays in the budget. Enter HWC's purchase cost before markup.
        </div>
        <AllowanceRow label="Bathtub"     value={s.tub_allowance}         onChange={v => set('tub_allowance', v)}
          show={yn(s.new_tub)} enabled={s.include_tub_material !== 'no'} onToggle={v => set('include_tub_material', v ? 'yes' : 'no')} />
        <AllowanceRow label="Shower Trim" value={s.shower_trim_allowance} onChange={v => set('shower_trim_allowance', v)}
          show={yn(s.has_shower_tile) || s.shower_finish === 'panel'} enabled={s.include_shower_trim_material !== 'no'} onToggle={v => set('include_shower_trim_material', v ? 'yes' : 'no')} />
        <AllowanceRow label="Toilet"      value={s.toilet_allowance}      onChange={v => set('toilet_allowance', v)}
          show={yn(s.has_toilet)} enabled={s.include_toilet_material !== 'no'} onToggle={v => set('include_toilet_material', v ? 'yes' : 'no')} />
        <AllowanceRow label="Vanity"      value={s.vanity_allowance}      onChange={v => set('vanity_allowance', v)}
          show={yn(s.has_vanity)} enabled={s.include_vanity_material !== 'no'} onToggle={v => set('include_vanity_material', v ? 'yes' : 'no')} />
        <AllowanceRow label="Accessories" value={s.accessory_allowance}   onChange={v => set('accessory_allowance', v)}
          enabled={s.include_accessory_material !== 'no'} onToggle={v => set('include_accessory_material', v ? 'yes' : 'no')} />
        <AllowanceRow label="Electrical" value={s.electrical_allowance} onChange={v => set('electrical_allowance', v)}
          show={yn(s.new_electrical)} enabled={s.include_electrical_material !== 'no'} onToggle={v => set('include_electrical_material', v ? 'yes' : 'no')} />
        <AllowanceRow label="Panel shower kit" value={s.panel_material_allowance} onChange={v => set('panel_material_allowance', v)}
          show={s.shower_finish === 'panel'} enabled={s.include_shower_material !== 'no'} onToggle={v => set('include_shower_material', v ? 'yes' : 'no')} />
        <AllowanceRow label="Floor covering" value={s.floor_material_allowance} onChange={v => set('floor_material_allowance', v)}
          show={['vinyl', 'marmoleum'].includes(s.floor_finish)} enabled={s.include_floor_material !== 'no'} onToggle={v => set('include_floor_material', v ? 'yes' : 'no')} />
        <AllowanceRow label="Shower door" value={s.shower_door_allowance} onChange={v => set('shower_door_allowance', v)}
          show={s.has_shower_door === 'yes'} enabled={s.include_shower_door_material !== 'no'} onToggle={v => set('include_shower_door_material', v ? 'yes' : 'no')} />
        {yn(s.has_floor_tile) && <button aria-pressed={s.include_floor_material !== 'no'} onClick={() => set('include_floor_material', s.include_floor_material === 'no' ? 'yes' : 'no')}>Floor tile supplied by {s.include_floor_material === 'no' ? 'customer' : 'HWC'}</button>}
        {yn(s.has_shower_tile) && <button aria-pressed={s.include_shower_material !== 'no'} onClick={() => set('include_shower_material', s.include_shower_material === 'no' ? 'yes' : 'no')}>Shower tile supplied by {s.include_shower_material === 'no' ? 'customer' : 'HWC'}</button>}

        <div style={{ marginTop: 8, padding: 8, backgroundColor: C.card2, borderRadius: 4 }}>
          <span style={{ color: C.txD, fontSize: 10 }}>
            Tile allowances auto-calculated from sqft.
            Floor: ${Math.max(400, Math.round(fl * 10)).toLocaleString()} ·
            Shower: ${Math.max(800, Math.round(wallTile * 12)).toLocaleString()}
          </span>
        </div>
        </>}
      </Box>

      {/* Existing custom-item contract: Details edits; assembler prices and maps. */}
      <Box>
        <div className="custom-items">
          <Label color={C.acc}>Additional scope</Label>
          <p>Add work missing from the template. Enter HWC's cost before markup.
            Use Subcontractor and Lump Sum for a complete quote.</p>
          <form aria-label="Custom item" onSubmit={saveItem}>
            <strong>{editor.mode === 'edit' ? 'Edit custom item' : 'Add custom item'}</strong>
            <label>Item name<input required value={item.name} onChange={e => updateItem({ name: e.target.value })} /></label>
            <label>Group<input value={item.group} onChange={e => updateItem({ group: e.target.value })} /></label>
            <div className="custom-fields">
              <label>Cost type<select aria-label="Cost type" value={item.type} onChange={e => updateItem({
                type: e.target.value, trade: null,
                unit: e.target.value === 'Labor' ? 'Hours' : e.target.value === 'Subcontractor' ? 'Lump Sum' : 'Each',
              })}>
                {Object.keys(jtMappings.types).map(type => <option key={type}>{type}</option>)}
              </select></label>
              <label>Cost code<select aria-label="Cost code" value={item.code} onChange={e => updateItem({ code: e.target.value })}>
                {Object.keys(jtMappings.codes).sort().map(code => <option key={code}>{code}</option>)}
              </select></label>
            </div>
            {item.type === 'Labor' && <label>Trade rate<select aria-label="Trade rate" value={item.trade || ''} onChange={e => updateItem({
              trade: e.target.value || null, unit: 'Hours',
              cost: e.target.value ? tradeRate(e.target.value).cost : item.cost,
            })}>
              <option value="">Manual cost (standard markup)</option>
              {Object.keys(tradeRates).map(trade => <option key={trade} value={trade}>{trade.replaceAll('_', ' ')} — ${tradeRate(trade).price.toFixed(2)}/hr price</option>)}
            </select></label>}
            <div className="custom-fields">
              <label>Quantity<input type="number" required min="0.01" step="any" value={item.qty}
                onChange={e => updateItem({ qty: e.target.value === '' ? '' : Number(e.target.value) })} /></label>
              <label>Unit<select aria-label="Unit" value={item.unit} disabled={item.type === 'Labor'} onChange={e => updateItem({ unit: e.target.value })}>
                {Object.keys(jtMappings.units).map(unit => <option key={unit}>{unit}</option>)}
              </select></label>
            </div>
            <label>Unit cost<input type="number" min="0" step="0.01" value={item.cost || ''} disabled={!!item.trade}
              onChange={e => updateItem({ cost: Number(e.target.value) })} /></label>
            <p>{item.trade ? 'The selected trade supplies the hourly cost and selling rate.' : 'The standard material markup applies to this cost.'}
              {' '}Leave cost blank to flag it for review. Unpriced work blocks sending.</p>
            {itemError && <p role="alert">{itemError}</p>}
            <div className="custom-actions">
              <button className="custom-save" type="submit">{editor.mode === 'edit' ? 'Save item' : 'Add item'}</button>
              {editor.mode === 'edit' && <button type="button" onClick={resetEditor}>Cancel edit</button>}
            </div>
          </form>
          {(s.custom_items || []).map(ci => (
            <div key={ci.draftId} className="custom-saved">
              <strong>{ci.name}</strong>
              <span>{s.budget_overrides?.[`custom:${ci.draftId}`] ?? ci.qty} {ci.unit || 'Each'} · ${ci.cost || 0} cost/unit · {ci.type || 'Materials'}</span>
              {s.budget_removed?.[`custom:${ci.draftId}`] && <span>Excluded from budget. Restore removed items in Budget to include it.</span>}
              {!ci.cost && <span>Cost needed before sending.</span>}
              <div className="custom-actions">
                <button type="button" aria-label={`Edit ${ci.name}`} onClick={() => editItem(ci)}>Edit</button>
                <button type="button" aria-label={`Delete ${ci.name}`} onClick={() => removeItem(ci.draftId)}>Delete</button>
              </div>
            </div>
          ))}
        </div>
      </Box>

      {/* Trade Rate Reference */}
      <Box style={{ gridColumn: '1/-1' }}>
        <Label>Trade Labor Rates (reference)</Label>
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
