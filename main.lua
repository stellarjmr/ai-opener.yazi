--- @since 26.04.03
-- Open AI coding tools in a new terminal tab from yazi.

local M = {}

local state = {
	default_tool = "claude",
	tools = {
		claude = { cmd = "claude" },
		codex  = { cmd = "codex" },
		amp    = { cmd = "amp" },
		gemini = { cmd = "gemini" },
		aider  = { cmd = "aider" },
	},
	terminal = nil, -- nil = auto-detect
}

local function shell_escape(s)
	return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

local function get_target_dir()
	local h = cx.active.current.hovered
	if h then
		if h.cha.is_dir then
			return tostring(h.url)
		else
			return tostring(h.url:parent())
		end
	end
	return tostring(cx.active.current.cwd)
end

local function detect_terminal()
	if state.terminal then
		return state.terminal
	end

	if os.getenv("TMUX") then
		return "tmux"
	end

	local term = os.getenv("TERM_PROGRAM")
	if term == "kitty" then
		return "kitty"
	elseif term == "WezTerm" then
		return "wezterm"
	elseif term == "ghostty" then
		return "ghostty"
	elseif term == "iTerm.app" then
		return "iterm"
	elseif term == "Apple_Terminal" then
		return "apple_terminal"
	end

	return "generic"
end

local function open_kitty(dir, cmd)
	local child, err = Command("kitty")
		:arg({ "@", "launch", "--type=tab", "--cwd=" .. dir, "--", "sh", "-c", cmd })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()
	if not child then
		return false, "Failed to spawn kitty: " .. (err or "unknown error")
	end
	child:wait()
	return true
end

local function open_wezterm(dir, cmd)
	local child, err = Command("wezterm")
		:arg({ "cli", "spawn", "--cwd", dir, "--", "sh", "-c", cmd })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()
	if not child then
		return false, "Failed to spawn wezterm: " .. (err or "unknown error")
	end
	child:wait()
	return true
end

local function open_tmux(dir, cmd)
	local child, err = Command("tmux")
		:arg({ "new-window", "-c", dir, cmd })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()
	if not child then
		return false, "Failed to spawn tmux: " .. (err or "unknown error")
	end
	child:wait()
	return true
end

local function open_ghostty(dir, cmd)
	local script = string.format(
		[[
tell application "Ghostty"
	activate
	set cfg to new surface configuration
	set initial working directory of cfg to %s
	set initial input of cfg to %s & "; exit\n"
	new tab with configuration cfg
end tell
]],
		shell_escape(dir),
		shell_escape(cmd)
	)
	local child, err = Command("osascript")
		:arg({ "-e", script })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()
	if not child then
		return false, "Failed to run osascript: " .. (err or "unknown error")
	end
	local output = child:wait_with_output()
	if not output or not output.status.success then
		-- Fallback: use keystroke-based approach for older ghostty
		local fallback_script = string.format(
			[[
tell application "Ghostty"
	activate
end tell
tell application "System Events"
	keystroke "t" using command down
	delay 0.3
	keystroke "cd %s && %s" & return
end tell
]],
			dir,
			cmd
		)
		local child2, err2 = Command("osascript")
			:arg({ "-e", fallback_script })
			:stdout(Command.PIPED)
			:stderr(Command.PIPED)
			:spawn()
		if not child2 then
			return false, "Failed to run osascript fallback: " .. (err2 or "unknown error")
		end
		child2:wait()
	end
	return true
end

local function open_iterm(dir, cmd)
	local script = string.format(
		[[
tell application "iTerm2"
	tell current window
		create tab with default profile
		tell current session
			write text "cd %s && %s"
		end tell
	end tell
end tell
]],
		shell_escape(dir),
		cmd
	)
	local child, err = Command("osascript")
		:arg({ "-e", script })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()
	if not child then
		return false, "Failed to run osascript: " .. (err or "unknown error")
	end
	child:wait()
	return true
end

local function open_apple_terminal(dir, cmd)
	local script = string.format(
		[[
tell application "Terminal"
	activate
	do script "cd %s && %s"
end tell
]],
		shell_escape(dir),
		cmd
	)
	local child, err = Command("osascript")
		:arg({ "-e", script })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()
	if not child then
		return false, "Failed to run osascript: " .. (err or "unknown error")
	end
	child:wait()
	return true
end

local function open_generic(dir, cmd)
	local permit = ya.hide()
	local child, err = Command("sh")
		:arg({ "-c", "cd " .. shell_escape(dir) .. " && " .. cmd })
		:stdin(Command.INHERIT)
		:stdout(Command.INHERIT)
		:stderr(Command.INHERIT)
		:status()
	if not child then
		return false, "Failed to run command: " .. (err or "unknown error")
	end
	return true
end

local openers = {
	kitty          = open_kitty,
	wezterm        = open_wezterm,
	tmux           = open_tmux,
	ghostty        = open_ghostty,
	iterm          = open_iterm,
	apple_terminal = open_apple_terminal,
	generic        = open_generic,
}

local function open_in_tab(terminal, dir, cmd)
	local opener = openers[terminal]
	if not opener then
		return open_generic(dir, cmd)
	end
	return opener(dir, cmd)
end

function M:setup(opts)
	if not opts then
		return
	end
	if opts.default_tool then
		state.default_tool = opts.default_tool
	end
	if opts.terminal then
		state.terminal = opts.terminal
	end
	if opts.tools then
		for name, tool in pairs(opts.tools) do
			state.tools[name] = tool
		end
	end
end

function M:entry(job)
	local tool_name = job.args[1] or state.default_tool
	local tool = state.tools[tool_name]
	if not tool then
		ya.notify({
			title = "ai-opener",
			content = "Unknown tool: " .. tool_name,
			level = "error",
			timeout = 3,
		})
		return
	end

	local dir = get_target_dir()
	if not dir then
		ya.notify({
			title = "ai-opener",
			content = "Cannot determine directory",
			level = "error",
			timeout = 3,
		})
		return
	end

	local terminal = detect_terminal()
	local ok, err = open_in_tab(terminal, dir, tool.cmd)

	if ok then
		ya.notify({
			title = "ai-opener",
			content = tool_name .. " opened via " .. terminal,
			level = "info",
			timeout = 2,
		})
	else
		ya.notify({
			title = "ai-opener",
			content = err or "Failed to open " .. tool_name,
			level = "error",
			timeout = 5,
		})
	end
end

return M
