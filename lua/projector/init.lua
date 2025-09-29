local storage = require("projector.storage")
local ui = require("projector.ui")
local runner = require("projector.runner")

local M = {}

local function cwd()
	return vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
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

function M.list_and_open()
	local projects = storage.get_projects()
	if #projects == 0 then
		return ui.notify("No projects saved yet.", vim.log.levels.WARN)
	end
	local labels = vim.tbl_map(function(p)
		return string.format("%s — %s", p.name or p.path, p.path)
	end, projects)
	ui.select(labels, { prompt = "Open project:" }, function(label)
		if not label then
			return
		end
		local idx = vim.fn.index(labels, label) + 1
		local sel = projects[idx]
		open_dir(sel.path)
	end)
end

function M.remove(opts)
	opts = opts or {}
	local target = opts.path or cwd()
	local proj = storage.find_by_path(target)
	if not proj then
		return ui.notify("Project not found for " .. target, vim.log.levels.WARN)
	end
	storage.remove_project(target)
	ui.notify("Removed project: " .. (proj.name or proj.path))
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
	user_opts = user_opts or {}
	vim.api.nvim_create_user_command("ProjectCreate", function(cmd)
		local args = vim.fn.split(cmd.args, " ")
		local path = args[1] ~= nil and args[1] or nil
		M.create({ path = path })
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("ProjectList", function()
		M.list_and_open()
	end, {})

	vim.api.nvim_create_user_command("ProjectOpen", function(cmd)
		local path = cmd.args ~= "" and cmd.args or nil
		M.open({ path = path })
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("ProjectRemove", function(cmd)
		local path = cmd.args ~= "" and cmd.args or nil
		M.remove({ path = path })
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("ProjectRun", function(cmd)
		local path = cmd.args ~= "" and cmd.args or nil
		M.run({ path = path })
	end, { nargs = "?" })
end

return M
