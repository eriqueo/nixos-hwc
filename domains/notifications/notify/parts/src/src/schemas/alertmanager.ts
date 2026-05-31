/**
 * Alertmanager webhook payload schema (v4).
 *
 * Reference: https://prometheus.io/docs/alerting/latest/configuration/#webhook_config
 *
 * Alertmanager POSTs one of these per receiver per group_interval. We
 * fan each alert in the batch out to dispatch() as a separate
 * Notification — keeps the audit trail per-alert and lets the router
 * make per-alert decisions (e.g., a single batch may include alerts of
 * different severities).
 */

import { z } from "zod";

/**
 * Alertmanager uses RFC 3339 timestamps but sets `endsAt` to
 * `0001-01-01T00:00:00Z` for actively-firing alerts. Accept any string;
 * the converter normalises into a real ISO timestamp.
 */
const TimestampSchema = z.string().min(1);

export const AlertmanagerAlertSchema = z.object({
  status: z.union([z.literal("firing"), z.literal("resolved")]),
  labels: z.record(z.string(), z.string()).default({}),
  annotations: z.record(z.string(), z.string()).default({}),
  startsAt: TimestampSchema,
  endsAt: TimestampSchema.optional(),
  generatorURL: z.string().optional(),
  fingerprint: z.string().optional(),
});

export const AlertmanagerWebhookSchema = z.object({
  version: z.string().optional(),
  status: z.union([z.literal("firing"), z.literal("resolved")]).optional(),
  receiver: z.string().optional(),
  groupKey: z.string().optional(),
  truncatedAlerts: z.number().optional(),
  groupLabels: z.record(z.string(), z.string()).default({}),
  commonLabels: z.record(z.string(), z.string()).default({}),
  commonAnnotations: z.record(z.string(), z.string()).default({}),
  externalURL: z.string().optional(),
  alerts: z.array(AlertmanagerAlertSchema).min(1),
});

export type AlertmanagerAlert = z.infer<typeof AlertmanagerAlertSchema>;
export type AlertmanagerWebhook = z.infer<typeof AlertmanagerWebhookSchema>;
