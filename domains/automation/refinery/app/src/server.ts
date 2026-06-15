// domains/automation/refinery/app/src/server.ts
//
// Read-only HTTP shell over the hopper parser. Late-bound config: port and
// vault dir come from the environment (set by the NixOS service), never
// hardcoded. Renders the full board on every request; the page meta-refreshes.

import { createServer } from "node:http";
import { readCards, readIdeas } from "./parse.ts";
import { renderPage } from "./render.ts";

const PORT = Number(process.env.REFINERY_PORT || 8060);
const VAULT =
  process.env.REFINERY_VAULT_DIR || `${process.env.HOME}/900_vaults/brain`;

const server = createServer((req, res) => {
  if (req.url === "/healthz") {
    res.writeHead(200, { "content-type": "text/plain" });
    res.end("ok");
    return;
  }
  try {
    const cards = readCards(VAULT);
    const ideas = readIdeas(VAULT);
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    res.end(renderPage(cards, ideas));
  } catch (e) {
    res.writeHead(500, { "content-type": "text/plain" });
    res.end("refinery board error: " + (e as Error).message);
  }
});

server.listen(PORT, () => {
  console.log(`refinery board listening on :${PORT} (vault=${VAULT})`);
});
