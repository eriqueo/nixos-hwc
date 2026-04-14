import { C, mono } from '../styles/theme.js';
import { Box, Label, Divider } from './Section.jsx';
import { Toggle } from './Toggle.jsx';
import { NumInput } from './NumInput.jsx';
import { Select } from './Select.jsx';
import { JobSelector } from './JobSelector.jsx';
import { deriveGeometry } from '../engine/assembler.js';

export function ScopeTab({ s, set, onAssemble, isMobile = false }) {
  const { fl, perim, wallTile } = deriveGeometry(s);

  return (
    <div style={{ display: 'grid', gridTemplateColumns: isMobile ? '1fr' : '1fr 1fr', gap: isMobile ? 10 : 14 }}>

      {/* Job Selection - spans full width */}
      <div style={{ gridColumn: '1/-1' }}>
        <JobSelector s={s} set={set} />
      </div>

      {/* Room Measurements */}
      <Box>
        <Label color={C.blu}>Room Measurements</Label>
        <NumInput label="Length"      value={s.room_length} onChange={v => set('room_length', v)} unit="ft" step={0.25} />
        <NumInput label="Width"       value={s.room_width}  onChange={v => set('room_width',  v)} unit="ft" step={0.25} />
        <NumInput label="Wall Height" value={s.wall_height} onChange={v => set('wall_height', v)} unit="ft" step={0.5}  />
        <NumInput label="Tile Height" value={s.tile_height} onChange={v => set('tile_height', v)} unit="ft" step={0.5}  />
        <div style={{ marginTop: 10, padding: 10, backgroundColor: C.card2, borderRadius: 5,
          display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
          <div><span style={{ color: C.txD, fontSize: 10 }}>Floor</span><br />
            <span style={{ color: C.txB, fontSize: 13, fontWeight: 600 }}>{fl.toFixed(0)} sqft</span></div>
          <div><span style={{ color: C.txD, fontSize: 10 }}>Wall Tile</span><br />
            <span style={{ color: C.txB, fontSize: 13, fontWeight: 600 }}>{wallTile.toFixed(0)} sqft</span></div>
          <div><span style={{ color: C.txD, fontSize: 10 }}>Perimeter</span><br />
            <span style={{ color: C.txB, fontSize: 13, fontWeight: 600 }}>{perim.toFixed(0)} lf</span></div>
        </div>
      </Box>

      {/* Demo & Plumbing */}
      <Box>
        <Label color={C.red}>Demo & Preconstruction</Label>
        <Select label="Demo Scope" value={s.demo_scope} onChange={v => set('demo_scope', v)} options={[
          { v: 'full_gut',     l: 'Full Gut' },
          { v: 'tile_only',    l: 'Tile Only' },
          { v: 'fixture_only', l: 'Fixture Only' },
          { v: 'none',         l: 'None' },
        ]} />
        <Toggle label="Permit Required" value={s.permit_required} onChange={v => set('permit_required', v)} />

        <Divider />
        <Label color={C.blu}>Plumbing Features</Label>
        <Toggle label="Has Bathtub" value={s.has_tub}    onChange={v => set('has_tub',    v)} />
        <Toggle label="Has Shower"  value={s.has_shower} onChange={v => set('has_shower', v)} />
        <Select label="Shower Pan" value={s.shower_pan_type} onChange={v => set('shower_pan_type', v)} show={s.has_shower} options={[
          { v: 'tub_combo',   l: 'Tub/Shower Combo' },
          { v: 'schluter_tray', l: 'Schluter Tray' },
          { v: 'mortar_bed',  l: 'Mortar Bed' },
          { v: 'prefab',      l: 'Prefab' },
        ]} />
        <Select label="Head Config" value={s.shower_head_config} onChange={v => set('shower_head_config', v)} show={s.has_shower} options={[
          { v: 'single',       l: 'Single' },
          { v: 'rain',         l: 'Rain' },
          { v: 'rain_handheld',l: 'Rain + Handheld' },
        ]} />
        <Select label="Toilet Type" value={s.toilet_type} onChange={v => set('toilet_type', v)} options={[
          { v: 'standard',   l: 'Standard' },
          { v: 'wall_mount', l: 'Wall Mount' },
        ]} />
        <Toggle label="Plumbing Relocated" value={s.plumbing_moved} onChange={v => set('plumbing_moved', v)} />
      </Box>

      {/* Tilework & Drywall */}
      <Box>
        <Label color={C.pur}>Tilework</Label>
        <Toggle label="Has Niches"  value={s.has_niche}   onChange={v => set('has_niche',   v)} />
        <NumInput label="Niche Count" value={s.niche_count} onChange={v => set('niche_count', v)} show={s.has_niche} step={1} min={0} max={4} />
        <Select label="Tile Complexity" value={s.tile_complexity} onChange={v => set('tile_complexity', v)} options={[
          { v: 'simple',  l: 'Simple (subway, large format)' },
          { v: 'pattern', l: 'Pattern (herringbone, stacked)' },
          { v: 'mosaic',  l: 'Mosaic (penny, hex, custom)' },
        ]} />

        <Divider />
        <Label color={C.pnk}>Drywall</Label>
        <Toggle   label="Drywall Repair Needed" value={s.drywall_repair_needed} onChange={v => set('drywall_repair_needed', v)} />
        <NumInput label="Sheet Count" value={s.drywall_sheets} onChange={v => set('drywall_sheets', v)} show={s.drywall_repair_needed} step={1} min={1} max={12} />
      </Box>

      {/* Electrical, Framing, Finish */}
      <Box>
        <Label color="#e8b84a">Electrical</Label>
        <Toggle label="Electrical Work Needed" value={s.electrical_needed} onChange={v => set('electrical_needed', v)} />
        <Select label="Scope" value={s.electrical_scope} onChange={v => set('electrical_scope', v)} show={s.electrical_needed} options={[
          { v: 'minor',    l: 'Minor (swap fixtures)' },
          { v: 'moderate', l: 'Moderate (add circuits)' },
          { v: 'rewire',   l: 'Rewire' },
        ]} />
        <NumInput label="GFCI Outlets"    value={s.gfci_count}          onChange={v => set('gfci_count',          v)} show={s.electrical_needed} step={1} />
        <NumInput label="Light Fixtures"  value={s.light_fixture_count} onChange={v => set('light_fixture_count', v)} show={s.electrical_needed} step={1} />
        <Toggle   label="Exhaust Fan"     value={s.has_fan}             onChange={v => set('has_fan',             v)} show={s.electrical_needed} />

        <Divider />
        <Label color={C.ylw}>Framing</Label>
        <NumInput label="General Framing Hours" value={s.framing_hours}   onChange={v => set('framing_hours',   v)} unit="hrs" step={1} />
        <Toggle   label="Pocket Door"           value={s.has_pocket_door} onChange={v => set('has_pocket_door', v)} />

        <Divider />
        <Label color={C.teal}>Finish Carpentry</Label>
        <Select label="Vanity Size" value={s.vanity_size} onChange={v => set('vanity_size', v)} options={[
          { v: 'single', l: 'Single (24-36")' },
          { v: 'double', l: 'Double (48-72")' },
        ]} />
        <Toggle   label="Mirror Install"    value={s.has_mirror}     onChange={v => set('has_mirror',     v)} />
        <Toggle   label="Trim & Baseboard"  value={s.has_trim_work}  onChange={v => set('has_trim_work',  v)} />
        <NumInput label="Accessory Count"   value={s.accessory_count} onChange={v => set('accessory_count', v)} step={1} />
      </Box>

      {/* Assemble button */}
      <div style={{ gridColumn: '1/-1', display: 'flex', justifyContent: 'flex-end' }}>
        <button onClick={onAssemble} style={{
          padding: '10px 28px', borderRadius: 6, border: 'none', cursor: 'pointer',
          backgroundColor: C.acc, color: C.bg,
          fontSize: 12, fontWeight: 700, fontFamily: mono,
          letterSpacing: '0.06em', textTransform: 'uppercase',
        }}>
          Assemble Estimate →
        </button>
      </div>
    </div>
  );
}
