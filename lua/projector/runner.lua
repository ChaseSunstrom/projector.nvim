local M = {}

-- Open a terminal in a split and run the command
function M.run_in_terminal(cmd, cwd)
	if not cmd or cmd == "" then
		return require("projector.ui").notify("No run command set for this project.", vim.log.levels.WARN)
	end
	-- horizontal split
	vim.cmd("split")
	vim.cmd("terminal")
	local bufnr = vim.api.nvim_get_current_buf()
	if cwd and cwd ~= "" then
		vim.fn.chansend(vim.b.terminal_job_id, "cd " .. vim.fn.fnameescape(cwd) .. "\n")
	end
	vim.fn.chansend(vim.b.terminal_job_id, cmd .. "\n")
	-- enter insert in terminal
	vim.cmd("startinsert")
	return bufnr
end

return M
