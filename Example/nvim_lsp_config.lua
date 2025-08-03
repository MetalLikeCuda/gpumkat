-- Metal LSP Configuration for Neovim
local lspconfig = require("lspconfig")
local configs = require("lspconfig.configs")

if not configs.metal_lsp then
	configs.metal_lsp = {
		default_config = {
			cmd = { "gpumkat", "-lsp" },
			filetypes = { "metal" },
			root_dir = lspconfig.util.root_pattern(".git", ".gpumkat"),
			settings = {},
			init_options = {
				enable_diagnostics = true,
				enable_completions = true,
				enable_hover = true,
				enable_formatting = true,
				enable_semantic_tokens = true,
				enable_signature_help = true,
			},
		},
		docs = {
			description = "Metal Language Server for GPU shader development",
		},
	}
end

-- Setup the Metal LSP
lspconfig.metal_lsp.setup({
	on_attach = function(client, bufnr)
		-- Enable completion triggered by <c-x><c-o>
		vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")

		-- Enable semantic tokens if supported
		if client.server_capabilities.semanticTokensProvider then
			vim.lsp.semantic_tokens.start(bufnr, client.id)
		end

		-- Mappings
		local opts = { noremap = true, silent = true, buffer = bufnr }

		-- Navigation
		vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
		vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
		vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
		vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
		vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)

		-- Code actions
		vim.keymap.set("n", "<space>rn", vim.lsp.buf.rename, opts)
		vim.keymap.set("n", "<space>ca", vim.lsp.buf.code_action, opts)
		vim.keymap.set("n", "<space>f", function()
			vim.lsp.buf.format({ async = true })
		end, opts)

		-- Diagnostics
		vim.keymap.set("n", "<space>e", vim.diagnostic.open_float, opts)
		vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
		vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
		vim.keymap.set("n", "<space>q", vim.diagnostic.setloclist, opts)
	end,

	flags = {
		debounce_text_changes = 150,
	},

	-- Enhanced capabilities
	capabilities = vim.tbl_deep_extend("force", require("cmp_nvim_lsp").default_capabilities(), {
		textDocument = {
			semanticTokens = {
				requests = {
					range = false,
					full = {
						delta = false,
					},
				},
				tokenTypes = {
					"namespace",
					"type",
					"class",
					"enum",
					"interface",
					"struct",
					"typeParameter",
					"parameter",
					"variable",
					"property",
					"enumMember",
					"event",
					"function",
					"method",
					"macro",
					"keyword",
					"modifier",
					"comment",
					"string",
					"number",
					"regexp",
					"operator",
				},
				tokenModifiers = {
					"declaration",
					"definition",
					"readonly",
					"static",
					"deprecated",
					"abstract",
					"async",
					"modification",
					"documentation",
					"defaultLibrary",
				},
			},
		},
	}),
})

-- Setup nvim-cmp for autocompletion
local cmp_status, cmp = pcall(require, "cmp")
if cmp_status then
	cmp.setup({
		sources = cmp.config.sources({
			{ name = "nvim_lsp", priority = 1000 },
			{ name = "buffer", priority = 500 },
			{ name = "path", priority = 250 },
		}),
		formatting = {
			format = function(entry, vim_item)
				vim_item.menu = ({
					nvim_lsp = "[LSP]",
					buffer = "[Buffer]",
					path = "[Path]",
				})[entry.source.name]
				return vim_item
			end,
		},
		experimental = {
			ghost_text = true,
		},
	})
end

-- Metal file type detection and configuration
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = { "*.metal" },
	callback = function()
		vim.bo.filetype = "metal"
		vim.bo.commentstring = "// %s"
		vim.bo.expandtab = true
		vim.bo.shiftwidth = 2
		vim.bo.tabstop = 2
		vim.bo.softtabstop = 2
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	pattern = "metal",
	callback = function(args)
		local bufnr = args.buf

		-- Define Metal-specific highlight groups that work with semantic tokens
		local highlights = {
			["@lsp.type.keyword.metal"] = { link = "Keyword" },
			["@lsp.type.function.metal"] = { link = "Function" },
			["@lsp.type.method.metal"] = { link = "Function" },
			["@lsp.type.type.metal"] = { link = "Type" },
			["@lsp.type.struct.metal"] = { link = "Structure" },
			["@lsp.type.variable.metal"] = { link = "Identifier" },
			["@lsp.type.parameter.metal"] = { link = "Parameter" },
			["@lsp.type.string.metal"] = { link = "String" },
			["@lsp.type.number.metal"] = { link = "Number" },
			["@lsp.type.comment.metal"] = { link = "Comment" },
			["@lsp.type.operator.metal"] = { link = "Operator" },
			["@lsp.mod.defaultLibrary.metal"] = { link = "Special" },
			["@lsp.mod.readonly.metal"] = { link = "Constant" },
		}

		for group, opts in pairs(highlights) do
			vim.api.nvim_set_hl(0, group, opts)
		end

		-- Fallback to C++ syntax for non-semantic highlighting
		if vim.fn.exists("syntax_on") then
			vim.cmd("syntax clear")
			vim.cmd("runtime! syntax/cpp.vim")

			vim.cmd([[
        syntax keyword metalKeyword kernel vertex fragment
        syntax keyword metalKeyword device constant threadgroup thread
        syntax keyword metalKeyword texture1d texture2d texture3d texturecube
        syntax keyword metalKeyword sampler buffer array
        syntax keyword metalType float2 float3 float4 int2 int3 int4
        syntax keyword metalType uint2 uint3 uint4 half2 half3 half4
        syntax keyword metalType float2x2 float3x3 float4x4
        syntax keyword metalBuiltin dot cross normalize length distance
        syntax keyword metalBuiltin pow sin cos tan sqrt abs mix clamp
        syntax keyword metalBuiltin sample read write gather
        
        highlight link metalKeyword Keyword
        highlight link metalType Type  
        highlight link metalBuiltin Function
      ]])
		end
	end,
})

-- Diagnostic configuration
vim.diagnostic.config({
	virtual_text = {
		prefix = "●",
		source = "always",
	},
	float = {
		source = "always",
		border = "rounded",
	},
	signs = true,
	underline = true,
	update_in_insert = false,
	severity_sort = true,
})

-- Define diagnostic signs
local signs = { Error = "󰅚 ", Warn = "󰀪 ", Hint = "󰌶 ", Info = " " }
for type, icon in pairs(signs) do
	local hl = "DiagnosticSign" .. type
	vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
end

-- Auto-format on save
vim.api.nvim_create_autocmd("BufWritePre", {
	pattern = "*.metal",
	callback = function()
		vim.lsp.buf.format({ async = false })
	end,
})
