// domains/home/apps/pi/parts/stop-guards.ts
//
// pi extension: the end-of-turn half of the agent contract. Ports two of the
// five Claude Code Stop hooks — ste100-guard.sh and the self-caught channel of
// mistake-guard.sh.
//
// WHY THIS SHAPE. Claude Code's Stop hook can return `{decision:"block"}` and
// force the model to keep working. pi's `agent_end` event carries no result
// type, so an extension cannot reject a turn there. pi supplies a different
// mechanism for the same outcome: pi.sendMessage(msg, {triggerTurn:true,
// deliverAs:"followUp"}) queues a message that starts a new turn as soon as the
// current one ends. The model therefore gets the correction and acts on it,
// which is what the Stop hook was for. The user still sees the finished answer
// first — that is the one behavioural difference from Claude Code, and it is
// not recoverable in pi 0.80.7.
//
// TRANSITION, NOT STATE. Each finding is fingerprinted and adjudicated once per
// session, exactly like lib/cases.sh. Without that, a correction the model then
// quotes back to itself re-fires on every following turn, and a gate that nags
// is the one thing measured to get switched off.
//
// AT MOST ONE FOLLOW-UP PER TURN. Two queued follow-ups would start two turns.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// --------------------------------------------------------------- STE100 rule
//
// There is no mechanical test for Simplified Technical English. The approved
// word list, one-meaning-per-word and no-synonyms are all judgment. So this
// checks exactly the one rule that is arithmetic:
//
//   "Use a maximum of 20 words per sentence in procedures, 25 in descriptive
//    text."
//
// The threshold is 30, not 25, for the same reason ste100-guard.sh uses 30:
// it was set from a corpus measurement of real responses, not from taste. A
// guard that fires on judgment calls becomes wallpaper within a day.
const MAX_WORDS = 30;

// Self-caught mistake admissions. Every pattern needs the AGENT as the subject
// of the error. Deliberately NOT "wrong", "bug", "failed" or "broke" alone —
// nearly every session here is ABOUT a defect, and a guard that fires on
// ordinary defect reporting is noise.
//
// `I did not check` is deliberately absent: on the Claude Code corpus it caught
// honest limitation reporting ("what I did not verify live, so you know the
// edges"), which is behaviour to protect, not to punish. The unambiguous forms
// ("I failed to check", "I should have checked") stay, because both name the
// omission as a fault.
const ADMISSIONS: RegExp[] = [
  /\bI (?:got|had) (?:that|this|it|those|them) wrong\b/i,
  /\bI was wrong\b/i,
  /\bmy (?:mistake|error|fault)\b/i,
  /\bthat was (?:wrong|a mistake|an error)\b/i,
  /\bI mis(?:read|diagnosed|understood|attributed|took|judged|labell?ed|counted|placed)\b/i,
  /\bI (?:incorrectly|wrongly|mistakenly) [a-z]+\b/i,
  /\bI (?:clobbered|overwrote|destroyed|corrupted) \w+/i,
  /\bI (?:failed to|forgot to|neglected to) (?:check|verify|read|test|look|run|ask)\b/i,
  /\bI should have (?:checked|verified|read|tested|looked|run|asked)\b/i,
  /\bcorrection to what I\b/i,
  /\bI (?:assumed|guessed)\b[^.]{0,60}\bwithout\b/i,
];

// ------------------------------------------------------------------ plumbing

function assistantText(messages: any[]): string {
  // Walk backwards to the last assistant message of the turn. Content is
  // either a plain string or an array of typed blocks; only text blocks count.
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (!m || m.role !== "assistant") continue;
    const c = m.content;
    if (typeof c === "string") return c;
    if (Array.isArray(c)) {
      return c
        .filter((b: any) => b && (b.type === "text" || typeof b.text === "string"))
        .map((b: any) => b.text ?? "")
        .join("\n");
    }
    return "";
  }
  return "";
}

// Strip everything the standard does not govern. A fenced block, a table row, a
// path, a URL and a heading are not sentences, and counting their words fires
// the guard on material the model is quoting rather than writing.
//
// ORDER MATTERS. Fences go first, or a fenced block containing a pipe loses
// only its rows and its prose survives as if the model had written it.
function prose(text: string): string[] {
  const noFences = text.replace(/```[\s\S]*?```/g, " ").replace(/`[^`\n]*`/g, " ");
  return noFences
    .split(/\r?\n/)
    .filter((line) => !/^\s*\|/.test(line))          // markdown table rows
    .filter((line) => !/^\s*[-*]\s*\[/.test(line))   // checklists
    .filter((line) => !/^\s*#/.test(line))           // headings
    .filter((line) => !/^\s*>/.test(line))           // block quotes
    .map((line) =>
      line
        .replace(/https?:\/\/\S+/g, " ")
        .replace(/\/[A-Za-z0-9_.@~-]+\/[A-Za-z0-9_./@~-]+/g, " ")
        .replace(/[A-Za-z0-9_.-]+\.(?:ts|tsx|js|jsx|sh|md|nix|json|py|yml|yaml)\b/g, " ")
        // Emphasis markers sit BETWEEN a full stop and the next capital, so
        // they defeat the sentence split: "...not one.** **Run them" never
        // matches ". " + capital, and three short sentences count as one long
        // run. Measured on the Claude Code corpus as a false positive.
        .replace(/\*\*/g, " ")
        .replace(/[*_]/g, " "),
    );
}

// A hand-written scanner, not a regex split. A sentence ends at . ! or ? only
// when the next non-space character is a capital, or the text ends. That keeps
// "v1.27", "3.5 MB" and "e.g. foo" whole — splitting those cuts one long
// sentence into two short ones and hides the violation.
//
// ONE LINE AT A TIME. Joining the whole turn is a false-positive factory: a
// bullet list carries no terminal punctuation, so seven bullets become one
// 88-word "sentence" — and a vertical list is what the standard PRESCRIBES for
// more than three items.
function longestSentence(lines: string[]): { count: number; text: string } {
  let best = { count: 0, text: "" };
  const consider = (s: string) => {
    const count = s.split(/\s+/).filter((w) => /[A-Za-z]/.test(w)).length;
    if (count > best.count) best = { count, text: s.trim() };
  };
  for (const line of lines) {
    let start = 0;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (c !== "." && c !== "!" && c !== "?") continue;
      let j = i + 1;
      while (j < line.length && line[j] === " ") j++;
      if (j < line.length && !/[A-Z]/.test(line[j])) continue;
      consider(line.slice(start, i + 1));
      start = j;
      i = j - 1;
    }
    if (start < line.length) consider(line.slice(start));
  }
  return best;
}

function sentenceAround(text: string, index: number): string {
  const from = Math.max(0, text.lastIndexOf(".", index) + 1);
  let to = text.indexOf(".", index);
  if (to < 0) to = text.length;
  return text.slice(from, to + 1).trim().slice(0, 220);
}

export default function (pi: ExtensionAPI) {
  // Session-scoped case ledger. The extension instance lives for the session,
  // so a Set is the whole mechanism — no file, no cleanup.
  const adjudicated = new Set<string>();

  pi.on("agent_end", async (event: any) => {
    let text = "";
    try {
      text = assistantText(event?.messages ?? []);
    } catch {
      return; // Fail open, always.
    }
    if (!text.trim()) return;

    // ---- channel 1: the model admitted a specific error of its own ---------
    for (const pattern of ADMISSIONS) {
      const m = pattern.exec(text);
      if (!m) continue;
      const sentence = sentenceAround(text, m.index);
      const fp = `mistake:${sentence}`;
      if (adjudicated.has(fp)) break;
      adjudicated.add(fp);
      pi.sendMessage(
        {
          customType: "hwc-stop-guard",
          display: true,
          content:
            `YOU DESCRIBED YOUR OWN MISTAKE AND DID NOT RECORD IT — you wrote ` +
            `"${sentence}", and no ledger entry was written.\n\n` +
            `  ~/.claude-config/bin/log-mistake --families\n` +
            `  ~/.claude-config/bin/log-mistake --family <slug> --title <slug> \\\n` +
            `    --did "..." --true "..." --why "..." --rule "..."\n\n` +
            `Run --families first and reuse a family slug. Minting a near-synonym ` +
            `is what kills the grouping. The four answers are separate on purpose: ` +
            `what you DID, what was actually TRUE, the reasoning error that ` +
            `produced the gap, and the rule that would have prevented it. Use ` +
            `--channel self-caught. Record the cause, not the fix you already ` +
            `shipped.\n\nIf this is a false positive — you are quoting the ledger, ` +
            `documenting the system, or restating an error already logged — clear ` +
            `it with \`log-mistake --dismiss "<why, >=20 chars>"\`.`,
        },
        { triggerTurn: true, deliverAs: "followUp" },
      );
      return; // One follow-up per turn.
    }

    // ---- channel 2: the STE100 sentence-length ceiling ---------------------
    const longest = longestSentence(prose(text));
    if (longest.count <= MAX_WORDS) return;
    const fp = `ste100:${longest.text.slice(0, 220)}`;
    if (adjudicated.has(fp)) return;
    adjudicated.add(fp);
    pi.sendMessage(
      {
        customType: "hwc-stop-guard",
        display: true,
        content:
          `STANDING INSTRUCTION NOT APPLIED — write every response in ASD-STE100 ` +
          `Simplified Technical English. Your longest sentence runs ` +
          `${longest.count} words. The ceiling is 25 for descriptive text and 20 ` +
          `for procedures.\n\nThe sentence: "${longest.text.slice(0, 220)}"\n\n` +
          `Rewrite the response now. Split each long sentence into short ones. ` +
          `Give one instruction per sentence. Use the active voice and name the ` +
          `agent of each action. Do not use phrasal verbs. Name what a pronoun ` +
          `refers to. Use a vertical list for more than three items.\n\n` +
          `This gate checks only the arithmetic part of the rule. A response that ` +
          `passes is not automatically compliant.`,
      },
      { triggerTurn: true, deliverAs: "followUp" },
    );
  });
}
