local storage = require("projector.storage")
local ui = require("projector.ui")
local runner = require("projector.runner")

local M = {}

local CONFIG = {
	projects_dir = nil, -- e.g. "~/Projects" ; if nil, :ProjectNew requires --in
	mkdir = true, -- create missing parent dirs
	git_init = false, -- optionally run `git init` when creating a project dir
}

local function set_config(user)
	user = user or {}
	CONFIG = vim.tbl_deep_extend("force", CONFIG, user)
end
local uv = vim.uv or vim.loop

local function expanduser(p)
	if not p or p == "" then
		return p
	end
	if p:sub(1, 2) == "~/" then
		return vim.fn.expand(p)
	end
	return p
end

local function get_types()
	local types = {
		"C",
		"C++",
		"C#",
		"Java",
		"Javascript",
		"Python",
		"TypeScript",
		"Haskell",
		"Rust",
		"Zig",
	}

	table.sort(types)

	return types
end

local function select_type(on_choice)
	local types = get_types()
	ui.select(types, { prompt = "Select project type:" }, function(type)
		on_choice(type)
	end)
end

local function select_project(prompt, on_choice)
	local projects = storage.get_projects()
	if #projects == 0 then
	  return ui.notify("No projects saved yet.", vim.log.levels.WARN)
	end
  
	-- Build label ↔ value map for the picker
	local items, labels = {}, {}
	for _, p in ipairs(projects) do
	  local label = string.format("%s — %s", p.name or p.path, p.path)
	  table.insert(items, { label = label, value = p })
	  table.insert(labels, label)
	end
  
	ui.select(labels, { prompt = prompt or "Select project:" }, function(choice_label)
	  if not choice_label then return on_choice(nil) end
	  for _, it in ipairs(items) do
		if it.label == choice_label then
		  return on_choice(it.value)
		end
	  end
	  on_choice(nil)
	end)
  end
  

local function normpath(p)
	if not p or p == "" then
		return p
	end
	p = vim.fn.fnamemodify(expanduser(p), ":p")
	if vim.endswith(p, "/") or vim.endswith(p, "\\") then
		p = p:sub(1, #p - 1)
	end
	return p
end

local function joinpath(a, b)
	a = normpath(a)
	if not a or a == "" then
		return normpath(b)
	end
	return normpath(a .. "/" .. b)
end

local function ensure_dir(dir)
	dir = normpath(dir)
	if vim.fn.isdirectory(dir) == 1 then
		return true
	end
	if not CONFIG.mkdir then
		return false, "Parent directory does not exist: " .. dir
	end
	vim.fn.mkdir(dir, "p")
	return true
end

local function run_git_init(dir)
	if not CONFIG.git_init then
		return
	end
	if vim.fn.executable("git") ~= 1 then
		return
	end
	-- non-blocking is fine, but simple works too:
	vim.fn.system({ "git", "-C", dir, "init" })
end

local function cwd()
	return vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
end

local function parse_new_args(raw)
	local parts = vim.fn.split(raw, " ")
	local opts = { name = nil, parent = nil, run = nil, type = nil }
	local i = 1
	while i <= #parts do
		local tok = parts[i]
		if tok == "--in" then
			i = i + 1
			opts.parent = parts[i]
		elseif tok == "--run" then
			i = i + 1
			opts.run = parts[i]
		elseif tok == "--type" then
			i = i + 1
			opts.type = parts[i]
		else
			-- first bare token = name
			if not opts.name then
				opts.name = tok
			else
				-- allow spaces in name if user quoted poorly: glue rest
				opts.name = opts.name .. " " .. tok
			end
		end
		i = i + 1
	end
	return opts
end

local function open_dir(dir)
	-- open dir in current instance
	vim.cmd("cd " .. vim.fn.fnameescape(dir))
	ui.notify("Changed directory to " .. dir)
	-- optional: open file tree if you use one
end

function M.create(opts)
	opts = opts or {}
	local path = opts.path or cwd()
	local name = opts.name or ui.input("Project name?", vim.fn.fnamemodify(path, ":t"))
	if name == "" then
		name = vim.fn.fnamemodify(path, ":t")
	end
	local run = opts.run or ui.input("Run command? (optional)", "", { cancelreturn = "" })
	storage.upsert_project({ name = name, path = path, run = run })
	ui.notify("Project saved: " .. name)
end

local function detect_run_command(dir)
	local candidates = {
		{ file = "package.json", cmd = "npm run dev" },
		{ file = "Cargo.toml", cmd = "cargo run" },
		{ file = "Makefile", cmd = "make" },
		{ file = "pyproject.toml", cmd = "python -m app" },
	}
	for _, c in ipairs(candidates) do
		if vim.fn.filereadable(dir .. "/" .. c.file) == 1 then
			return c.cmd
		end
	end
end

local function finalize_create(dir, name, run, ptype)
	-- Register
	storage.upsert_project({ name = name, path = dir, run = run, type = ptype })

	-- cd + feedback
	vim.cmd("cd " .. vim.fn.fnameescape(dir))
	ui.notify(("Created project '%s' at %s"):format(name, dir))
end

function M.create_new_from_cli(raw_args)
	local args = parse_new_args(raw_args or "")
	local parent = args.parent or CONFIG.projects_dir
	if not parent or parent == "" then
		ui.notify("No parent dir given. (Defaulting to: ~/Projects/) set projects_dir in setup().", vim.log.levels.WARN)
		CONFIG.projects_dir = "~/Projects/"
	end
	parent = normpath(parent)

	-- Ask for name if not provided
	local name = args.name or ui.input("New project name?", "")
	if not name or name == "" then
		return ui.notify("Project name is required.", vim.log.levels.ERROR)
	end

	local dir = joinpath(parent, name)
	local ok, err = ensure_dir(dir)
	if not ok then
		return ui.notify(err, vim.log.levels.ERROR)
	end

	-- Optional git init
	run_git_init(dir)

	-- Run command: arg > detected > prompt
	local run = args.run
	if not run or run == "" then
		run = detect_run_command(dir) or ui.input("Run command? (optional)", "")
	end

	local type = args.type
	if not type or type == "" then
		select_type(args)
	end

	if args.type and args.type ~= "" then
		return finalize_create(dir, name, run, args.type)
	end

	-- Otherwise, ask and finish in the callback.
	select_type(function(choice)
		if not choice or choice == "" then
			-- user cancelled; still create without a type (or bail if you prefer)
			return finalize_create(dir, name, run, nil)
		end
		finalize_create(dir, name, run, choice)
	end)
end

function M.list_and_open()
	select_project("Open Project: ", function(p)
		if not p then return end
		open_dir(p.path)
	end)
end


function M.delete(opts)
	opts = opts or {}
	local arg  = opts.arg   -- can be path or name
	local bang = opts.bang
  
	local function do_delete(p)
	  if not p then return end
	  if not bang then
		local ok = ui.confirm(("Delete project '%s'?"):format(p.name or p.path))
		if not ok then return end
	  end
	  -- Prefer name delete if available (avoids path normalization issues)
	  if p.name and storage.find_by_name and storage.find_by_name(p.name) then
		storage.remove_by_name(p.name)
	  else
		storage.remove_project(p.path)
	  end
	  ui.notify(("Deleted project: %s"):format(p.name or p.path))
	end
  
	-- If user provided an argument, try resolve directly first
	if arg and arg ~= "" then
	  local target = storage.find_by_path(arg) or (storage.find_by_name and storage.find_by_name(arg)) or nil
	  if target then
		return do_delete(target)
	  end
	  -- Fall back to picker if not found
	  return select_project("Delete project:", do_delete)
	end
  
	-- No arg → let the user pick
	return select_project("Delete project:", do_delete)
  end
  

function M.open(opts)
	opts = opts or {}
	if opts.path then
		open_dir(opts.path)
		return
	end
	return M.list_and_open()
end

function M.run(opts)
	opts = opts or {}
	local target = opts.path or cwd()
	local proj = storage.find_by_path(target)
	if not proj then
		return ui.notify("Project not found for " .. target, vim.log.levels.WARN)
	end
	runner.run_in_terminal(proj.run, proj.path)
end

-- User commands
function M.setup(user_opts)
	set_config(user_opts or {})
	vim.api.nvim_create_user_command("ProjectCreate", function(cmd)
		local args = vim.fn.split(cmd.args, " ")
		local path = args[1] ~= nil and args[1] or nil
		M.create({ path = path })
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("ProjectNew", function(cmd)
		M.create_new_from_cli(cmd.args)
	end, { nargs = "*" })

	vim.api.nvim_create_user_command("ProjectList", function()
		M.list_and_open()
	end, {})

	vim.api.nvim_create_user_command("ProjectOpen", function(cmd)
		local path = cmd.args ~= "" and cmd.args or nil
		M.open({ path = path })
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("ProjectDelete", function(cmd)
		M.delete({ arg = cmd.args, bang = cmd.bang })
	end, { nargs = "?", bang = true })

	vim.api.nvim_create_user_command("ProjectRun", function(cmd)
		local path = cmd.args ~= "" and cmd.args or nil
		M.run({ path = path })
	end, { nargs = "?" })
end

return M
