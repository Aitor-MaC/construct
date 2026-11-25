# Configuration

**English** · [Español](configuracion.md)

File: `~/.config/macterminal/config`. If it doesn’t exist, the default values are used. You can also open it from Settings, Advanced tab.

## Format

- One assignment per line: `key = value`. Values can be wrapped in single or double quotes.
- Empty lines and lines that start with `#` are ignored.
- It reloads when you save the file (or with the “Reload Configuration” action in the palette).
- Maximum size 64 KB; above that, the default values are used.
- An error doesn’t break the app: the affected line goes back to its default value and a notice is shown. A repeated key shows a warning and the last one wins.
- When a key is in the file, it takes precedence over the Settings window, and Settings writes to the same file.

## Keys

| Key | Values | Default | Applies |
|---|---|---|---|
| `font-family` | Name of an installed font; can’t be empty | `Monaspace Krypton NF` | On reload, to open panes |
| `font-size` | Number from 10 to 24 (a decimal comma is accepted) | `13` | On reload |
| `intensity` | `subtle`, `balanced`, `immersive`, or the original `sutil`, `equilibrado`, `inmersivo`. Settings always writes the Spanish value so existing files keep working | `equilibrado` (Balanced) | On reload |
| `prompt` | `true` or `false`: Construct prompt | `true` | New sessions only |
| `autosuggest` | `true` or `false`: gray suggestion from the history | `true` | New sessions only |
| `prompt-user-host` | `always`, `ssh` (only in an SSH session or as root; since this is the prompt of Construct’s local zsh, in practice it means “only as root”) or `never`: `user@computer` segment at the start of the prompt. As root it turns red; over SSH it’s marked with `⇄` | `always` | New sessions only |
| `prompt-path` | `full` (`~/Projects/Construct`, cut on the left with `…/` so at least 30 columns stay free) or `short` (`~/P/Construct`) | `full` | New sessions only |
| `background-opacity` | Number from 0.5 to 1; out-of-range values are clamped | `1` | On reload |
| `quake-hotkey` | Global shortcut, see below | `ctrl+grave` | On reload |
| `shell` | Absolute path to an existing executable | the system `$SHELL`, or `/bin/zsh` | New sessions only |
| `greeting-name` | Name in the “Wake up, …” greeting. Control, bidi and invisible characters and line breaks are removed, and it’s cut to 32 characters; empty is the same as not setting it | the first name of your macOS account | On the next greeting |

## Shortcut format

Modifiers separated by `+` with the key at the end: `cmd`, `ctrl`, `alt`, `shift`. The key is a character or one of `grave`, `left`, `right`, `up`, `down`, `return`, `escape`, `tab`, `space`, `plus` (`+` is written `plus`). Examples: `ctrl+grave`, `cmd+alt+space`.

A global shortcut without `cmd`, `ctrl` or `alt` is rejected in Settings (it would fire while you type), and it can’t match a menu shortcut either.

## Example

```
# Appearance
font-family = Monaspace Krypton NF
font-size = 14
intensity = immersive
background-opacity = 0.9
greeting-name = Neo

# Shell
prompt = true
prompt-user-host = always
prompt-path = full
autosuggest = true
shell = /bin/zsh

# Quake window
quake-hotkey = ctrl+grave
```

## Other files

- Own history for autosuggestions and the palette: `~/Library/Application Support/Macterminal/history.json` (permissions 0600, up to 2000 entries, never sent anywhere). If it gets corrupted, it’s set aside as `history.json.corrupt` and a new, empty one is started.
- The prompt is injected with a temporary `ZDOTDIR` that loads your real `~/.zshrc` without modifying it.
