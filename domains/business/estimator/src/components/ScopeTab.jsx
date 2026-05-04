import { C, mono } from '../styles/theme.js';
import { Box, Label, Divider } from './Section.jsx';
import { NumInput } from './NumInput.jsx';
import { Select } from './Select.jsx';
import { JobSelector } from './JobSelector.jsx';
import { deriveGeometry, deriveDeckGeometry } from '../engine/assembler.js';
import templates from '../data/templates.json';

function PillToggle({ label, value, onChange }) {
  const on = value === 'yes';
  return (
    <button
      onClick={() => onChange(on ? 'no' : 'yes')}
      style={{
        padding: '6px 12px', borderRadius: 20, border: 'none', cursor: 'pointer',
        backgroundColor: on ? C.acc : C.card2,
        color: on ? C.bg : C.txD,
        fontSize: 11, fontWeight: 600, fontFamily: mono,
        transition: 'all 0.15s',
      }}
    >{label}</button>
  );
}

function DerivedStat({ label, value, unit }) {
  return (
    <div style={{ textAlign: 'center' }}>
      <span style={{ color: C.txD, fontSize: 9, textTransform: 'uppercase' }}>{label}</span><br />
      <span style={{ color: C.txB, fontSize: 13, fontWeight: 600 }}>{value}</span>
      <span style={{ color: C.txD, fontSize: 10 }}> {unit}</span>
    </div>
  );
}

export function ScopeTab({ s, set, onAssemble, isMobile = false }) {
  const { fl, perim, wallTile, panTile, curbTile, paintSqft } = deriveGeometry(s);
  const isDeck = s.job_type === 'Deck';

  return (
    <div style={{ display: 'grid', gridTemplateColumns: isMobile ? '1fr' : '1fr 1fr', gap: isMobile ? 10 : 14 }}>

      {/* Job Selection */}
      <div style={{ gridColumn: '1/-1' }}>
        <JobSelector s={s} set={set} />
      </div>

      {/* Job Type Selector */}
      <div style={{ gridColumn: '1/-1' }}>
        <Box>
          <Label color={C.acc}>Project Type</Label>
          <Select label="Type" value={s.job_type || 'Bathroom'} onChange={v => set('job_type', v)} options={[
            { v: 'Bathroom', l: 'Bathroom' },
            { v: 'Deck', l: 'Deck' },
          ]} />
        </Box>
      </div>

      {/* Template Selector */}
      {templates.length > 0 && (() => {
        const jobType = (s.job_type || 'Bathroom').toLowerCase();
        const filtered = templates.filter(t => t.project_type === jobType);
        if (filtered.length === 0) return null;
        return (
          <div style={{ gridColumn: '1/-1' }}>
            <Box>
              <Label color={C.teal}>Load Template</Label>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, padding: '4px 0' }}>
                {filtered.map(t => (
                  <button key={t.id || t.name}
                    onClick={() => {
                      const keep = ['mode','customerId','customerName','locationId','jobId','jobNumber','jobName','address',
                        'newCustomerName','newCustomerPhone','newCustomerEmail','newCustomerStreet','newCustomerCity','newCustomerState','newCustomerZip'];
                      const preserved = {};
                      keep.forEach(k => { if (s[k]) preserved[k] = s[k]; });
                      const ts = typeof t.state === 'string' ? JSON.parse(t.state) : t.state;
                      Object.entries(ts).forEach(([k, v]) => set(k, v));
                      Object.entries(preserved).forEach(([k, v]) => set(k, v));
                    }}
                    title={t.description || ''}
                    style={{
                      padding: '6px 12px', borderRadius: 20, border: `1px solid ${C.brd}`,
                      cursor: 'pointer', backgroundColor: C.card2, color: C.txB,
                      fontSize: 11, fontWeight: 500, fontFamily: mono,
                      transition: 'all 0.15s',
                    }}
                  >
                    {t.name}
                  </button>
                ))}
              </div>
            </Box>
          </div>
        );
      })()}

      {/* ── DECK FORM ──────────────────────────────────────────────────── */}
      {isDeck && (() => {
        const dg = deriveDeckGeometry(s);
        return (
          <>
            <Box>
              <Label color={C.blu}>Deck Dimensions</Label>
              <NumInput label="Length" value={s.deck_length_ft} onChange={v => set('deck_length_ft', v)} unit="ft" step={1} />
              <NumInput label="Width" value={s.deck_width_ft} onChange={v => set('deck_width_ft', v)} unit="ft" step={1} />
              <NumInput label="Height" value={s.deck_height_ft} onChange={v => set('deck_height_ft', v)} unit="ft" step={0.5} />
              <NumInput label="Joist Spacing" value={s.joist_spacing_in} onChange={v => set('joist_spacing_in', v)} unit="in" step={4} />

              <div style={{ marginTop: 10, padding: 10, backgroundColor: C.card2, borderRadius: 5,
                display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
                <DerivedStat label="Deck Area" value={dg.deckSqft.toFixed(0)} unit="sqft" />
                <DerivedStat label="Perimeter" value={dg.perimeter.toFixed(0)} unit="lf" />
                <DerivedStat label="Joists" value={dg.joistCount.toString()} unit="ea" />
              </div>
            </Box>

            <Box>
              <Label color={C.pur}>Stairs & Railing</Label>
              <NumInput label="Stair Treads" value={s.stair_tread_count} onChange={v => set('stair_tread_count', v)} unit="ea" step={1} min={0} />
              <NumInput label="Stringers" value={s.stair_stringer_count} onChange={v => set('stair_stringer_count', v)} unit="ea" step={1} min={2} />
              <NumInput label="Stair Width" value={s.stair_width_ft} onChange={v => set('stair_width_ft', v)} unit="ft" step={0.5} />
              <NumInput label="Railing" value={s.railing_lf} onChange={v => set('railing_lf', v)} unit="lf" step={1} min={0} />
            </Box>

            <Box>
              <Label color={C.red}>Scope</Label>
              <Select label="Project" value={s.project_scope} onChange={v => set('project_scope', v)} options={[
                { v: 'new_build', l: 'New Build' },
                { v: 'full_rebuild', l: 'Full Rebuild' },
                { v: 'partial_rebuild', l: 'Partial Rebuild (keep frame)' },
                { v: 'repair', l: 'Repair' },
              ]} />
              <Select label="Decking" value={s.decking_material} onChange={v => set('decking_material', v)} options={[
                { v: 'pt', l: 'Pressure-Treated' },
                { v: 'cedar', l: 'Western Red Cedar' },
                { v: 'redwood', l: 'Redwood' },
                { v: 'composite_mid', l: 'Composite (Trex Enhance)' },
                { v: 'composite_premium', l: 'Composite Premium (TimberTech)' },
              ]} />
              <Select label="Railing" value={s.railing_type} onChange={v => set('railing_type', v)} options={[
                { v: 'no', l: 'None' },
                { v: 'wood', l: 'Wood' },
                { v: 'composite', l: 'Composite' },
                { v: 'metal_cable', l: 'Metal / Cable' },
                { v: 'glass', l: 'Glass Panel' },
              ]} />
            </Box>
          </>
        );
      })()}

      {/* ── BATHROOM FORM ──────────────────────────────────────────────── */}
      {!isDeck && <>
      <Box>
        <Label color={C.blu}>Room Measurements</Label>
        <NumInput label="Room Length"  value={s.bathroom_length_ft} onChange={v => set('bathroom_length_ft', v)} unit="ft" step={0.25} />
        <NumInput label="Room Width"   value={s.bathroom_width_ft}  onChange={v => set('bathroom_width_ft',  v)} unit="ft" step={0.25} />
        <NumInput label="Wall Height"  value={s.wall_height_ft}     onChange={v => set('wall_height_ft',     v)} unit="ft" step={0.5}  />
        <NumInput label="Wall Repair"  value={s.bathroom_wall_repair_sqft} onChange={v => set('bathroom_wall_repair_sqft', v)} unit="sf" step={4} />

        <div style={{ marginTop: 10, padding: 10, backgroundColor: C.card2, borderRadius: 5,
          display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
          <DerivedStat label="Floor" value={fl.toFixed(0)} unit="sqft" />
          <DerivedStat label="Paint Area" value={paintSqft.toFixed(0)} unit="sqft" />
          <DerivedStat label="Perimeter" value={perim.toFixed(0)} unit="lf" />
        </div>
      </Box>

      {/* Shower Measurements */}
      <Box>
        <Label color={C.pur}>Shower Measurements</Label>
        <NumInput label="Tile Height"  value={s.shower_wall_height_ft}  onChange={v => set('shower_wall_height_ft',  v)} unit="ft" step={0.5} />
        <NumInput label="Wall 1 Width" value={s.shower_wall_1_width_ft} onChange={v => set('shower_wall_1_width_ft', v)} unit="ft" step={0.25} />
        <NumInput label="Wall 2 Width" value={s.shower_wall_2_width_ft} onChange={v => set('shower_wall_2_width_ft', v)} unit="ft" step={0.25} />
        <NumInput label="Wall 3 Width" value={s.shower_wall_3_width_ft} onChange={v => set('shower_wall_3_width_ft', v)} unit="ft" step={0.25} />
        <NumInput label="Wall 4 Width" value={s.shower_wall_4_width_ft} onChange={v => set('shower_wall_4_width_ft', v)} unit="ft" step={0.25} min={0} />
        <NumInput label="Pan Width"    value={s.shower_pan_width_ft}    onChange={v => set('shower_pan_width_ft',    v)} unit="ft" step={0.25} />
        <NumInput label="Pan Length"   value={s.shower_pan_length_ft}   onChange={v => set('shower_pan_length_ft',   v)} unit="ft" step={0.25} />
        <NumInput label="Curb Length"  value={s.shower_curb_length_ft}  onChange={v => set('shower_curb_length_ft',  v)} unit="ft" step={0.25} />
        <NumInput label="Curb Width"   value={s.shower_curb_width_in}   onChange={v => set('shower_curb_width_in',   v)} unit="in" step={1} />
        <NumInput label="Curb Height"  value={s.shower_curb_height_in}  onChange={v => set('shower_curb_height_in',  v)} unit="in" step={1} />

        <div style={{ marginTop: 10, padding: 10, backgroundColor: C.card2, borderRadius: 5,
          display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
          <DerivedStat label="Wall Tile" value={wallTile.toFixed(0)} unit="sqft" />
          <DerivedStat label="Pan" value={panTile.toFixed(0)} unit="sqft" />
          <DerivedStat label="Curb" value={curbTile.toFixed(0)} unit="sqft" />
        </div>
      </Box>

      {/* Demo Scope & Niches */}
      <Box>
        <Label color={C.red}>Demo Scope</Label>
        <Select label="Scope" value={s.demo_scope} onChange={v => set('demo_scope', v)} options={[
          { v: 'shower_only',       l: 'Shower Only' },
          { v: 'shower_and_floors', l: 'Shower + Floors' },
          { v: 'full_gut',          l: 'Full Gut' },
        ]} />

        <Divider />
        <Label color={C.teal}>Shower Niches</Label>
        <Select label="Niches" value={s.shower_niches} onChange={v => set('shower_niches', v)} options={[
          { v: '0', l: 'None' },
          { v: '1', l: '1 Niche' },
          { v: '2', l: '2 Niches' },
          { v: '3', l: '3 Niches' },
        ]} />
      </Box>

      {/* Feature Toggles */}
      <Box>
        <Label color={C.acc}>Feature Toggles</Label>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, padding: '4px 0' }}>
          <PillToggle label="Shower Tile"  value={s.has_shower_tile}  onChange={v => set('has_shower_tile',  v)} />
          <PillToggle label="Floor Tile"   value={s.has_floor_tile}   onChange={v => set('has_floor_tile',   v)} />
          <PillToggle label="Accent Tile"  value={s.has_accent_tile}  onChange={v => set('has_accent_tile',  v)} />
          <PillToggle label="Paint"        value={s.has_paint}        onChange={v => set('has_paint',        v)} />
          <PillToggle label="Vanity"       value={s.has_vanity}       onChange={v => set('has_vanity',       v)} />
          <PillToggle label="Mirror"       value={s.has_mirror}       onChange={v => set('has_mirror',       v)} />
          <PillToggle label="New Tub"      value={s.new_tub}          onChange={v => set('new_tub',          v)} />
          <PillToggle label="Electrical"   value={s.new_electrical}   onChange={v => set('new_electrical',   v)} />
          <PillToggle label="Exhaust Fan"  value={s.new_fan}          onChange={v => set('new_fan',          v)} />
        </div>
      </Box>
      </>}

      {/* Assemble button */}
      <div style={{ gridColumn: '1/-1', display: 'flex', justifyContent: 'flex-end' }}>
        <button onClick={onAssemble} style={{
          padding: '10px 28px', borderRadius: 6, border: 'none', cursor: 'pointer',
          backgroundColor: C.acc, color: C.bg,
          fontSize: 12, fontWeight: 700, fontFamily: mono,
          letterSpacing: '0.06em', textTransform: 'uppercase',
        }}>
          Assemble Estimate
        </button>
      </div>
    </div>
  );
}
