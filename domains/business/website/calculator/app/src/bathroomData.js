// ─── Bathroom Calculator Data ──────────────────────────────────────────────
// Thin loader. The canonical source is the JSON file in the website repo
// at site_files/src/_data/calculator-bathroom.json. Vite imports JSON
// natively. To change pricing, options, or copy: edit the JSON only.

import data from "../../../site_files/src/_data/calculator-bathroom.json";
import { buildSteps, makeCalculator, makeHelpers } from "./calcData.js";

export const STEPS = buildSteps(data);
export const calculateRange = makeCalculator(data);
export const { getLabel, getAttribution, fireEvent, fmt } = makeHelpers(data);
export const WEBHOOK = data.webhook;
export const WEBHOOK_APPT = data.webhookAppointment;
export const REPORT_CONTEXT = data.reportContext;
export const IMAGE_BASE = data.imageBase;
