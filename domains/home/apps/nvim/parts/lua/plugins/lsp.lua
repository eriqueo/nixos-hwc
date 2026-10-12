-- domains/home/apps/nvim/parts/lua/plugins/lsp.lua
-- Using native vim.lsp (Neovim 0.11+)

-- Get cmp capabilities if available
local capabilities = vim.lsp.protocol.make_client_capabilities()
local cmp_ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if cmp_ok then
  capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
end

-- Keymaps applied when LSP attaches
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
  callback = function(ev)
    local opts = { buffer = ev.buf, remap = false }

    -- Navigation
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
    vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
    vim.keymap.set("n", "gt", vim.lsp.buf.type_definition, opts)

    -- Documentation
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("i", "<C-h>", vim.lsp.buf.signature_help, opts)

    -- Workspace

    -- Diagnostics
    vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
    vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)

    -- Code actions

    -- Formatting
  end,
})

-- Diagnostic configuration
vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
})

local signs = { Error = " ", Warn = " ", Hint = " ", Info = " " }
for type, icon in pairs(signs) do
  local hl = "DiagnosticSign" .. type
  vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
end

-- Server configurations
local servers = {
  lua_ls = {
    settings = {
      Lua = {
        runtime = { version = "LuaJIT" },
        diagnostics = { globals = { "vim" } },
        workspace = { library = vim.api.nvim_get_runtime_file("", true) },
        telemetry = { enable = false },
      },
    },
  },
  nil_ls = { settings = { ["nil"] = { nix = { flake = { autoArchive = true } } } } },
  pyright = {},
  ts_ls = {},
  rust_analyzer = {
    settings = {
      ["rust-analyzer"] = {
        cargo = { allFeatures = true },
      },
    },
  },
  gopls = {},
  clangd = {
    cmd = { "clangd", "--offset-encoding=utf-16" },
  },
}

-- Use vim.lsp.config if available (Neovim 0.11+), fallback to lspconfig
if vim.lsp.config then
  -- Modern API
  for name, config in pairs(servers) do
    config.capabilities = capabilities
    vim.lsp.config(name, config)
  end
  vim.lsp.enable(vim.tbl_keys(servers))
else
  -- Fallback for older Neovim
  local lspconfig_ok, lspconfig = pcall(require, "lspconfig")
  if lspconfig_ok then
    for name, config in pairs(servers) do
      config.capabilities = capabilities
      if lspconfig[name] then
        lspconfig[name].setup(config)
      end
    end
  end
end
