import PDFDocument from 'pdfkit';
import fs from 'node:fs';
import path from 'node:path';
import type { Config, DaySummary, CategorySummary } from '../lib/types.js';
import { formatHoursDecimal, formatCurrency } from '../lib/time.js';

interface InvoiceData {
  config: Config;
  from: string; // YYYY-MM-DD
  to: string;
  days: DaySummary[];
  categories: CategorySummary[];
  totalMinutes: number;
}

export function generateInvoice(data: InvoiceData): string {
  const outDir = path.join(process.env.HOME || '~', 'Documents', 'datax-time');
  fs.mkdirSync(outDir, { recursive: true });
  const filename = `invoice-${data.from}-to-${data.to}.pdf`;
  const outPath = path.join(outDir, filename);

  const doc = new PDFDocument({ size: 'LETTER', margin: 60 });
  const stream = fs.createWriteStream(outPath);
  doc.pipe(stream);

  const { config, from, to, days, categories, totalMinutes } = data;
  const totalHours = totalMinutes / 60;
  const amountDue = totalHours * config.rate;

  // ── Header ──────────────────────────────────────────
  doc.fontSize(24).font('Helvetica-Bold').text('INVOICE', { align: 'right' });
  doc.moveDown(0.3);
  doc.fontSize(11).font('Helvetica').text(config.name, { align: 'right' });
  doc.fontSize(10).text(`${from}  →  ${to}`, { align: 'right' });
  doc.moveDown(1.5);

  // ── Line Items Table ────────────────────────────────
  const tableTop = doc.y;
  const col = { date: 60, cat: 170, hours: 340, notes: 410 };

  // Header row
  doc.fontSize(9).font('Helvetica-Bold');
  doc.text('Date', col.date, tableTop);
  doc.text('Category', col.cat, tableTop);
  doc.text('Hours', col.hours, tableTop);
  doc.text('Notes', col.notes, tableTop);

  doc.moveTo(60, tableTop + 14).lineTo(550, tableTop + 14).lineWidth(0.5).stroke();

  let y = tableTop + 20;
  doc.font('Courier').fontSize(8.5);

  for (const day of days) {
    if (y > 680) {
      doc.addPage();
      y = 60;
    }
    const hrs = formatHoursDecimal(day.total_minutes);
    const notesText = day.notes.filter(Boolean).join('; ').slice(0, 80);

    doc.text(day.date, col.date, y);
    doc.text(day.category, col.cat, y);
    doc.text(hrs, col.hours, y);
    doc.text(notesText || '—', col.notes, y, { width: 140, lineBreak: false });
    y += 15;
  }

  // ── Category Summary ────────────────────────────────
  y += 20;
  if (y > 620) { doc.addPage(); y = 60; }

  doc.moveTo(300, y).lineTo(550, y).lineWidth(0.5).stroke();
  y += 10;

  doc.font('Helvetica-Bold').fontSize(10);
  doc.text('Category Summary', 300, y);
  y += 18;

  doc.font('Courier').fontSize(9);
  for (const cat of categories) {
    doc.text(cat.category, 310, y);
    doc.text(`${formatHoursDecimal(cat.total_minutes)} hrs`, 460, y, { align: 'right', width: 80 });
    y += 14;
  }

  // Totals
  y += 6;
  doc.moveTo(300, y).lineTo(550, y).lineWidth(0.5).stroke();
  y += 10;

  doc.font('Helvetica-Bold').fontSize(10);
  doc.text('Total Hours', 310, y);
  doc.text(formatHoursDecimal(totalMinutes), 460, y, { align: 'right', width: 80 });
  y += 16;

  doc.text('Rate', 310, y);
  doc.text(`${formatCurrency(config.rate)}/hr`, 460, y, { align: 'right', width: 80 });
  y += 16;

  doc.fontSize(13);
  doc.text('Amount Due', 310, y);
  doc.text(formatCurrency(amountDue), 440, y, { align: 'right', width: 100 });

  doc.end();

  return new Promise<string>((resolve, reject) => {
    stream.on('finish', () => resolve(outPath));
    stream.on('error', reject);
  }) as unknown as string; // sync-ish for CLI — see note below
}

/** Async wrapper for proper stream handling */
export async function generateInvoiceAsync(data: InvoiceData): Promise<string> {
  const outDir = path.join(process.env.HOME || '~', 'Documents', 'datax-time');
  fs.mkdirSync(outDir, { recursive: true });
  const filename = `invoice-${data.from}-to-${data.to}.pdf`;
  const outPath = path.join(outDir, filename);

  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'LETTER', margin: 60 });
    const stream = fs.createWriteStream(outPath);
    doc.pipe(stream);

    const { config, from, to, days, categories, totalMinutes } = data;
    const totalHours = totalMinutes / 60;
    const amountDue = totalHours * config.rate;

    // Header
    doc.fontSize(24).font('Helvetica-Bold').text('INVOICE', { align: 'right' });
    doc.moveDown(0.3);
    doc.fontSize(11).font('Helvetica').text(config.name, { align: 'right' });
    doc.fontSize(10).text(`${from}  →  ${to}`, { align: 'right' });
    doc.moveDown(1.5);

    // Table header
    const tableTop = doc.y;
    const c = { date: 60, cat: 170, hours: 340, notes: 410 };
    doc.fontSize(9).font('Helvetica-Bold');
    doc.text('Date', c.date, tableTop);
    doc.text('Category', c.cat, tableTop);
    doc.text('Hours', c.hours, tableTop);
    doc.text('Notes', c.notes, tableTop);
    doc.moveTo(60, tableTop + 14).lineTo(550, tableTop + 14).lineWidth(0.5).stroke();

    let y = tableTop + 20;
    doc.font('Courier').fontSize(8.5);
    for (const day of days) {
      if (y > 680) { doc.addPage(); y = 60; }
      doc.text(day.date, c.date, y);
      doc.text(day.category, c.cat, y);
      doc.text(formatHoursDecimal(day.total_minutes), c.hours, y);
      doc.text(day.notes.filter(Boolean).join('; ').slice(0, 80) || '—', c.notes, y, { width: 140, lineBreak: false });
      y += 15;
    }

    // Summary
    y += 20;
    if (y > 620) { doc.addPage(); y = 60; }
    doc.moveTo(300, y).lineTo(550, y).lineWidth(0.5).stroke();
    y += 10;
    doc.font('Helvetica-Bold').fontSize(10).text('Category Summary', 300, y);
    y += 18;
    doc.font('Courier').fontSize(9);
    for (const cat of categories) {
      doc.text(cat.category, 310, y);
      doc.text(`${formatHoursDecimal(cat.total_minutes)} hrs`, 460, y, { align: 'right', width: 80 });
      y += 14;
    }
    y += 6;
    doc.moveTo(300, y).lineTo(550, y).lineWidth(0.5).stroke();
    y += 10;
    doc.font('Helvetica-Bold').fontSize(10);
    doc.text('Total Hours', 310, y);
    doc.text(formatHoursDecimal(totalMinutes), 460, y, { align: 'right', width: 80 });
    y += 16;
    doc.text('Rate', 310, y);
    doc.text(`${formatCurrency(config.rate)}/hr`, 460, y, { align: 'right', width: 80 });
    y += 16;
    doc.fontSize(13);
    doc.text('Amount Due', 310, y);
    doc.text(formatCurrency(amountDue), 440, y, { align: 'right', width: 100 });

    doc.end();
    stream.on('finish', () => resolve(outPath));
    stream.on('error', reject);
  });
}
