# ai-opener.yazi

Open AI coding tools (Claude, Codex, Amp, Gemini, and Aider) in a new terminal tab
from Yazi, with the working directory set to the current Yazi directory.

## Supported Terminals

- **kitty** — via remote control socket (`kitty @`, requires `listen_on`)
- **WezTerm** — via `wezterm cli` (untested)
- **tmux** — via `tmux new-window`
- **Ghostty** — via AppleScript (macOS, 1.3.0+)
- **iTerm2** — via AppleScript (macOS, untested)
- **Rex** — via `rex window new` and `rex send` in the current Rex session

Terminal is auto-detected from Yazi's environment and lightweight terminal
probes. The `TMUX` environment variable takes precedence over `TERM_PROGRAM`.
Inside Rex, `REX_SESSION` also takes precedence over `TERM_PROGRAM`, so Rex is
still detected when `TERM_PROGRAM` is overridden (for example to `ghostty` for
Yazi image previews).
`TERM_PROGRAM` values are normalized with the same product-name aliases as the
configured `terminal` option.
For kitty, the plugin uses a configured `kitty_listen_on`, `KITTY_LISTEN_ON`, or
a live kitty socket it can verify. Leading and trailing whitespace around
`KITTY_LISTEN_ON` is ignored.

## Compatibility

Maintained against Yazi/Ya `26.8.15`.

## Installation

```sh
ya pkg add stellarjmr/ai-opener
```

## Usage

Add keybindings to `~/.config/yazi/keymap.toml`:

Use `plugin ai-opener` without an argument to open a plain terminal in the
current directory. Pass a tool name, such as `codex`, only when you want to run
that AI CLI in the new tab.

```toml
[[mgr.prepend_keymap]]
on   = "A"
run  = "plugin ai-opener"
desc = "Open terminal in new tab"

[[mgr.prepend_keymap]]
on   = ["a", "o"]
run  = "plugin ai-opener"
desc = "Open terminal only in new tab"

[[mgr.prepend_keymap]]
on   = ["a", "c"]
run  = "plugin ai-opener claude"
desc = "Open Claude Code in new tab"

[[mgr.prepend_keymap]]
on   = ["a", "x"]
run  = "plugin ai-opener codex"
desc = "Open Codex CLI in new tab"

[[mgr.prepend_keymap]]
on   = ["a", "a"]
run  = "plugin ai-opener amp"
desc = "Open Amp in new tab"

[[mgr.prepend_keymap]]
on   = ["a", "g"]
run  = "plugin ai-opener gemini"
desc = "Open Gemini CLI in new tab"

[[mgr.prepend_keymap]]
on   = ["a", "i"]
run  = "plugin ai-opener aider"
desc = "Open Aider in new tab"
```

## Configuration

Optionally configure the plugin in `~/.config/yazi/init.lua`:

```lua
require("ai-opener"):setup({
    -- Override auto-detected terminal:
    -- "kitty", "wezterm", "tmux", "ghostty", "iterm", or "rex".
    -- Product-name aliases such as "WezTerm" and "iTerm2" are accepted.
    -- Leading and trailing whitespace around terminal and kitty socket settings
    -- is ignored.
    -- terminal = "kitty",

    -- Custom kitty socket path (default: unix:/tmp/mykitty)
    -- kitty_listen_on = "unix:/tmp/mykitty",

    -- Add custom tools or override built-in ones.
    -- Tool names are trimmed before registration.
    -- Empty or all-whitespace names or commands are ignored.
    -- tools = {
    --     mycli = { cmd = "my-custom-ai --flag" },
    --     quick = "quick-ai --flag",
    -- },
})
```

Malformed or temporarily inaccessible setup metadata is ignored, so a bad
custom tool entry does not prevent other valid tools from registering.

### Built-in Tools

Tool arguments are optional. No argument opens a terminal only; a known tool
argument runs that command in the new tab/window. Leading and trailing
whitespace around tool arguments is ignored. If Yazi tool argument metadata is
temporarily unavailable or malformed, the plugin treats it as no tool argument.

| Name     | Command  |
|----------|----------|
| `claude` | `claude` |
| `codex`  | `codex`  |
| `amp`    | `amp`    |
| `gemini` | `gemini` |
| `aider`  | `aider`  |

## How It Works

1. Uses Yazi's current directory as the working directory, regardless of the
   hovered item
2. Detects the terminal emulator automatically
3. Opens a new tab in that terminal in the current directory
4. When a tool argument is provided, runs that AI tool and closes the tab when
   the tool exits; without an argument, leaves the shell open without running an
   AI CLI

If Yazi current-directory metadata is temporarily unavailable, malformed, or
cannot be converted to a path, the plugin reports a
directory-resolution error instead of opening a terminal without a usable
directory.

## Terminal-Specific Notes

- **kitty** requires `allow_remote_control yes` and `listen_on` in `kitty.conf`:
  ```
  allow_remote_control yes
  listen_on unix:/tmp/mykitty
  ```
- **Ghostty** requires version 1.3.0+ for AppleScript tab creation support.
- **tmux** works inside any terminal emulator.
- **Rex** opens a new window (tab) in the session Yazi is running in, using the
  `rex` CLI from `REX_BIN_DIR` when set. Tool commands are typed into the new
  interactive shell, so your shell startup files still set up `PATH`.

## License

MIT License - see [LICENSE](LICENSE) file for details.
