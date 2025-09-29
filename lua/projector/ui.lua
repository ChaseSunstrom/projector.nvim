local M = {}

function M.input(prompt, default, opts)
	opts = opts or {}
	return vim.fn.input({ prompt = prompt .. " ", default = default or "", cancelreturn = opts.cancelreturn or "" })
end

function M.confirm(msg, default_yes)
	local choices = default_yes and "[Y/n]" or "[y/N]"
	local ans = vim.fn.input({ prompt = msg .. " " .. choices .. " " })
	ans = ans:lower()
	if ans == "" then return default_yes and true or false end
	return ans == "y" or ans == "yes"
end

function M.select(items, opts, on_choice)
	opts = opts or { prompt = "Select:" }
	if vim.ui and vim.ui.select then
		vim.ui.select(items, opts, on_choice)
	else
		-- simple fallback with inputlist
		local lines = { opts.prompt }
		for i, it in ipairs(items) do
			table.insert(lines, string.format("%d. %s", i, it))
		end
		local idx = vim.fn.inputlist(lines)
		if idx < 1 or idx > #items then
			return on_choice(nil)
		end
		on_choice(items[idx])
	end
end

function M.notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "Projector" })
end

return M
