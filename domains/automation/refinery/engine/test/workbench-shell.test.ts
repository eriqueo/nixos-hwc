// The board renders the shared Workbench shell (vendored shell.css.ts) and
// switches areas through the Nix-produced registry, parsed once at the edge.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { loadWorkbenchRegistry, parseWorkbenchRegistry } from "../src/shells/workbench.js";
import { renderReference, setWorkbenchRegistry } from "../src/shells/render.js";

const REGISTRY = {
  product: "HWC Workbench",
  home: "https://workbench.example/",
  areas: [
    { id: "crm", label: "CRM", available: true, href: "https://crm.example/" },
    { id: "refinery", label: "Refinery", available: true, href: "https://refinery.example/" },
    { id: "event-scout", label: "Event Scout", available: false, href: null },
  ],
};

test("parseWorkbenchRegistry rejects malformed shapes and duplicate ids", () => {
  assert.throws(() => parseWorkbenchRegistry(null));
  assert.throws(() => parseWorkbenchRegistry({ home: "x" }));
  assert.throws(() => parseWorkbenchRegistry({ home: "x", areas: [{ id: "a" }] }));
  assert.throws(() => parseWorkbenchRegistry({ ...REGISTRY, areas: [REGISTRY.areas[0], REGISTRY.areas[0]] }), /duplicate/);
  assert.equal(parseWorkbenchRegistry(REGISTRY).areas.length, 3);
});

test("loadWorkbenchRegistry degrades to null on a missing or bad file", () => {
  const warnings: string[] = [];
  assert.equal(loadWorkbenchRegistry(undefined, (m) => warnings.push(m)), null);
  assert.equal(loadWorkbenchRegistry("/nonexistent/areas.json", (m) => warnings.push(m)), null);
  const dir = mkdtempSync(join(tmpdir(), "wb-"));
  writeFileSync(join(dir, "bad.json"), "{not json");
  assert.equal(loadWorkbenchRegistry(join(dir, "bad.json"), (m) => warnings.push(m)), null);
  writeFileSync(join(dir, "areas.json"), JSON.stringify(REGISTRY));
  assert.equal(loadWorkbenchRegistry(join(dir, "areas.json"), (m) => warnings.push(m))?.areas.length, 3);
  assert.equal(warnings.length, 2, "one warning per unreadable file, none for absent config");
});

test("layout renders the shared shell and a registry-driven area switcher", () => {
  setWorkbenchRegistry(parseWorkbenchRegistry(REGISTRY));
  try {
    const html = renderReference([]);
    assert.ok(html.includes('class="wb-shell"') && html.includes('class="wb-rail"'), "shell contract markup");
    assert.ok(html.includes("--color-copper") && html.includes(".wb-rail-item"), "palette + shell css inlined");
    assert.ok(html.includes('data-registry="ready"'));
    assert.ok(html.includes('<option value="https://crm.example/">CRM</option>'), "sibling area navigates to its origin");
    assert.ok(html.includes('<option value="" selected>Refinery</option>'), "current area is the selected no-op");
    assert.ok(html.includes("Event Scout (not deployed)") && html.includes("disabled"), "unavailable area is listed, not linked");
    assert.ok(html.includes('href="https://workbench.example/"'), "brand links to the registry home");
    assert.ok(html.includes('<span class="wb-rail-label" id="wb-rail-group-work">Work views</span>'));
    assert.ok(html.includes('<span class="wb-rail-text">Overnight</span>') && html.includes('<span class="wb-rail-text">Reviews</span>'));
  } finally {
    setWorkbenchRegistry(null);
  }
  const degraded = renderReference([]);
  assert.ok(degraded.includes('data-registry="unavailable"'));
  assert.ok(degraded.includes("Workbench home (registry unavailable)"), "home is always offered");
  assert.ok(degraded.includes('<option value="" selected>Refinery</option>'));
});
