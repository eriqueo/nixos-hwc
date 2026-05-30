# domains/ai/personas/library/_defaults.nix
#
# Default values for every persona. Per-persona .nix files override
# selectively via attribute-set merge:
#
#   import ../_defaults.nix // {
#     model = "cpu";
#     temperature = 0.6;
#     # ...only what differs
#   }
#
# Adding a new persona field here is automatically default-safe for every
# existing persona — they simply inherit the new key.
{
  model = "gpu";          # "gpu" | "cpu"
  temperature = 0.4;
  topP = 0.95;
  maxTokens = 256;
  description = "";

  # Memory & knowledge gates (consumed by persona-daemon)
  useMemory = false;      # persist conversation turns?
  useKnowledge = false;   # retrieve from brain vault at chat time?
  knowledgeTopK = 0;      # how many top chunks to inject when useKnowledge=true
}
