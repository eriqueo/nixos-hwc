import { C, mono } from '../styles/theme.js';
import { Box, Label, Divider } from './Section.jsx';
import { NumInput } from './NumInput.jsx';
import { Select } from './Select.jsx';
import { JobSelector } from './JobSelector.jsx';
import { deriveGeometry } from '../engine/assembler.js';

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

  return (
    <div style={{ display: 'grid', gridTemplateColumns: isMobile ? '1fr' : '1fr 1fr', gap: isMobile ? 10 : 14 }}>

      {/* Job Selection */}
      <div style={{ gridColumn: '1/-1' }}>
        <JobSelector s={s} set={set} />
      </div>

      {/* Room Measurements */}
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
