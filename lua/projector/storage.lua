local M = {}

local uv = vim.uv or vim.loop
local json = vim.json or { encode = vim.fn.json_encode, decode = vim.fn.json_decode }

local function data_dir()
	local dir = vim.fn.stdpath("data") .. "/projector"
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	return dir
end

local function db_path()
	return data_dir() .. "/projects.json"
end

local function read_file(path)
	local fd = uv.fs_open(path, "r", 438) -- 0666
	if not fd then
		return nil
	end
	local stat = uv.fs_fstat(fd)
	local data = uv.fs_read(fd, stat.size, 0)
	uv.fs_close(fd)
	return data
end

local function write_file(path, data)
	local fd = uv.fs_open(path, "w", 420) -- 0644
	if not fd then
		return false, "open failed"
	end
	uv.fs_write(fd, data, 0)
	uv.fs_close(fd)
	return true
end

function M.load()
	local path = db_path()
	if vim.fn.filereadable(path) == 0 then
		return { projects = {} }
	end
	local ok, decoded = pcall(function()
		local txt = read_file(path)
		if not txt or txt == "" then
			return { projects = {} }
		end
		local tbl = json.decode(txt)
		if not tbl or not tbl.projects then
			return { projects = {} }
		end
		return tbl
	end)
	return ok and decoded or { projects = {} }
end

function M.save(db)
	db = db or { projects = {} }
	local ok, encoded = pcall(function()
		return json.encode(db)
	end)
	if not ok then
		return false, "json encode failed"
	end
	return write_file(db_path(), encoded)
end

local function normalize_path(path)
	path = vim.fn.fnamemodify(path, ":p")
	-- remove trailing slash
	if vim.endswith(path, "/") or vim.endswith(path, "\\") then
		path = path:sub(1, #path - 1)
	end
	return path
end

function M.upsert_project(entry)
	local db = M.load()
	entry.path = normalize_path(entry.path)
	-- replace if exists
	local replaced = false
	for i, p in ipairs(db.projects) do
		if p.path == entry.path then
			db.projects[i] = vim.tbl_deep_extend("force", p, entry)
			replaced = true
			break
		end
	end
	if not replaced then
		table.insert(db.projects, entry)
	end
	M.save(db)
end

function M.remove_project(path)
	local db = M.load()
	path = normalize_path(path)
	local new = {}
	for _, p in ipairs(db.projects) do
		if p.path ~= path then
			table.insert(new, p)
		end
	end
	db.projects = new
	M.save(db)
end

function M.find_by_name(name)
	if not name or name == "" then return nil end
	for _, p in ipairs(M.get_projects()) do
	  if p.name == name then return p end
	end
  end

function M.remove_by_name(name)
	local db = M.load()
	local new = {}
	for _, p in ipairs(db.projects) do
		if p.name ~= name then table.insert(new, p) end
	end
	db.projects = new
	M.save(db)
end

function M.get_projects()
	local db = M.load()
	table.sort(db.projects, function(a, b)
		return (a.name or a.path) < (b.name or b.path)
	end)
	return db.projects
end

function M.find_by_path(path)
	path = path and normalize_path(path) or nil
	for _, p in ipairs(M.get_projects()) do
		if p.path == path then
			return p
		end
	end
end

return M
