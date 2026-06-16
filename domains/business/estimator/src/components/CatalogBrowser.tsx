// @ts-nocheck
import { useState, useMemo } from 'react';
import { C, mono } from '../styles/theme.js';
import { matPrice } from '../engine/pricing.js';
import pricebook from '../data/pricebook.json' with { type: 'json' };

// All unique trades from the pricebook, sorted
const ALL_TRADES = [...new Set(pricebook.map(i => i.trade).filter(Boolean))].sort();

const TYPE_FILTERS = [
  { key: null, label: 'All' },
  { key: 'Labor', label: 'Labor' },
  { key: 'Material', label: 'Material' },
  { key: 'Allowance', label: 'Allowance' },
  { key: 'Other', label: 'Other' },
];

/**
 * Slide-out catalog browser panel.
 * Reads pricebook.json, lets user search/filter/pick items with quantities.
 * Calls onAdd(picks) with array of picked items when confirmed.
 */
export function CatalogBrowser({ open, onClose, onAdd, isMobile = false }) {
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState(null);
  const [tradeFilter, setTradeFilter] = useState('');
  const [cart, setCart] = useState({}); // { catalogItemId: { ...item, qty } }
  const [expandedId, setExpandedId] = useState(null);
  const [qtyInput, setQtyInput] = useState('1');

  // Filter pricebook
  const results = useMemo(() => {
    let items = pricebook;
    if (typeFilter) items = items.filter(i => i.itemType === typeFilter);
    if (tradeFilter) items = items.filter(i => i.trade === tradeFilter);
    if (search.trim()) {
      const q = search.toLowerCase();
      items = items.filter(i =>
        (i.name || '').toLowerCase().includes(q) ||
        (i.trade || '').toLowerCase().includes(q) ||
        (i.notes || '').toLowerCase().includes(q)
      );
    }
    return items;
  }, [search, typeFilter, tradeFilter]);

  // Group results by trade
  const grouped = useMemo(() => {
    const g = {};
    for (const item of results) {
      const key = item.trade || 'Other';
      if (!g[key]) g[key] = [];
      g[key].push(item);
    }
    return Object.entries(g).sort((a, b) => a[0].localeCompare(b[0]));
  }, [results]);

  const cartCount = Object.keys(cart).length;

  const handleExpand = (item) => {
    if (expandedId === item.id) {
      setExpandedId(null);
    } else {
      setExpandedId(item.id);
      setQtyInput(cart[item.id]?.qty?.toString() || '1');
    }
  };

  const handleConfirmItem = (item) => {
    const qty = parseFloat(qtyInput) || 1;
    setCart(prev => ({
      ...prev,
      [item.id]: {
        catalogItemId: item.id,
        name: item.name,
        group: item.group || 'Catalog Picks',
        code: item.code || '',
        type: item.type || 'Materials',
        unit: item.unit || 'Each',
        unitAbbr: item.unitAbbr || '',
        qty,
        uc: item.unitCost || 0,
        up: item.unitPrice || matPrice(item.unitCost || 0),
        trade: item.trade || null,
        itemType: item.itemType,
      },
    }));
    setExpandedId(null);
  };

  const handleRemoveFromCart = (id) => {
    setCart(prev => {
      const next = { ...prev };
      delete next[id];
      return next;
    });
  };

  const handleAddAll = () => {
    onAdd(Object.values(cart));
    setCart({});
    setSearch('');
    setExpandedId(null);
    onClose();
  };

  if (!open) return null;

  const panelWidth = isMobile ? '100vw' : '480px';

  return (
    <>
      {/* Backdrop */}
      <div onClick={onClose} style={{
        position: 'fixed', inset: 0, backgroundColor: 'rgba(0,0,0,0.5)',
        zIndex: 200,
      }} />

      {/* Panel */}
      <div style={{
        position: 'fixed', top: 0, right: 0, bottom: 0,
        width: panelWidth, maxWidth: '100vw',
        backgroundColor: C.bg, borderLeft: `1px solid ${C.brd}`,
        zIndex: 201, display: 'flex', flexDirection: 'column',
        fontFamily: mono,
      }}>

        {/* Header */}
        <div style={{
          padding: '14px 16px', borderBottom: `1px solid ${C.brd}`,
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          flexShrink: 0,
        }}>
          <span style={{ color: C.txB, fontSize: 13, fontWeight: 700 }}>Price Book</span>
          <button onClick={onClose} style={{
            background: 'none', border: 'none', color: C.txD,
            cursor: 'pointer', fontSize: 16, fontFamily: mono, padding: '2px 6px',
          }}>✕</button>
        </div>

        {/* Search */}
        <div style={{ padding: '10px 16px 6px', flexShrink: 0 }}>
          <input
            type="text"
            placeholder="Search items..."
            value={search}
            onChange={e => setSearch(e.target.value)}
            autoFocus
            style={{
              width: '100%', padding: '10px 12px', borderRadius: 6,
              border: `1px solid ${C.brd}`, backgroundColor: C.card,
              color: C.txB, fontSize: 12, fontFamily: mono, outline: 'none',
              boxSizing: 'border-box',
            }}
          />
        </div>

        {/* Filters */}
        <div style={{ padding: '4px 16px 10px', flexShrink: 0 }}>
          {/* Type chips */}
          <div style={{ display: 'flex', gap: 4, marginBottom: 8, flexWrap: 'wrap' }}>
            {TYPE_FILTERS.map(f => (
              <button key={f.label} onClick={() => setTypeFilter(f.key)} style={{
                padding: '5px 10px', borderRadius: 4, border: `1px solid ${C.brd}`,
                backgroundColor: typeFilter === f.key ? C.acc : 'transparent',
                color: typeFilter === f.key ? C.bg : C.txD,
                fontSize: 10, fontWeight: 600, fontFamily: mono, cursor: 'pointer',
                textTransform: 'uppercase', letterSpacing: '0.05em',
              }}>
                {f.label}
              </button>
            ))}
          </div>
          {/* Trade dropdown */}
          <select
            value={tradeFilter}
            onChange={e => setTradeFilter(e.target.value)}
            style={{
              width: '100%', padding: '8px 10px', borderRadius: 5,
              border: `1px solid ${C.brd}`, backgroundColor: C.card,
              color: C.tx, fontSize: 11, fontFamily: mono, outline: 'none',
            }}
          >
            <option value="">All trades ({results.length} items)</option>
            {ALL_TRADES.map(t => (
              <option key={t} value={t}>{t}</option>
            ))}
          </select>
        </div>

        {/* Results */}
        <div style={{ flex: 1, overflowY: 'auto', padding: '0 0 80px' }}>
          {grouped.map(([trade, items]) => (
            <div key={trade}>
              {/* Trade group header */}
              <div style={{
                padding: '8px 16px', backgroundColor: 'rgba(255,255,255,0.02)',
                borderTop: `1px solid ${C.brd}`, borderBottom: `1px solid ${C.brd}`,
              }}>
                <span style={{ color: C.txD, fontSize: 10, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
                  {trade} ({items.length})
                </span>
              </div>

              {/* Items */}
              {items.map(item => {
                const inCart = !!cart[item.id];
                const isExpanded = expandedId === item.id;

                return (
                  <div key={item.id} style={{
                    borderBottom: `1px solid ${C.brd}22`,
                    backgroundColor: inCart ? 'rgba(107,203,119,0.04)' : 'transparent',
                  }}>
                    {/* Item row */}
                    <div style={{
                      padding: '8px 16px', display: 'flex', justifyContent: 'space-between',
                      alignItems: 'center', cursor: 'pointer',
                    }} onClick={() => handleExpand(item)}>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{
                          color: C.tx, fontSize: 11, overflow: 'hidden',
                          textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                        }}>
                          {inCart && <span style={{ color: C.grn, marginRight: 4 }}>●</span>}
                          {item.name}
                        </div>
                        <div style={{ color: C.txD, fontSize: 10, marginTop: 2 }}>
                          ${(item.unitCost || 0).toFixed(2)} → ${(item.unitPrice || matPrice(item.unitCost || 0)).toFixed(2)}
                          <span style={{ marginLeft: 6 }}>{item.unitAbbr || item.unit || 'ea'}</span>
                        </div>
                      </div>
                      {inCart ? (
                        <button onClick={(e) => { e.stopPropagation(); handleRemoveFromCart(item.id); }} style={{
                          background: 'none', border: `1px solid ${C.brd}`,
                          color: C.txD, cursor: 'pointer', fontSize: 10, fontFamily: mono,
                          padding: '4px 8px', borderRadius: 4,
                        }}>
                          ×{cart[item.id].qty}
                        </button>
                      ) : (
                        <button onClick={(e) => { e.stopPropagation(); handleExpand(item); }} style={{
                          background: 'none', border: `1px solid ${C.brd}`,
                          color: C.acc, cursor: 'pointer', fontSize: 12, fontFamily: mono,
                          padding: '4px 10px', borderRadius: 4,
                        }}>
                          +
                        </button>
                      )}
                    </div>

                    {/* Expanded qty input */}
                    {isExpanded && (
                      <div style={{
                        padding: '6px 16px 10px', display: 'flex', gap: 8, alignItems: 'center',
                        backgroundColor: 'rgba(255,255,255,0.02)',
                      }}>
                        <span style={{ color: C.txD, fontSize: 10 }}>Qty:</span>
                        <input
                          type="number"
                          value={qtyInput}
                          onChange={e => setQtyInput(e.target.value)}
                          autoFocus
                          onKeyDown={e => e.key === 'Enter' && handleConfirmItem(item)}
                          style={{
                            width: 70, padding: '6px 8px', borderRadius: 4,
                            border: `1px solid ${C.brd}`, backgroundColor: C.card2,
                            color: C.txB, fontSize: 12, textAlign: 'right',
                            fontFamily: mono, outline: 'none',
                          }}
                        />
                        <span style={{ color: C.txD, fontSize: 10 }}>{item.unitAbbr || item.unit || 'ea'}</span>
                        <button onClick={() => handleConfirmItem(item)} style={{
                          padding: '6px 14px', borderRadius: 4, border: 'none',
                          backgroundColor: C.acc, color: C.bg, cursor: 'pointer',
                          fontSize: 10, fontWeight: 700, fontFamily: mono,
                        }}>
                          {inCart ? 'Update' : 'Add'}
                        </button>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          ))}

          {results.length === 0 && (
            <div style={{ padding: 32, textAlign: 'center', color: C.txD, fontSize: 12 }}>
              No items match your search.
            </div>
          )}
        </div>

        {/* Cart summary (sticky bottom) */}
        <div style={{
          position: 'absolute', bottom: 0, left: 0, right: 0,
          padding: '12px 16px', borderTop: `1px solid ${C.brd}`,
          backgroundColor: C.card, display: 'flex', justifyContent: 'space-between',
          alignItems: 'center',
        }}>
          <span style={{ color: C.txD, fontSize: 11 }}>
            {cartCount === 0 ? 'No items selected' : `${cartCount} item${cartCount > 1 ? 's' : ''} selected`}
          </span>
          <button
            onClick={handleAddAll}
            disabled={cartCount === 0}
            style={{
              padding: '9px 18px', borderRadius: 5, border: 'none',
              backgroundColor: cartCount > 0 ? C.acc : C.brd,
              color: cartCount > 0 ? C.bg : C.txD,
              cursor: cartCount > 0 ? 'pointer' : 'default',
              fontSize: 11, fontWeight: 700, fontFamily: mono,
            }}
          >
            Add to Estimate →
          </button>
        </div>
      </div>
    </>
  );
}
