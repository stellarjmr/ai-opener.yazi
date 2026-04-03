# ai-opener.yazi

Open AI coding tools (Claude, Codex, Amp, Gemini, etc.) in a new terminal tab
from Yazi, with the working directory set to the current cursor position.

## Supported Terminals

- **kitty** — via remote control (`kitty @`)
- **WezTerm** — via `wezterm cli`
- **tmux** — via `tmux new-window`
- **Ghostty** — via AppleScript (macOS, 1.3.0+ preferred)
- **iTerm2** — via AppleScript (macOS)
- **Terminal.app** — via AppleScript (macOS)
- **Generic** — runs inline in the current terminal as fallback

Terminal is auto-detected via `TMUX` and `TERM_PROGRAM` environment variables.

## Installation

```sh
ya pkg add stellarjmr/ai-opener
```

## Usage

Add keybindings to `~/.config/yazi/keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on   = "A"
run  = "plugin ai-opener --args='claude'"
desc = "Open Claude Code in new tab"

[[mgr.prepend_keymap]]
on   = ["a", "c"]
run  = "plugin ai-opener --args='claude'"
desc = "Open Claude Code in new tab"

[[mgr.prepend_keymap]]
on   = ["a", "x"]
run  = "plugin ai-opener --args='codex'"
desc = "Open Codex CLI in new tab"

[[mgr.prepend_keymap]]
on   = ["a", "a"]
run  = "plugin ai-opener --args='amp'"
desc = "Open Amp in new tab"

[[mgr.prepend_keymap]]
on   = ["a", "g"]
run  = "plugin ai-opener --args='gemini'"
desc = "Open Gemini CLI in new tab"
```

## Configuration

Optionally configure the plugin in `~/.config/yazi/init.lua`:

```lua
require("ai-opener"):setup({
    -- Default tool when no argument is provided
    default_tool = "claude",

    -- Override auto-detected terminal
    -- terminal = "kitty",

    -- Add custom tools or override built-in ones
    -- tools = {
    --     mycli = { cmd = "my-custom-ai --flag" },
    -- },
})
```

### Built-in Tools

| Name     | Command  |
|----------|----------|
| `claude` | `claude` |
| `codex`  | `codex`  |
| `amp`    | `amp`    |
| `gemini` | `gemini` |
| `aider`  | `aider`  |

## How It Works

1. Resolves the working directory from the hovered item (directory → use it;
   file → use its parent directory)
2. Detects the terminal emulator via environment variables
3. Opens a new tab in that terminal with the AI tool running in the resolved
   directory

## Notes

- **kitty** requires `allow_remote_control yes` in `kitty.conf`.
- **Ghostty** uses the 1.3.0+ AppleScript API (`new tab with configuration`),
  with a keystroke-based fallback for older versions.
- The **generic** fallback hides yazi and runs the tool inline — yazi resumes
  when the tool exits.
