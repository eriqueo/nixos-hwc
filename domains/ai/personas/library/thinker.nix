import ./_defaults.nix // {
  model = "cpu";
  temperature = 0.6;
  maxTokens = 1024;
  description = "Multi-step reasoning via the 24B MoE on CPU — slower, deeper";
  useMemory = true;
}
