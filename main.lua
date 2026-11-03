--- @since 26.04.03
-- Open AI coding tools in a new terminal tab from yazi.

local M = {}

local state = {
	tools = {
		claude = { cmd = "claude" },
		codex  = { cmd = "codex" },
		amp    = { cmd = "amp" },
		gemini = { cmd = "gemini" },
		aider  = { cmd = "aider" },
	},
	terminal = nil, -- nil = auto-detect
}

local cached_terminal = nil
local cached_kitty_listen = nil

local KITTY_SOCKET_CANDIDATES = {
	"unix:/tmp/mykitty",
}

local function error_message(err)
	if err == nil then
		return "unknown error"
	end
	local ok, message = pcall(function()
		return tostring(err)
	end)
	if ok and type(message) == "string" and message ~= "" then
		return message
	end
	return "unknown error"
end

local function spawn_piped(name, args)
	local ok, child, err = pcall(function()
		return Command(name)
			:arg(args)
			:stdout(Command.PIPED)
			:stderr(Command.PIPED)
			:spawn()
	end)
	if ok then
		return child, error_message(err)
	end
	return nil, error_message(child)
end

local function wait_with_output(child)
	if not child then
		return nil
	end
	local ok, output = pcall(function()
		return child:wait_with_output()
	end)
	if ok then
		return output
	end
	return nil
end

local function safe_field(value, key)
	local ok, result = pcall(function()
		if value then
			return value[key]
		end
		return nil
	end)
	if ok then
		return result
	end
	return nil
end

local function status_success(status)
	return safe_field(status, "success") == true
end

local function output_success(output)
	return status_success(safe_field(output, "status"))
end

local function normalize_tool(tool)
	if type(tool) == "string" and tool:find("%S") then
		return { cmd = tool }
	end
	if type(tool) == "table" then
		local cmd = safe_field(tool, "cmd")
		if type(cmd) == "string" and cmd:find("%S") then
			return { cmd = cmd }
		end
	end
	return nil
end

local function trim_string(value)
	if type(value) ~= "string" then
		return nil
	end
	return string.gsub(value, "^%s*(.-)%s*$", "%1")
end

local function normalize_terminal(terminal)
	terminal = trim_string(terminal)
	if not terminal or terminal == "" then
		return nil
	end

	local lowered = string.lower(terminal)
	if lowered == "kitty" then
		return "kitty"
	end
	if lowered == "wezterm" then
		return "wezterm"
	end
	if lowered == "tmux" then
		return "tmux"
	end
	if lowered == "ghostty" then
		return "ghostty"
	end
	if lowered == "iterm" or lowered == "iterm2" or lowered == "iterm.app" then
		return "iterm"
	end
	if lowered == "rex" then
		return "rex"
	end
	return terminal
end

local function normalize_tool_name(name)
	name = trim_string(name)
	if name and name ~= "" then
		return name
	end
	return nil
end

local function tool_name_from_job(job)
	if type(job) == "string" then
		return normalize_tool_name(job)
	end
	if type(job) ~= "table" then
		return nil
	end

	local args = safe_field(job, "args")
	if type(args) == "string" then
		return normalize_tool_name(args)
	end
	if type(args) == "table" then
		return normalize_tool_name(safe_field(args, 1))
	end
	return nil
end

local function verify_kitty_socket(sock)
	local child = spawn_piped("kitty", { "@", "--to", sock, "ls" })
	local output = wait_with_output(child)
	if output_success(output) then
		return true
	end
	return false
end

local function find_kitty_socket()
	-- Try known socket paths (verified with kitty @ ls)
	for _, sock in ipairs(KITTY_SOCKET_CANDIDATES) do
		if verify_kitty_socket(sock) then
			return sock
		end
	end
	-- Try glob /tmp/kitty-* and verify each
	local child = spawn_piped("sh", { "-c", "ls /tmp/kitty-* 2>/dev/null" })
	if child then
		local output = wait_with_output(child)
		local stdout = safe_field(output, "stdout")
		if output_success(output) and type(stdout) == "string" then
			for path in string.gmatch(stdout, "[^\n]+") do
				local trimmed_path = string.gsub(path, "%s+$", "")
				if #trimmed_path > 0 then
					local sock = "unix:" .. trimmed_path
					if verify_kitty_socket(sock) then
						return sock
					end
				end
			end
		end
	end
	return nil
end

local function safe_tostring(value)
	local ok, str = pcall(function()
		return tostring(value)
	end)
	if ok and type(str) == "string" and str ~= "" then
		return str
	end
	return nil
end

local get_target_dir = ya.sync(function()
	local active = safe_field(cx, "active")
	local current = safe_field(active, "current")
	if not current then
		return nil
	end
	local cwd = safe_field(current, "cwd")
	if cwd then
		return safe_tostring(cwd)
	end
	return nil
end)

local function shell_escape(s)
	return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

local function applescript_escape(s)
	s = string.gsub(s, "\\", "\\\\")
	s = string.gsub(s, '"', '\\"')
	return '"' .. s .. '"'
end

local function wait_failed(child)
	local ok, status = pcall(function()
		return child:wait()
	end)
	return not ok or not status_success(status)
end

local function read_env(name)
	local child = spawn_piped("printenv", { name })
	if not child then
		return nil
	end
	local output = wait_with_output(child)
	local stdout = safe_field(output, "stdout")
	if output_success(output) and stdout then
		local val = trim_string(stdout)
		if val and val ~= "" then
			return val
		end
	end
	return nil
end

local function resolve_kitty_socket()
	if state.kitty_listen_on then
		return state.kitty_listen_on
	end
	if cached_kitty_listen then
		return cached_kitty_listen
	end

	cached_kitty_listen = read_env("KITTY_LISTEN_ON") or find_kitty_socket()
	return cached_kitty_listen
end

local function detect_terminal()
	if state.terminal then
		if state.terminal == "kitty" then
			cached_kitty_listen = resolve_kitty_socket()
		end
		return state.terminal
	end

	if cached_terminal then
		return cached_terminal
	end

	local tmux = read_env("TMUX")
	if tmux then
		cached_terminal = "tmux"
	else
		local term = normalize_terminal(read_env("TERM_PROGRAM"))
		if term == "kitty" then
			cached_terminal = "kitty"
			cached_kitty_listen = resolve_kitty_socket()
		elseif term == "wezterm" then
			cached_terminal = "wezterm"
		elseif term == "ghostty" then
			cached_terminal = "ghostty"
		elseif term == "iterm" then
			cached_terminal = "iterm"
		elseif term == "rex" then
			cached_terminal = "rex"
		end
	end

	-- Fallback: probe kitty socket when env detection fails
	if not cached_terminal then
		local sock = resolve_kitty_socket()
		if sock then
			-- Verify it's a live kitty by trying kitty @ ls
			local child = spawn_piped("kitty", { "@", "--to", sock, "ls" })
			if child then
				local output = wait_with_output(child)
				if output_success(output) then
					cached_terminal = "kitty"
					cached_kitty_listen = sock
				end
			end
		end
	end

	return cached_terminal
end

local function open_kitty(dir, cmd)
	local sock = resolve_kitty_socket()
	if not sock then
		return false, "kitty socket not found (add to kitty.conf: allow_remote_control yes, listen_on unix:/tmp/mykitty)"
	end

	-- Step 1: Launch a new tab with the user's default shell
	local child, err = spawn_piped("kitty", { "@", "--to", sock, "launch", "--type=tab", "--cwd", dir })
	if not child then
		return false, "Failed to spawn kitty: " .. (err or "unknown error")
	end
	local output = wait_with_output(child)
	if not output_success(output) then
		return false, "kitty launch failed on " .. sock
	end

	-- Step 2: Send the command to the newly created tab
	if not cmd then
		return true
	end

	local child2, err2 = spawn_piped("kitty", { "@", "--to", sock, "send-text", "--match", "recent:0", cmd .. "; exit\r" })
	if not child2 then
		return false, "Failed to send text: " .. (err2 or "unknown error")
	end
	if wait_failed(child2) then
		return false, "kitty send-text failed on " .. sock
	end
	return true
end

local function open_wezterm(dir, cmd)
	local args = { "cli", "spawn", "--cwd", dir }
	if cmd then
		args = { "cli", "spawn", "--cwd", dir, "--", "sh", "-c", cmd }
	end

	local child, err = spawn_piped("wezterm", args)
	if not child then
		return false, "Failed to spawn wezterm: " .. (err or "unknown error")
	end
	if wait_failed(child) then
		return false, "wezterm spawn exited unsuccessfully"
	end
	return true
end

local function open_tmux(dir, cmd)
	local args = { "new-window", "-c", dir }
	if cmd then
		args = { "new-window", "-c", dir, "sh", "-c", "sleep 0.2 && exec " .. cmd }
	end

	local child, err = spawn_piped("tmux", args)
	if not child then
		return false, "Failed to spawn tmux: " .. (err or "unknown error")
	end
	if wait_failed(child) then
		return false, "tmux new-window exited unsuccessfully"
	end
	return true
end

local function open_ghostty(dir, cmd)
	local input_line = ""
	if cmd then
		input_line = string.format(
			"\n\tset initial input of cfg to %s & \"; exit\\n\"",
			applescript_escape(cmd)
		)
	end

	local script = string.format(
		[[tell application "Ghostty"
	activate
	set cfg to new surface configuration
	set initial working directory of cfg to %s
	%s
	new tab in window 1 with configuration cfg
end tell]],
		applescript_escape(dir),
		input_line
	)
	local child, err = spawn_piped("osascript", { "-e", script })
	if not child then
		return false, "Failed to run osascript: " .. (err or "unknown error")
	end
	if wait_failed(child) then
		return false, "Ghostty AppleScript exited unsuccessfully"
	end
	return true
end

local function open_iterm(dir, cmd)
	local full_cmd = "cd " .. shell_escape(dir)
	if cmd then
		full_cmd = full_cmd .. " && " .. cmd
	end

	local script = string.format(
		[[tell application "iTerm2"
	tell current window
		create tab with default profile
		tell current session
			write text %s
		end tell
	end tell
end tell]],
		applescript_escape(full_cmd)
	)
	local child, err = spawn_piped("osascript", { "-e", script })
	if not child then
		return false, "Failed to run osascript: " .. (err or "unknown error")
	end
	if wait_failed(child) then
		return false, "iTerm2 AppleScript exited unsuccessfully"
	end
	return true
end

local function rex_executable()
	local bin_dir = read_env("REX_BIN_DIR")
	if bin_dir then
		return bin_dir .. "/rex"
	end
	return "rex"
end

local function open_rex(dir, cmd)
	local rex = rex_executable()

	-- Step 1: Open a new window (tab) with an interactive shell in the current
	-- Rex session, so the user's shell startup files set up PATH and aliases.
	local child, err = spawn_piped(rex, { "window", "new", "--cwd", dir, "--json" })
	if not child then
		return false, "Failed to spawn rex: " .. (err or "unknown error")
	end
	local output = wait_with_output(child)
	if not output_success(output) then
		return false, "rex window new exited unsuccessfully"
	end

	if not cmd then
		return true
	end

	-- Step 2: Type the command into the new window's terminal block
	local stdout = safe_field(output, "stdout")
	local block = type(stdout) == "string" and string.match(stdout, '"(block:[^"]+)"') or nil
	if not block then
		return false, "rex window new did not report a terminal block"
	end

	local child2, err2 = spawn_piped(rex, { "send", "-b", block, cmd .. "; exit\n" })
	if not child2 then
		return false, "Failed to send text: " .. (err2 or "unknown error")
	end
	if wait_failed(child2) then
		return false, "rex send exited unsuccessfully"
	end
	return true
end

local openers = {
	kitty   = open_kitty,
	wezterm = open_wezterm,
	tmux    = open_tmux,
	ghostty = open_ghostty,
	iterm   = open_iterm,
	rex     = open_rex,
}

local function notify(msg)
	pcall(function()
		ya.notify(msg)
	end)
end

function M:setup(opts)
	if type(opts) ~= "table" then
		return
	end
	local terminal = normalize_terminal(safe_field(opts, "terminal"))
	if terminal then
		state.terminal = terminal
	end
	local kitty_listen_on = trim_string(safe_field(opts, "kitty_listen_on"))
	if kitty_listen_on and kitty_listen_on ~= "" then
		state.kitty_listen_on = kitty_listen_on
		cached_kitty_listen = kitty_listen_on
	end
	local tools = safe_field(opts, "tools")
	if type(tools) == "table" then
		pcall(function()
			for name, tool in pairs(tools) do
				local tool_name = normalize_tool_name(name)
				if tool_name then
					local normalized = normalize_tool(tool)
					if normalized then
						state.tools[tool_name] = normalized
					end
				end
			end
		end)
	end
end

function M:entry(job)
	local tool_name = tool_name_from_job(job)
	local tool = nil
	if tool_name then
		tool = state.tools[tool_name]
	end
	if tool_name and not tool then
		notify({
			title = "ai-opener",
			content = "Unknown tool: " .. tool_name,
			level = "error",
			timeout = 3,
		})
		return
	end

	local dir = get_target_dir()
	if not dir then
		notify({
			title = "ai-opener",
			content = "Cannot determine directory",
			level = "error",
			timeout = 3,
		})
		return
	end

	local terminal = detect_terminal()
	if not terminal then
		notify({
			title = "ai-opener",
			content = "Cannot detect terminal. Set terminal in setup(), e.g. require('ai-opener'):setup({ terminal = 'kitty' })",
			level = "error",
			timeout = 5,
		})
		return
	end

	local opener = openers[terminal]
	if not opener then
		notify({
			title = "ai-opener",
			content = "Unsupported terminal: " .. terminal,
			level = "error",
			timeout = 5,
		})
		return
	end

	local ok, err = opener(dir, tool and tool.cmd)
	if ok then
		local content = "Terminal opened via " .. terminal
		if tool_name then
			content = tool_name .. " opened via " .. terminal
		end
		notify({
			title = "ai-opener",
			content = content,
			level = "info",
			timeout = 2,
		})
	else
		notify({
			title = "ai-opener",
			content = err or "Failed to open terminal",
			level = "error",
			timeout = 5,
		})
	end
end

return M
