// ─── Deck Calculator Data ──────────────────────────────────────────────────
// Thin loader. Canonical source: site_files/src/_data/calculator-deck.json.
// To change pricing, options, or copy: edit the JSON only.

import data from "../../../site_files/src/_data/calculator-deck.json";
import { buildSteps, makeCalculator, makeHelpers } from "./calcData.js";

export const STEPS = buildSteps(data);
export const calculateRange = makeCalculator(data);
export const { getLabel, getAttribution, fireEvent, fmt } = makeHelpers(data);
export const WEBHOOK = data.webhook;
export const REPORT_CONTEXT = data.reportContext;
export const IMAGE_BASE = data.imageBase;
