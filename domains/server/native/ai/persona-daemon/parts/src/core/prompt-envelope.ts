import type { PersonaMeta } from "./types.ts";

/**
 * Pinned contract — changing this shape is breaking for any persona's .md
 * that references the envelope. Plan doc spells out the structure.
 *
 * In Commit 2 the `<context>` and `<instructions>` blocks are absent
 * (RAG isn't wired). They get added by Commit 3 when useKnowledge fires.
 */
export function buildSystemPrompt(args: {
  persona: PersonaMeta;
  summary: string | null;
  retrievedChunks?: ReadonlyArray<{
    notePath: string;
    sectionTitle: string;
    score: number;
    body: string;
  }>;
}): string {
  const { persona, summary, retrievedChunks } = args;

  const parts: string[] = [];
  parts.push(`<system>${persona.systemPrompt.trim()}</system>`);
  parts.push(`<conversation-summary>${summary ?? "(none)"}</conversation-summary>`);

  if (retrievedChunks && retrievedChunks.length > 0) {
    const chunks = retrievedChunks.map((c) => {
      return `  <chunk path="${escapeAttr(c.notePath)}" section="${
        escapeAttr(c.sectionTitle)
      }" score="${c.score.toFixed(4)}">\n${c.body.trim()}\n  </chunk>`;
    }).join("\n");
    parts.push(
      `<context source="brain-vault" retrieved="${retrievedChunks.length}">\n${chunks}\n</context>`,
    );
    parts.push(
      `<instructions>\nCite chunks by their path when you use them. If the context is empty or irrelevant, answer from your own knowledge and say so.\n</instructions>`,
    );
  }

  return parts.join("\n");
}

function escapeAttr(s: string): string {
  return s.replace(/[&<>"]/g, (c) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
  })[c] ?? c);
}
