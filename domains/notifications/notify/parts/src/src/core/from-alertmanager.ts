/**
 * Pure converter: Alertmanager webhook → Notification[].
 *
 * Each alert in the batch becomes its own Notification so the router
 * makes per-alert decisions and the (future) audit log records each
 * delivery attempt individually. Stable ids derived from
 * `fingerprint` (when Alertmanager provides it) or
 * `alertname + startsAt` so re-deliveries of the same alert by
 * Alertmanager produce the same Notification id — sets up dedup for
 * Phase 1.5.
 */

import type { Notification, Priority } from "./types.js";
import type {
  AlertmanagerAlert,
  AlertmanagerWebhook,
} from "../schemas/alertmanager.js";

/**
 * Map an Alertmanager `severity` label to a Notification priority.
 * Falls back to P3 for unknown values — visible without being a page.
 */
export function severityToPriority(severity: string | undefined): Priority {
  switch ((severity ?? "").toLowerCase()) {
    // The Prometheus rules in domains/monitoring/prometheus/parts/alerts.nix
    // speak an INVERTED P-scale (P5=Critical, P4=Warning, P3=Info — see its
    // header). Before these cases existed every alertmanager alert fell
    // through to the default and dispatched at priority 3, erasing the tiers.
    case "p5":
    case "critical":
    case "page":
      return 1;
    case "high":
    case "error":
      return 2;
    case "p4":
    case "warning":
    case "warn":
      return 3;
    case "p3":
    case "info":
    case "notice":
      return 4;
    case "low":
    case "debug":
      return 5;
    default:
      return 3;
  }
}

/** Render labels as `k: v` lines for fallback body text. */
function renderLabels(labels: Record<string, string>, omit: ReadonlySet<string>): string {
  return Object.entries(labels)
    .filter(([k]) => !omit.has(k))
    .map(([k, v]) => `${k}: ${v}`)
    .join("\n");
}

/** Slug-clean: lowercase, replace non-[a-z0-9-] with `-`, trim dashes. */
function slugify(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9-]+/g, "-").replace(/^-+|-+$/g, "");
}

function alertToNotification(
  alert: AlertmanagerAlert,
  commonLabels: Record<string, string>,
  commonAnnotations: Record<string, string>,
): Notification {
  const labels = { ...commonLabels, ...alert.labels };
  const annotations = { ...commonAnnotations, ...alert.annotations };
  const isResolved = alert.status === "resolved";

  // Topic: prefer explicit `category` (existing alert-rules convention)
  // or `topic`; fall back to "monitoring" so the topic schema's slug
  // regex always matches.
  const rawTopic = labels.category || labels.topic || "monitoring";
  const topic = slugify(rawTopic) || "monitoring";

  // Priority: resolved → always P5; firing → severity mapping.
  const priority: Priority = isResolved ? 5 : severityToPriority(labels.severity);

  // Title: annotations.summary > labels.alertname > literal "alert".
  const baseTitle = annotations.summary || labels.alertname || "alert";
  const title = (isResolved ? "[RESOLVED] " : "") + baseTitle;

  // Body: annotations.description > a label dump (without re-stating
  // alertname/severity which are already in the embed elsewhere).
  let body = annotations.description || annotations.summary || "";
  if (!body) {
    body = renderLabels(labels, new Set(["alertname", "severity"]));
  }

  // Tags: pluck a few well-known labels. Filter empties.
  const tags: string[] = [];
  for (const k of ["severity", "alertname", "category", "instance", "job"]) {
    const v = labels[k];
    if (v && v.length > 0) tags.push(v);
  }
  tags.push(alert.status);

  // Stable id: prefer Alertmanager's fingerprint (when present, it's
  // already content-hashed across labels); otherwise alertname +
  // startsAt. Suffix with status so a firing+resolved pair gets two
  // distinct audit rows when audit-log lands.
  const baseId = alert.fingerprint || `${labels.alertname || "unknown"}-${alert.startsAt}`;
  const id = `alertmanager-${baseId}-${alert.status}`;

  return {
    id,
    title,
    body,
    priority,
    topic,
    source: "alertmanager",
    tags,
    context: {
      ...labels,
      ...annotations,
      generatorURL: alert.generatorURL || "",
      fingerprint: alert.fingerprint || "",
    },
    occurredAt: alert.startsAt,
  };
}

/** Fan an Alertmanager webhook payload into one Notification per alert. */
export function webhookToNotifications(payload: AlertmanagerWebhook): Notification[] {
  return payload.alerts.map((a) =>
    alertToNotification(a, payload.commonLabels, payload.commonAnnotations),
  );
}
