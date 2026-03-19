import { useState, useMemo, useCallback, useEffect } from "react";

// ============================================================
// REFERENCE DATA (from JT)
// ============================================================
const JT = {
  codes: {"0100":"22Nm3uGRAMmH","0200":"22Nm3uGRAMmJ","0600":"22Nm3uGRAMmN","1000":"22Nm3uGRAMmS","1100":"22Nm3uGRAMmT","1400":"22Nm3uGRAMmW","1800":"22Nm3uGRAMma","1900":"22Nm3uGRAMmb","2100":"22Nm3uGRAMmd","2300":"22Nm3uGRAMmf","2400":"22Nm3uGRAMmg","3000":"22Nm3uGRAMmn","3100":"22Nm3uGRAMmp"},
  types: {"Admin":"22PJuNqewZmV","Labor":"22Nm3uGRAMmq","Materials":"22Nm3uGRAMmr","Other":"22Nm3uGRAMmt","Selections":"22PQ4KZExZjP","Subcontractor":"22Nm3uGRAMms"},
  units: {"Hours":"22Nm3uGRAMm9","Each":"22Nm3uGRAMm7","Gallons":"22Nm3uGRAMm8","Lump Sum":"22Nm3uGRAMmB","Square Feet":"22Nm3uGRAMmD","Linear Feet":"22Nm3uGRAMmA"}
};

// Per-trade labor rates (wage × burden = cost, cost × markup = price)
const TRADE_RATES = {
  planning: { wage: 35, burden: 1.35, markup: 1.43 },
  demo: { wage: 35, burden: 1.35, markup: 2.0 },
  framing: { wage: 38, burden: 1.35, markup: 1.85 },
  plumbing: { wage: 42, burden: 1.35, markup: 1.75 },
  electrical: { wage: 45, burden: 1.35, markup: 1.75 },
  tiling: { wage: 45, burden: 1.35, markup: 2.0 },
  drywall: { wage: 35, burden: 1.35, markup: 2.0 },
  painting: { wage: 35, burden: 1.35, markup: 2.0 },
  cabinetry: { wage: 38, burden: 1.35, markup: 1.85 },
  waterproofing: { wage: 42, burden: 1.35, markup: 1.75 },
};

function tradeRate(trade) {
  const r = TRADE_RATES[trade] || TRADE_RATES.planning;
  const cost = r.wage * r.burden;
  return { cost: Math.round(cost * 100) / 100, price: Math.round(cost * r.markup * 100) / 100 };
}

// Material markup: ~30% target margin = 1.4286x
const MAT_MARKUP = 1.4286;
function matPrice(cost) { return Math.round(cost * MAT_MARKUP * 100) / 100; }

// ============================================================
// CATALOG — organized by phase, condition-triggered
// ============================================================
function buildCatalog(s) {
  const fl = s.room_length * s.room_width;
  const perim = 2 * (s.room_length + s.room_width);
  const wallTile = s.tile_height > 0 ? perim * s.tile_height : 0;
  const items = [];
  let id = 0;
  const add = (name, group, code, type, unit, qty, cost, trade, trigger) => {
    if (!trigger) return;
    let uc, up;
    if (type === "Labor") { const r = tradeRate(trade); uc = r.cost; up = r.price; }
    else if (type === "Other") { uc = cost; up = matPrice(cost); }
    else { uc = cost; up = matPrice(cost); }
    items.push({ id: ++id, name, group, code, type, unit, qty: Math.ceil(qty * 100) / 100, uc, up, extC: Math.round(uc * qty * 100)/100, extP: Math.round(up * qty * 100)/100, trade });
  };

  // PRECONSTRUCTION
  add("Admin | Planning | Site Walkthrough", "Preconstruction", "0100", "Labor", "Hours", 2, 0, "planning", true);
  add("Admin | Planning | Remodeling Permit", "Preconstruction", "0100", "Other", "Each", 1, 350, null, s.permit_required);

  // DEMO
  if (s.demo_scope !== "none") {
    add("Labor | Demo | Install Floor Protection", "Demo > Labor", "0200", "Labor", "Hours", 3, 0, "demo", true);
    add("Labor | Demo | Floor Tile", "Demo > Labor", "0200", "Labor", "Hours", Math.max(4, fl * 0.12), 0, "demo", s.demo_scope === "full_gut" || s.demo_scope === "tile_only");
    add("Labor | Demo | Shower Surround", "Demo > Labor", "0200", "Labor", "Hours", Math.max(4, wallTile * 0.04), 0, "demo", s.has_shower);
    add("Labor | Demo | Bathtub Surround", "Demo > Labor", "0200", "Labor", "Hours", 6, 0, "demo", s.has_tub && s.demo_scope === "full_gut");
    add("Material | Protection | Floor Protection Roll", "Demo > Materials", "0100", "Materials", "Each", 1, 35, null, true);
    add("Material | Protection | Sheeting Tape", "Demo > Materials", "0100", "Materials", "Each", 2, 13, null, true);
    add("Material | Protection | Dust Control Sheeting", "Demo > Materials", "0100", "Materials", "Each", 1, 20, null, true);
    add("Material | Protection | Trash Bags", "Demo > Materials", "0100", "Materials", "Each", fl > 80 ? 2 : 1, 27, null, true);
    add("Material | Demo | Dump Trailer", "Demo > Materials", "0200", "Other", "Each", 1, 200, null, true);
  }

  // FRAMING
  add("Labor | Framing | General", "Rough Carpentry > Labor", "0600", "Labor", "Hours", s.framing_hours, 0, "framing", s.framing_hours > 0);
  add("Labor | Framing | Niche Blocking", "Rough Carpentry > Labor", "0600", "Labor", "Hours", s.niche_count * 2, 0, "framing", s.has_niche && s.niche_count > 0);
  add("Labor | Framing | Install Tub", "Rough Carpentry > Labor", "0600", "Labor", "Hours", 5, 0, "framing", s.has_tub);
  add("Labor | Framing | Pocket Door", "Rough Carpentry > Labor", "0600", "Labor", "Hours", 6, 0, "framing", s.has_pocket_door);
  add("Material | Framing | Screws 3\" Exterior 5lb", "Rough Carpentry > Materials", "3100", "Materials", "Each", 1, 32.98, null, true);
  add("Material | Framing | 2x4x8 KD SPF", "Rough Carpentry > Materials", "0600", "Materials", "Each", Math.max(2, Math.ceil(perim / 8)), 13, null, true);
  add("Material | Framing | Plywood 3/4\" ACX", "Rough Carpentry > Materials", "0600", "Materials", "Each", 1, 95, null, true);
  add("Material | Framing | Pocket Door Frame Kit", "Rough Carpentry > Materials", "0600", "Materials", "Each", 1, 362.85, null, s.has_pocket_door);

  // PLUMBING
  if (s.has_shower) {
    add("Labor | Plumbing | Install Mixer Valve", "Plumbing > Shower Labor", "1100", "Labor", "Hours", 4, 0, "plumbing", true);
    add("Labor | Plumbing | Install Shower Trim", "Plumbing > Shower Labor", "1100", "Labor", "Hours", 2, 0, "plumbing", true);
    add("Labor | Plumbing | Run Showerhead Copper", "Plumbing > Shower Labor", "1100", "Labor", "Hours", s.shower_head_config === "rain_handheld" ? 6 : 4, 0, "plumbing", true);
    add("Material | Plumbing | Posi-Temp Rough-In Valve", "Plumbing > Materials", "1100", "Materials", "Each", 1, 135, null, true);
    add("Material | Plumbing | 1/2\" Copper Pipe", "Plumbing > Materials", "1100", "Materials", "Each", s.shower_head_config === "rain_handheld" ? 3 : 2, 8, null, true);
    add("Material | Plumbing | Copper Fittings", "Plumbing > Materials", "1100", "Materials", "Lump Sum", 1, 50, null, true);
  }
  if (s.has_tub) {
    add("Labor | Plumbing | Tub Drain Hookup", "Plumbing > Tub Labor", "1100", "Labor", "Hours", 4, 0, "plumbing", true);
  }
  add("Labor | Plumbing | Install Toilet", "Plumbing > Toilet Labor", "1100", "Labor", "Hours", s.toilet_type === "wall_mount" ? 8 : 2, 0, "plumbing", true);
  if (s.plumbing_moved) {
    add("Material | Plumbing | 2\" PVC Drain Pipe 10'", "Plumbing > Materials", "1100", "Materials", "Each", 1, 17, null, true);
  }
  add("Material | Plumbing | PVC Fittings", "Plumbing > Materials", "1100", "Materials", "Each", 6, 3, null, true);

  // ELECTRICAL
  if (s.electrical_needed) {
    add("Labor | Electrical | General", "Electrical > Labor", "1000", "Labor", "Hours", s.electrical_scope === "moderate" ? 8 : s.electrical_scope === "rewire" ? 16 : 4, 0, "electrical", true);
    add("Labor | Electrical | GFCI Install", "Electrical > Labor", "1000", "Labor", "Hours", s.gfci_count * 1.5, 0, "electrical", s.gfci_count > 0);
    add("Material | Electrical | GFCI Outlet", "Electrical > Materials", "1000", "Materials", "Each", s.gfci_count, 25, null, s.gfci_count > 0);
    add("Labor | Electrical | Light Fixture Install", "Electrical > Labor", "1000", "Labor", "Hours", s.light_fixture_count * 1, 0, "electrical", s.light_fixture_count > 0);
    add("Labor | Electrical | Exhaust Fan", "Electrical > Labor", "1000", "Labor", "Hours", 3, 0, "electrical", s.has_fan);
  }

  // WATERPROOFING (separate from tile)
  if (s.has_shower) {
    const wpSqft = wallTile + fl * 0.3;
    add("Labor | Waterproofing | Membrane Application", "Waterproofing > Labor", "1800", "Labor", "Hours", Math.max(6, wpSqft * 0.04), 0, "waterproofing", true);
  }

  // TILEWORK
  add("Labor | Tile | Floor Installation", "Tilework > Floor Tile Labor", "1800", "Labor", "Hours", Math.max(8, fl * (s.tile_complexity === "mosaic" ? 0.4 : s.tile_complexity === "pattern" ? 0.3 : 0.22)), 0, "tiling", true);
  if (s.has_shower) {
    add("Labor | Tile | Shower Installation", "Tilework > Shower Tile Labor", "1800", "Labor", "Hours", Math.max(12, wallTile * (s.tile_complexity === "mosaic" ? 0.25 : 0.18)), 0, "tiling", true);
    add("Labor | Tile | Niche Installation", "Tilework > Shower Tile Labor", "1800", "Labor", "Hours", s.niche_count * 4, 0, "tiling", s.has_niche && s.niche_count > 0);
  }
  if (s.shower_pan_type === "schluter_tray") {
    add("Material | Tile | Schluter Shower Pan", "Tilework > Materials", "1800", "Materials", "Each", 1, 178, null, true);
    add("Material | Tile | Schluter Drain", "Tilework > Materials", "1800", "Materials", "Each", 1, 99, null, true);
  }
  add("Material | Tile | Waterproof Backer Board 1/2\" 4x8", "Tilework > Materials", "1800", "Materials", "Each", Math.max(2, Math.ceil(wallTile / 32)), 98.99, null, s.has_shower);
  add("Material | Tile | Schluter Banding 16'", "Tilework > Materials", "1800", "Materials", "Each", Math.max(1, Math.ceil(perim / 16)), 20.75, null, true);
  add("Material | Tile | Permacolor Grout", "Tilework > Materials", "1800", "Materials", "Each", 1, 95, null, true);
  add("Material | Tile | Schluter 1/4\" Aluminum Trim", "Tilework > Materials", "1800", "Materials", "Each", Math.max(2, Math.ceil(perim / 8)), 24, null, true);
  add("Material | Tile | Thinset Mortar 50#", "Tilework > Materials", "1800", "Materials", "Each", Math.max(2, Math.ceil((fl + wallTile) / 80)), 28.5, null, true);
  add("Material | Tile | Silicone Sealant", "Tilework > Materials", "1800", "Materials", "Each", Math.max(2, Math.ceil(perim / 12)), 22, null, true);
  add("Material | Tile | Grout Sealer", "Tilework > Materials", "1800", "Materials", "Each", 1, 20, null, true);

  // DRYWALL
  if (s.drywall_repair_needed) {
    add("Labor | Drywall | Remove and Replace", "Drywall > Labor", "1400", "Labor", "Hours", s.drywall_sheets * 1.5, 0, "drywall", true);
    add("Material | Drywall | Drywall 1/2\" 4x8", "Drywall > Materials", "1400", "Materials", "Each", Math.max(1, Math.floor(s.drywall_sheets * 0.6)), 20.48, null, true);
    add("Material | Drywall | Mold Resistant 1/2\" 4x8", "Drywall > Materials", "1400", "Materials", "Each", Math.max(1, Math.ceil(s.drywall_sheets * 0.4)), 19.2, null, true);
    add("Material | Drywall | Mud 4.5 gal", "Drywall > Materials", "1400", "Materials", "Each", 1, 15.48, null, true);
    add("Material | Drywall | Tape Mesh 500ft", "Drywall > Materials", "1400", "Materials", "Each", 1, 11.98, null, true);
    add("Material | Drywall | Screws 1-5/8\" 1lb", "Drywall > Materials", "1400", "Materials", "Each", 1, 7.98, null, s.drywall_sheets <= 3);
    add("Material | Drywall | Screws 1-5/8\" 5lb", "Drywall > Materials", "1400", "Materials", "Each", 1, 25.98, null, s.drywall_sheets > 3);
  }

  // PAINTING
  const paintHrs = (perim * s.wall_height) / 40; // rough: 40sqft/hr base
  add("Labor | Painting | Prep", "Painting > Labor", "2300", "Labor", "Hours", Math.max(4, Math.ceil(paintHrs * 0.3)), 0, "painting", true);
  add("Labor | Painting | Caulking", "Painting > Labor", "2300", "Labor", "Hours", Math.max(2, Math.ceil(paintHrs * 0.15)), 0, "painting", true);
  add("Labor | Painting | Prime Coat", "Painting > Labor", "2300", "Labor", "Hours", Math.max(3, Math.ceil(paintHrs * 0.25)), 0, "painting", true);
  add("Labor | Painting | Finish Coats", "Painting > Labor", "2300", "Labor", "Hours", Math.max(4, Math.ceil(paintHrs * 0.5)), 0, "painting", true);
  const paintGal = Math.max(1, Math.ceil((perim * s.wall_height) / 350));
  add("Material | Painting | BIN Shellac Primer", "Painting > Materials", "2300", "Materials", "Gallons", paintGal, 75, null, true);
  add("Material | Painting | SW Emerald Urethane Semi Gloss", "Painting > Materials", "2300", "Materials", "Each", paintGal, 110, null, true);
  add("Material | Painting | Painters Tape Blue", "Painting > Materials", "2300", "Materials", "Each", Math.max(2, Math.ceil(perim / 12)), 6.98, null, true);
  add("Material | Painting | Caulking", "Painting > Materials", "2300", "Materials", "Each", Math.max(2, Math.ceil(perim / 12)), 11.19, null, true);

  // FINISH CARPENTRY
  add("Labor | Finish Carpentry | Install Vanity", "Finish Carpentry > Labor", "1900", "Labor", "Hours", s.vanity_size === "double" ? 6 : 4, 0, "cabinetry", true);
  add("Labor | Finish Carpentry | Accessories & Hardware", "Finish Carpentry > Labor", "1900", "Labor", "Hours", Math.max(4, s.accessory_count * 0.75), 0, "cabinetry", true);
  add("Labor | Finish Carpentry | Mirror Install", "Finish Carpentry > Labor", "1900", "Labor", "Hours", 2, 0, "cabinetry", s.has_mirror);
  add("Labor | Finish Carpentry | Trim & Base", "Finish Carpentry > Labor", "2100", "Labor", "Hours", Math.max(2, Math.ceil(perim / 6)), 0, "cabinetry", s.has_trim_work);

  // ALLOWANCES
  add("Allowance | Bathtub", "Allowances", "2400", "Materials", "Lump Sum", 1, s.tub_allowance, null, s.has_tub);
  add("Allowance | Shower Trim", "Allowances", "1100", "Materials", "Lump Sum", 1, s.shower_trim_allowance, null, s.has_shower);
  add("Allowance | Shower Tile", "Allowances > Tile", "1800", "Materials", "Lump Sum", 1, Math.max(800, Math.round(wallTile * 12)), null, s.has_shower);
  add("Allowance | Floor Tile", "Allowances > Tile", "1800", "Materials", "Lump Sum", 1, Math.max(400, Math.round(fl * 10)), null, true);
  add("Allowance | Toilet", "Allowances", "2400", "Materials", "Lump Sum", 1, s.toilet_allowance, null, true);
  add("Allowance | Vanity", "Allowances", "3000", "Materials", "Lump Sum", 1, s.vanity_allowance, null, true);
  add("Allowance | Bathroom Accessories", "Allowances", "3000", "Materials", "Lump Sum", 1, s.accessory_allowance, null, true);
  add("Allowance | Electrical", "Allowances", "1000", "Materials", "Lump Sum", 1, 800, null, s.electrical_needed);

  // CUSTOM LINE ITEMS
  if (s.custom_items) {
    s.custom_items.forEach(ci => {
      if (ci.name && ci.qty > 0) add(ci.name, ci.group || "Additional Items", ci.code || "3100", ci.type || "Materials", ci.unit || "Each", ci.qty, ci.cost || 0, ci.trade || null, true);
    });
  }

  return items;
}

// ============================================================
// DEFAULT STATE
// ============================================================
const DEFAULT = {
  // Context
  customer: "", address: "", job_name: "",
  // Measurements
  room_length: 8, room_width: 7, wall_height: 8, tile_height: 6,
  // Core toggles
  demo_scope: "full_gut", permit_required: true,
  has_tub: true, has_shower: true, has_niche: true,
  // Feature params
  niche_count: 2, shower_pan_type: "tub_combo", shower_head_config: "single",
  toilet_type: "standard", vanity_size: "single",
  tile_complexity: "simple",
  // Framing
  framing_hours: 4, has_pocket_door: false,
  // Plumbing
  plumbing_moved: false,
  // Electrical
  electrical_needed: false, electrical_scope: "minor", gfci_count: 1, light_fixture_count: 2, has_fan: true,
  // Drywall
  drywall_repair_needed: true, drywall_sheets: 3,
  // Finish
  has_mirror: true, has_trim_work: true, accessory_count: 5,
  // Allowances
  tub_allowance: 1200, shower_trim_allowance: 1200, toilet_allowance: 1600, vanity_allowance: 2000, accessory_allowance: 1000,
  // Custom
  custom_items: [],
};

// ============================================================
// STYLES
// ============================================================
const C = {
  bg:"#0c0e11",card:"#14171c",card2:"#1a1e25",brd:"#262b33",
  tx:"#9ca3af",txB:"#e2e5ea",txD:"#5a6270",
  acc:"#c9956b",accD:"#a07448",
  grn:"#6bcb77",red:"#ee6b6e",blu:"#5b9bd5",
  pur:"#8b7ec8",pnk:"#c77da3",teal:"#5ec6c0",ylw:"#d4a574",
};
const GC = {"Preconstruction":C.txD,"Demo":C.red,"Rough Carpentry":C.ylw,"Plumbing":C.blu,"Electrical":"#e8b84a","Waterproofing":C.teal,"Tilework":C.pur,"Drywall":C.pnk,"Painting":C.grn,"Finish Carpentry":C.teal,"Allowances":C.acc,"Additional":C.txD};
const mono = "'JetBrains Mono','SF Mono','Fira Code',monospace";

// ============================================================
// SMALL COMPONENTS
// ============================================================
const Box = ({children, style}) => <div style={{backgroundColor:C.card,borderRadius:8,border:`1px solid ${C.brd}`,padding:14,...style}}>{children}</div>;
const Label = ({children,color}) => (
  <div style={{display:"flex",alignItems:"center",gap:7,marginBottom:8}}>
    <div style={{width:3,height:14,borderRadius:2,backgroundColor:color||C.acc}}/>
    <span style={{color:C.txB,fontSize:11,fontWeight:700,letterSpacing:"0.08em",textTransform:"uppercase",fontFamily:mono}}>{children}</span>
  </div>
);
const Tog = ({label,value,onChange,show=true}) => {
  if (!show) return null;
  return (
    <div style={{display:"flex",alignItems:"center",justifyContent:"space-between",padding:"5px 0"}}>
      <span style={{color:C.tx,fontSize:12,fontFamily:mono}}>{label}</span>
      <button onClick={()=>onChange(!value)} style={{width:40,height:22,borderRadius:11,border:"none",cursor:"pointer",position:"relative",backgroundColor:value?C.acc:C.brd,transition:"all 0.15s"}}>
        <div style={{width:16,height:16,borderRadius:8,backgroundColor:"#fff",position:"absolute",top:3,left:value?21:3,transition:"left 0.15s",boxShadow:"0 1px 3px rgba(0,0,0,0.3)"}}/>
      </button>
    </div>
  );
};
const Num = ({label,value,onChange,unit,min=0,max=999,step=1,show=true}) => {
  if (!show) return null;
  return (
    <div style={{display:"flex",alignItems:"center",justifyContent:"space-between",padding:"5px 0"}}>
      <span style={{color:C.tx,fontSize:12,fontFamily:mono}}>{label}</span>
      <div style={{display:"flex",alignItems:"center",gap:4}}>
        <input type="number" value={value||""} onChange={e=>onChange(parseFloat(e.target.value)||0)} min={min} max={max} step={step}
          style={{width:60,padding:"3px 6px",borderRadius:3,border:`1px solid ${C.brd}`,backgroundColor:C.card2,color:C.txB,fontSize:13,textAlign:"right",fontFamily:mono,outline:"none"}}/>
        {unit&&<span style={{color:C.txD,fontSize:10,width:22}}>{unit}</span>}
      </div>
    </div>
  );
};
const Sel = ({label,value,onChange,options,show=true}) => {
  if (!show) return null;
  return (
    <div style={{display:"flex",alignItems:"center",justifyContent:"space-between",padding:"5px 0"}}>
      <span style={{color:C.tx,fontSize:12,fontFamily:mono}}>{label}</span>
      <select value={value} onChange={e=>onChange(e.target.value)} style={{padding:"3px 6px",borderRadius:3,border:`1px solid ${C.brd}`,backgroundColor:C.card2,color:C.txB,fontSize:12,fontFamily:mono,outline:"none",cursor:"pointer"}}>
        {options.map(o=><option key={o.v} value={o.v}>{o.l}</option>)}
      </select>
    </div>
  );
};
const Stat = ({label,value,color}) => (
  <div style={{textAlign:"center"}}>
    <div style={{color:C.txD,fontSize:9,textTransform:"uppercase",letterSpacing:"0.1em"}}>{label}</div>
    <div style={{color:color||C.txB,fontSize:16,fontWeight:700,fontFamily:mono}}>{value}</div>
  </div>
);

// ============================================================
// MAIN APP
// ============================================================
export default function App() {
  const [s, setS] = useState(DEFAULT);
  const [overrides, setOvr] = useState({});
  const [removed, setRemoved] = useState({});
  const [view, setView] = useState("scope");
  const [newItem, setNewItem] = useState({name:"",group:"Additional Items",qty:1,cost:0,type:"Materials",unit:"Each"});
  const [pushMsg, setPushMsg] = useState(null);

  const set = useCallback((k,v) => setS(p=>({...p,[k]:v})),[]);

  const catalog = useMemo(() => buildCatalog(s), [s]);
  const estimate = useMemo(() => {
    return catalog.filter(i => !removed[i.id]).map(i => {
      const qty = overrides[i.id] !== undefined ? overrides[i.id] : i.qty;
      return {...i, qty, extC: Math.round(i.uc*qty*100)/100, extP: Math.round(i.up*qty*100)/100, _edited: overrides[i.id]!==undefined};
    });
  }, [catalog, overrides, removed]);

  const totals = useMemo(() => {
    let cost=0,price=0,items=0,laborHrs=0;
    estimate.forEach(i=>{cost+=i.extC;price+=i.extP;items++;if(i.type==="Labor")laborHrs+=i.qty;});
    return {cost,price,items,laborHrs,margin:price>0?((price-cost)/price*100):0};
  },[estimate]);

  const groups = useMemo(() => {
    const g = {};
    estimate.forEach(i => { if(!g[i.group])g[i.group]=[]; g[i.group].push(i); });
    return g;
  },[estimate]);

  const fl = s.room_length * s.room_width;
  const wallTile = s.tile_height > 0 ? 2*(s.room_length+s.room_width)*s.tile_height : 0;
  const perim = 2*(s.room_length+s.room_width);

  const addCustomItem = () => {
    if (!newItem.name) return;
    set("custom_items", [...(s.custom_items||[]), {...newItem}]);
    setNewItem({name:"",group:"Additional Items",qty:1,cost:0,type:"Materials",unit:"Each"});
  };

  const copyPayload = () => {
    const payload = estimate.map(i => ({
      name:i.name, groupName:i.group, costCodeId:JT.codes[i.code],
      costTypeId:JT.types[i.type], unitId:JT.units[i.unit],
      quantity:i.qty, unitCost:i.uc, unitPrice:i.up
    }));
    navigator.clipboard.writeText(JSON.stringify(payload,null,2));
    setPushMsg("payload"); setTimeout(()=>setPushMsg(null),2500);
  };

  const tabs = [
    {id:"scope",label:"Scope"},
    {id:"details",label:"Details"},
    {id:"estimate",label:`Budget (${totals.items})`}
  ];

  return (
    <div style={{minHeight:"100vh",backgroundColor:C.bg,color:C.tx,fontFamily:mono}}>
      {/* HEADER */}
      <div style={{padding:"16px 20px 0",borderBottom:`1px solid ${C.brd}`}}>
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:12}}>
          <div>
            <span style={{color:C.acc,fontSize:15,fontWeight:800}}>⬡ Heartwood</span>
            <span style={{color:C.txD,fontSize:11,marginLeft:8}}>Estimate Assembler v2</span>
          </div>
          <div style={{display:"flex",gap:16}}>
            <Stat label="Cost" value={`$${Math.round(totals.cost).toLocaleString()}`}/>
            <Stat label="Price" value={`$${Math.round(totals.price).toLocaleString()}`} color={C.acc}/>
            <Stat label="Margin" value={`${totals.margin.toFixed(1)}%`} color={C.grn}/>
            <Stat label="Labor" value={`${Math.round(totals.laborHrs)}h`} color={C.blu}/>
          </div>
        </div>
        <div style={{display:"flex",gap:0}}>
          {tabs.map(t=>(
            <button key={t.id} onClick={()=>setView(t.id)} style={{
              padding:"7px 18px",border:"none",cursor:"pointer",fontSize:11,fontWeight:600,fontFamily:mono,
              letterSpacing:"0.06em",textTransform:"uppercase",transition:"all 0.1s",borderRadius:"4px 4px 0 0",
              backgroundColor:view===t.id?C.card:"transparent",
              color:view===t.id?C.acc:C.txD,
              borderBottom:view===t.id?`2px solid ${C.acc}`:"2px solid transparent"
            }}>{t.label}</button>
          ))}
        </div>
      </div>

      <div style={{padding:16,maxWidth:960,margin:"0 auto"}}>
        {/* ==================== SCOPE TAB ==================== */}
        {view === "scope" && (
          <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:14}}>
            <Box>
              <Label color={C.blu}>Room Measurements</Label>
              <Num label="Length" value={s.room_length} onChange={v=>set("room_length",v)} unit="ft" step={0.25}/>
              <Num label="Width" value={s.room_width} onChange={v=>set("room_width",v)} unit="ft" step={0.25}/>
              <Num label="Wall Height" value={s.wall_height} onChange={v=>set("wall_height",v)} unit="ft" step={0.5}/>
              <Num label="Tile Height" value={s.tile_height} onChange={v=>set("tile_height",v)} unit="ft" step={0.5}/>
              <div style={{marginTop:10,padding:10,backgroundColor:C.card2,borderRadius:5,display:"grid",gridTemplateColumns:"1fr 1fr 1fr",gap:8}}>
                <div><span style={{color:C.txD,fontSize:10}}>Floor</span><br/><span style={{color:C.txB,fontSize:13,fontWeight:600}}>{fl.toFixed(0)} sqft</span></div>
                <div><span style={{color:C.txD,fontSize:10}}>Wall Tile</span><br/><span style={{color:C.txB,fontSize:13,fontWeight:600}}>{wallTile.toFixed(0)} sqft</span></div>
                <div><span style={{color:C.txD,fontSize:10}}>Perimeter</span><br/><span style={{color:C.txB,fontSize:13,fontWeight:600}}>{perim.toFixed(0)} lf</span></div>
              </div>
            </Box>

            <Box>
              <Label color={C.red}>Demo & Preconstruction</Label>
              <Sel label="Demo Scope" value={s.demo_scope} onChange={v=>set("demo_scope",v)}
                options={[{v:"full_gut",l:"Full Gut"},{v:"tile_only",l:"Tile Only"},{v:"fixture_only",l:"Fixture Only"},{v:"none",l:"None"}]}/>
              <Tog label="Permit Required" value={s.permit_required} onChange={v=>set("permit_required",v)}/>

              <div style={{height:1,backgroundColor:C.brd,margin:"10px 0"}}/>
              <Label color={C.blu}>Plumbing Features</Label>
              <Tog label="Has Bathtub" value={s.has_tub} onChange={v=>set("has_tub",v)}/>
              <Tog label="Has Shower" value={s.has_shower} onChange={v=>set("has_shower",v)}/>
              <Sel label="Shower Pan" value={s.shower_pan_type} onChange={v=>set("shower_pan_type",v)} show={s.has_shower}
                options={[{v:"tub_combo",l:"Tub/Shower Combo"},{v:"schluter_tray",l:"Schluter Tray"},{v:"mortar_bed",l:"Mortar Bed"},{v:"prefab",l:"Prefab"}]}/>
              <Sel label="Head Config" value={s.shower_head_config} onChange={v=>set("shower_head_config",v)} show={s.has_shower}
                options={[{v:"single",l:"Single"},{v:"rain",l:"Rain"},{v:"rain_handheld",l:"Rain + Handheld"}]}/>
              <Sel label="Toilet Type" value={s.toilet_type} onChange={v=>set("toilet_type",v)}
                options={[{v:"standard",l:"Standard"},{v:"wall_mount",l:"Wall Mount"}]}/>
              <Tog label="Plumbing Relocated" value={s.plumbing_moved} onChange={v=>set("plumbing_moved",v)}/>
            </Box>

            <Box>
              <Label color={C.pur}>Tilework</Label>
              <Tog label="Has Niches" value={s.has_niche} onChange={v=>set("has_niche",v)}/>
              <Num label="Niche Count" value={s.niche_count} onChange={v=>set("niche_count",v)} show={s.has_niche} step={1} min={0} max={4}/>
              <Sel label="Tile Complexity" value={s.tile_complexity} onChange={v=>set("tile_complexity",v)}
                options={[{v:"simple",l:"Simple (subway, large format)"},{v:"pattern",l:"Pattern (herringbone, stacked)"},{v:"mosaic",l:"Mosaic (penny, hex, custom)"}]}/>

              <div style={{height:1,backgroundColor:C.brd,margin:"10px 0"}}/>
              <Label color={C.pnk}>Drywall</Label>
              <Tog label="Drywall Repair Needed" value={s.drywall_repair_needed} onChange={v=>set("drywall_repair_needed",v)}/>
              <Num label="Sheet Count" value={s.drywall_sheets} onChange={v=>set("drywall_sheets",v)} show={s.drywall_repair_needed} step={1} min={1} max={12}/>
            </Box>

            <Box>
              <Label color="#e8b84a">Electrical</Label>
              <Tog label="Electrical Work Needed" value={s.electrical_needed} onChange={v=>set("electrical_needed",v)}/>
              <Sel label="Scope" value={s.electrical_scope} onChange={v=>set("electrical_scope",v)} show={s.electrical_needed}
                options={[{v:"minor",l:"Minor (swap fixtures)"},{v:"moderate",l:"Moderate (add circuits)"},{v:"rewire",l:"Rewire"}]}/>
              <Num label="GFCI Outlets" value={s.gfci_count} onChange={v=>set("gfci_count",v)} show={s.electrical_needed} step={1}/>
              <Num label="Light Fixtures" value={s.light_fixture_count} onChange={v=>set("light_fixture_count",v)} show={s.electrical_needed} step={1}/>
              <Tog label="Exhaust Fan" value={s.has_fan} onChange={v=>set("has_fan",v)} show={s.electrical_needed}/>

              <div style={{height:1,backgroundColor:C.brd,margin:"10px 0"}}/>
              <Label color={C.ylw}>Framing</Label>
              <Num label="General Framing Hours" value={s.framing_hours} onChange={v=>set("framing_hours",v)} unit="hrs" step={1}/>
              <Tog label="Pocket Door" value={s.has_pocket_door} onChange={v=>set("has_pocket_door",v)}/>

              <div style={{height:1,backgroundColor:C.brd,margin:"10px 0"}}/>
              <Label color={C.teal}>Finish Carpentry</Label>
              <Sel label="Vanity Size" value={s.vanity_size} onChange={v=>set("vanity_size",v)}
                options={[{v:"single",l:"Single (24-36\")"},{v:"double",l:"Double (48-72\")"}]}/>
              <Tog label="Mirror Install" value={s.has_mirror} onChange={v=>set("has_mirror",v)}/>
              <Tog label="Trim & Baseboard" value={s.has_trim_work} onChange={v=>set("has_trim_work",v)}/>
              <Num label="Accessory Count" value={s.accessory_count} onChange={v=>set("accessory_count",v)} step={1}/>
            </Box>

            <div style={{gridColumn:"1/-1",display:"flex",justifyContent:"flex-end"}}>
              <button onClick={()=>{setOvr({});setRemoved({});setView("estimate");}} style={{
                padding:"10px 28px",borderRadius:6,border:"none",cursor:"pointer",
                backgroundColor:C.acc,color:C.bg,fontSize:12,fontWeight:700,fontFamily:mono,
                letterSpacing:"0.06em",textTransform:"uppercase"
              }}>Assemble Estimate →</button>
            </div>
          </div>
        )}

        {/* ==================== DETAILS TAB ==================== */}
        {view === "details" && (
          <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:14}}>
            <Box>
              <Label color={C.acc}>Allowance Amounts</Label>
              <Num label="Bathtub" value={s.tub_allowance} onChange={v=>set("tub_allowance",v)} unit="$" show={s.has_tub} step={100}/>
              <Num label="Shower Trim" value={s.shower_trim_allowance} onChange={v=>set("shower_trim_allowance",v)} unit="$" show={s.has_shower} step={100}/>
              <Num label="Toilet" value={s.toilet_allowance} onChange={v=>set("toilet_allowance",v)} unit="$" step={100}/>
              <Num label="Vanity" value={s.vanity_allowance} onChange={v=>set("vanity_allowance",v)} unit="$" step={100}/>
              <Num label="Accessories" value={s.accessory_allowance} onChange={v=>set("accessory_allowance",v)} unit="$" step={100}/>
              <div style={{marginTop:8,padding:8,backgroundColor:C.card2,borderRadius:4}}>
                <span style={{color:C.txD,fontSize:10}}>Tile allowances are auto-calculated from sqft. Floor: ${Math.max(400,Math.round(fl*10)).toLocaleString()} · Shower: ${Math.max(800,Math.round(wallTile*12)).toLocaleString()}</span>
              </div>
            </Box>
            <Box>
              <Label color={C.txD}>Add Custom Line Item</Label>
              <div style={{display:"flex",flexDirection:"column",gap:6}}>
                <input placeholder="Item name" value={newItem.name} onChange={e=>setNewItem(p=>({...p,name:e.target.value}))}
                  style={{padding:"6px 8px",borderRadius:3,border:`1px solid ${C.brd}`,backgroundColor:C.card2,color:C.txB,fontSize:12,fontFamily:mono,outline:"none"}}/>
                <div style={{display:"flex",gap:6}}>
                  <input placeholder="Group" value={newItem.group} onChange={e=>setNewItem(p=>({...p,group:e.target.value}))}
                    style={{flex:1,padding:"6px 8px",borderRadius:3,border:`1px solid ${C.brd}`,backgroundColor:C.card2,color:C.txB,fontSize:12,fontFamily:mono,outline:"none"}}/>
                  <select value={newItem.type} onChange={e=>setNewItem(p=>({...p,type:e.target.value}))}
                    style={{padding:"6px",borderRadius:3,border:`1px solid ${C.brd}`,backgroundColor:C.card2,color:C.txB,fontSize:11,fontFamily:mono}}>
                    <option value="Materials">Materials</option><option value="Labor">Labor</option><option value="Other">Other</option>
                  </select>
                </div>
                <div style={{display:"flex",gap:6}}>
                  <input type="number" placeholder="Qty" value={newItem.qty} onChange={e=>setNewItem(p=>({...p,qty:parseFloat(e.target.value)||0}))}
                    style={{width:60,padding:"6px 8px",borderRadius:3,border:`1px solid ${C.brd}`,backgroundColor:C.card2,color:C.txB,fontSize:12,fontFamily:mono,outline:"none",textAlign:"right"}}/>
                  <input type="number" placeholder="Unit Cost" value={newItem.cost||""} onChange={e=>setNewItem(p=>({...p,cost:parseFloat(e.target.value)||0}))}
                    style={{width:80,padding:"6px 8px",borderRadius:3,border:`1px solid ${C.brd}`,backgroundColor:C.card2,color:C.txB,fontSize:12,fontFamily:mono,outline:"none",textAlign:"right"}}/>
                  <button onClick={addCustomItem} style={{
                    padding:"6px 14px",borderRadius:3,border:"none",cursor:"pointer",
                    backgroundColor:C.acc,color:C.bg,fontSize:11,fontWeight:700,fontFamily:mono
                  }}>+ Add</button>
                </div>
              </div>
              {s.custom_items?.length > 0 && (
                <div style={{marginTop:10}}>
                  {s.custom_items.map((ci,idx)=>(
                    <div key={idx} style={{display:"flex",justifyContent:"space-between",padding:"4px 0",borderBottom:`1px solid ${C.brd}`}}>
                      <span style={{color:C.tx,fontSize:11}}>{ci.name} ({ci.qty}× ${ci.cost})</span>
                      <button onClick={()=>set("custom_items",s.custom_items.filter((_,i)=>i!==idx))}
                        style={{background:"none",border:"none",color:C.red,cursor:"pointer",fontSize:11,fontFamily:mono}}>×</button>
                    </div>
                  ))}
                </div>
              )}
            </Box>
            <Box style={{gridColumn:"1/-1"}}>
              <Label>Trade Labor Rates (reference — edit in catalog DB)</Label>
              <div style={{display:"grid",gridTemplateColumns:"repeat(5,1fr)",gap:8}}>
                {Object.entries(TRADE_RATES).map(([k,v])=>{
                  const r = tradeRate(k);
                  return (
                    <div key={k} style={{padding:8,backgroundColor:C.card2,borderRadius:4,textAlign:"center"}}>
                      <div style={{color:C.txD,fontSize:9,textTransform:"uppercase",marginBottom:2}}>{k}</div>
                      <div style={{color:C.txB,fontSize:13,fontWeight:600}}>${r.cost.toFixed(2)}</div>
                      <div style={{color:C.acc,fontSize:10}}>${r.price.toFixed(2)}/hr</div>
                    </div>
                  );
                })}
              </div>
            </Box>
          </div>
        )}

        {/* ==================== ESTIMATE TAB ==================== */}
        {view === "estimate" && (
          <div>
            <Box style={{padding:0,overflow:"hidden"}}>
              <div style={{display:"grid",gridTemplateColumns:"1fr 54px 70px 70px 80px 80px 30px",gap:6,padding:"7px 10px",
                backgroundColor:C.card2,borderBottom:`1px solid ${C.brd}`,fontSize:9,color:C.txD,textTransform:"uppercase",letterSpacing:"0.1em",fontWeight:600}}>
                <span>Item</span><span style={{textAlign:"right"}}>Qty</span><span style={{textAlign:"right"}}>Unit</span>
                <span style={{textAlign:"right"}}>$/Unit</span><span style={{textAlign:"right"}}>Cost</span>
                <span style={{textAlign:"right"}}>Price</span><span/>
              </div>
              {Object.entries(groups).map(([gn, items]) => {
                const base = gn.split(" > ")[0];
                const gc = GC[base]||C.txD;
                const gCost = items.reduce((a,i)=>a+i.extC,0);
                const gPrice = items.reduce((a,i)=>a+i.extP,0);
                return (
                  <div key={gn}>
                    <div style={{display:"grid",gridTemplateColumns:"1fr 54px 70px 70px 80px 80px 30px",gap:6,padding:"6px 10px",
                      backgroundColor:"rgba(255,255,255,0.015)",borderBottom:`1px solid ${C.brd}`,borderTop:`1px solid ${C.brd}`}}>
                      <span style={{color:gc,fontSize:11,fontWeight:700}}>{gn}</span>
                      <span/><span/><span/>
                      <span style={{color:C.txD,fontSize:10,textAlign:"right"}}>${Math.round(gCost).toLocaleString()}</span>
                      <span style={{color:gc,fontSize:10,textAlign:"right",fontWeight:600}}>${Math.round(gPrice).toLocaleString()}</span>
                      <span/>
                    </div>
                    {items.map(item=>(
                      <div key={item.id} style={{display:"grid",gridTemplateColumns:"1fr 54px 70px 70px 80px 80px 30px",gap:6,padding:"5px 10px",
                        alignItems:"center",borderBottom:`1px solid ${C.brd}22`,fontSize:11,
                        backgroundColor:item._edited?"rgba(201,149,107,0.04)":"transparent"}}>
                        <div style={{display:"flex",alignItems:"center",gap:6,overflow:"hidden"}}>
                          <div style={{width:2,height:12,borderRadius:1,backgroundColor:gc,flexShrink:0}}/>
                          <span style={{color:C.tx,overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap"}}>{item.name}</span>
                        </div>
                        <input type="number" value={item.qty} onChange={e=>setOvr(o=>({...o,[item.id]:parseFloat(e.target.value)||0}))}
                          style={{width:48,padding:"2px 4px",borderRadius:3,border:`1px solid ${C.brd}`,backgroundColor:C.card2,color:C.txB,fontSize:11,textAlign:"right",fontFamily:"inherit",outline:"none"}}/>
                        <span style={{color:C.txD,textAlign:"right",fontSize:10}}>{item.unit}</span>
                        <span style={{color:C.tx,textAlign:"right"}}>${item.uc.toFixed(2)}</span>
                        <span style={{color:C.tx,textAlign:"right"}}>${Math.round(item.extC).toLocaleString()}</span>
                        <span style={{color:C.acc,textAlign:"right",fontWeight:600}}>${Math.round(item.extP).toLocaleString()}</span>
                        <button onClick={()=>setRemoved(r=>({...r,[item.id]:true}))}
                          style={{background:"none",border:"none",color:C.txD,cursor:"pointer",fontSize:10,fontFamily:mono,padding:0}}>×</button>
                      </div>
                    ))}
                  </div>
                );
              })}
              <div style={{display:"grid",gridTemplateColumns:"1fr 54px 70px 70px 80px 80px 30px",gap:6,padding:"10px 10px",
                backgroundColor:C.card2,borderTop:`2px solid ${C.acc}`}}>
                <span style={{color:C.txB,fontSize:12,fontWeight:700}}>TOTAL · {totals.items} items · {Math.round(totals.laborHrs)}h labor</span>
                <span/><span/><span/>
                <span style={{color:C.txB,fontSize:13,fontWeight:700,textAlign:"right"}}>${Math.round(totals.cost).toLocaleString()}</span>
                <span style={{color:C.acc,fontSize:13,fontWeight:700,textAlign:"right"}}>${Math.round(totals.price).toLocaleString()}</span>
                <span/>
              </div>
            </Box>

            <div style={{display:"flex",gap:10,marginTop:14,justifyContent:"flex-end",flexWrap:"wrap"}}>
              <button onClick={()=>setView("scope")} style={{padding:"9px 18px",borderRadius:5,border:`1px solid ${C.brd}`,cursor:"pointer",backgroundColor:"transparent",color:C.txD,fontSize:11,fontWeight:600,fontFamily:mono}}>
                ← Edit Scope
              </button>
              <button onClick={()=>setView("details")} style={{padding:"9px 18px",borderRadius:5,border:`1px solid ${C.brd}`,cursor:"pointer",backgroundColor:"transparent",color:C.txD,fontSize:11,fontWeight:600,fontFamily:mono}}>
                Allowances & Custom Items
              </button>
              <button onClick={copyPayload} style={{padding:"9px 18px",borderRadius:5,border:"none",cursor:"pointer",backgroundColor:C.acc,color:C.bg,fontSize:11,fontWeight:700,fontFamily:mono}}>
                {pushMsg==="payload"?"✓ Copied":"Copy JT Payload"}
              </button>
            </div>
            {pushMsg && <div style={{marginTop:10,padding:10,backgroundColor:C.card,borderRadius:5,border:`1px solid ${C.brd}`}}>
              <span style={{color:C.txD,fontSize:10}}>JT payload on clipboard. Use with jobtread_add_budget_line_items or paste into n8n webhook.</span>
            </div>}
          </div>
        )}
      </div>
    </div>
  );
}
