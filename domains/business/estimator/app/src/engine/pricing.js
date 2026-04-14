import tradeRates from '../data/tradeRates.json';

// Material markup: ~30% target margin
export const MAT_MARKUP = 1.4286;

/**
 * Calculate hourly cost and price for a given trade.
 * cost  = wage × burden
 * price = cost × markup
 */
export function tradeRate(trade) {
  const r = tradeRates[trade] ?? tradeRates.planning;
  const cost = Math.round(r.wage * r.burden * 100) / 100;
  return {
    cost,
    price: Math.round(cost * r.markup * 100) / 100,
  };
}

/**
 * Apply material markup to a raw cost to get sell price.
 */
export function matPrice(cost) {
  return Math.round(cost * MAT_MARKUP * 100) / 100;
}

/**
 * Compute extended cost and price for a line item.
 */
export function extendItem(item) {
  const extC = Math.round(item.uc * item.qty * 100) / 100;
  const extP = Math.round(item.up * item.qty * 100) / 100;
  return { ...item, extC, extP };
}
