# Cambios

## 1.0.4 — 2026-11-25

- AI requests can be written between quotes, closed or not: `"#help me upgrade powershell"` or `'?? list big files'` no longer fail with "command not found". If the quote closes before the end of the line (`"#" || true`), the line runs as a normal command.

## 1.0.3 — 2026-11-24

- Ask Apple Intelligence from the prompt with `#text`, `# text` or `?? text` (it used to require exactly `# ` with a space). The request is never run and never enters your zsh history.
- A grey hint, "⏎ ask Apple Intelligence", appears as soon as you type `#` or `??`, so you know Enter goes to the AI.
- Lines starting with `#` inside a heredoc or an unclosed quote are kept as typed.

## 1.0.2 — 2026-11-23

- The "Wake up, {name}…" greeting now plays every time the app opens and on every new window or tab, in all three intensities (it used to be Immersive only, once a day). Splits and the Quake window don't show it.
- Any key skips the greeting and goes straight to the shell.

## 1.0.1 — 2026-11-23

- Settings › AI refreshes the Apple Intelligence status on its own every few seconds while the model is downloading or Apple Intelligence is turned off, and switches to "Available" as soon as it's ready.
- New "Open Apple Intelligence Settings…" button that jumps to the Apple Intelligence & Siri pane of System Settings.
- Custom Matrix-style DMG (background, icon layout and volume icon).

## 1.0.0 — 2026-11-23

First public release of Construct, signed with Developer ID and notarized by Apple (`scripts/notarize.sh`). Includes everything below.

- Distributed as `Construct-1.0.dmg`.
- First-run name prompt and personalised "Wake up" greeting, English base language with Spanish translation, empty state shown only until the first command, and a richer prompt (`user@host`, full path).

## 0.3.0

Renamed to Construct.

- The app is now called Construct (`Construct.app`): window title, menus, permission prompts, Settings, onboarding and `TERM_PROGRAM=Construct`.
- The bundle identifier, `~/.config/macterminal/config` and the history path are unchanged, so preferences, permissions and your configuration carry over.

## 0.2.0

English as base language, Spanish translation.

- The interface is written in English and translated into Spanish with String Catalogs (app, `MacterminalCore` and `MacterminalTerminal`). macOS picks the language: Spanish on a Spanish system, English otherwise.
- Permission prompts (Apple Events, Documents, Desktop, Downloads, removable and network volumes) are localized through `InfoPlist.xcstrings`.
- `intensity` also accepts `subtle`, `balanced` and `immersive`; the Spanish values keep working and are still the ones written to the file.
- Durations in the block chip use the decimal separator of the region; relative dates in the palette follow the current locale.
- The AI explains its suggestion in the language of the request.
- “Wake up, Neo…” stays in English in every language.
- README and configuration guide in English, with the Spanish versions in `README.es.md` and `docs/configuracion.md`.

## 0.1.0

Primera versión.

### Terminal
- Shell de login en PTY con SwiftTerm; copiar, pegar y selección con ratón.
- Pestañas nativas, splits verticales y horizontales con navegación por teclado; lo nuevo hereda el directorio.
- Ventana Quake con atajo global configurable.
- Búsqueda en el scrollback con contador.

### Tema Matrix
- Paleta ANSI, fuente Monaspace Krypton NF y ventana siempre oscura.
- Lluvia digital con tres intensidades (Sutil, Equilibrado, Inmersivo), pausa con ventana inactiva, Modo Bajo Consumo y Reducir movimiento.

### Shell
- Prompt propio para zsh con ruta, rama git, código de salida, duración y hora, sin tocar `~/.zshrc`.
- Integración OSC 133/7 y bloques de comandos con chips de salida, navegación y copia.
- Autocompletado desde el historial propio.

### Productividad
- Paleta de comandos (`⇧⌘P`) con acciones, historial y carpetas recientes.
- IA local con `# …` y Apple Foundation Models: propone, y solo inserta tras confirmar.
- Configuración por archivo con recarga en caliente y ventana de Ajustes.

### Seguridad
- SwiftTerm fijado a una revisión de `main` que corrige un desbordamiento de memoria (CWE-787).
- OSC propios con nonce de sesión, sin ejecución automática de comandos.

### Límites conocidos
- La búsqueda resalta solo la coincidencia actual.
- La verificación manual de la interfaz quedó pendiente de revisión por el usuario.
