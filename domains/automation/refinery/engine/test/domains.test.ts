import { test } from "node:test";
import assert from "node:assert/strict";
import { classifyDomain, resolveDomain, domainOf, DomainRegistry } from "../src/domains.js";

const REG: DomainRegistry = {
  domains: [
    { key: "kidpix", label: "KidPix", color: "#cf995f", match: ["kidpix"] },
    { key: "nixos", label: "NixOS", color: "#5e81ac", match: ["nixos", "nixos repo"] },
    { key: "datax", label: "DataX", color: "#b16286", match: ["datax"] },
  ],
  fallback: { key: "misc", label: "Misc", color: "#a7aaad", match: [] },
};

test("classifyDomain reads the leading prefix (the _ideas.md convention)", () => {
  assert.equal(classifyDomain("kidpix: funny custom sounds", REG), "kidpix");
  assert.equal(classifyDomain("nixos repo: orphaned-options audit", REG), "nixos");
  assert.equal(classifyDomain("DataX: distill raw logs", REG), "datax", "case-insensitive");
  assert.equal(classifyDomain("kidpix (big): SlideShow mode", REG), "kidpix", "parenthetical stripped");
});

test("classifyDomain falls back when there's no clear prefix", () => {
  assert.equal(classifyDomain("just a sentence with no colon prefix at all", REG), "misc");
  assert.equal(classifyDomain("unknownthing: do something", REG), "misc");
});

test("resolveDomain / domainOf resolve color + manual override", () => {
  assert.equal(resolveDomain("nixos", REG).color, "#5e81ac");
  assert.equal(resolveDomain("nope", REG).key, "misc", "unknown key → fallback");
  // domainOf classifies from payload.input …
  assert.equal(domainOf({ payload: { input: "kidpix: a thing" } }, REG).key, "kidpix");
  // … but a manual payload.domain override wins.
  assert.equal(domainOf({ payload: { input: "kidpix: a thing", domain: "datax" } }, REG).key, "datax");
});
