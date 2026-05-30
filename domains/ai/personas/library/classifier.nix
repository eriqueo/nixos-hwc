import ./_defaults.nix // {
  temperature = 0.1;
  topP = 0.9;
  maxTokens = 64;
  description = "Classify text into one of the supplied labels — single-token reply";
  # stateless transformer; persisting its I/O would pollute RAG with label tokens
  useMemory = false;
}
