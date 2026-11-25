# Configuración

[English](configuration.md) · **Español**

Archivo: `~/.config/macterminal/config`. Si no existe, se usan los valores por defecto. También se puede abrir desde Ajustes, pestaña Avanzado.

## Formato

- Una asignación por línea: `clave = valor`. Los valores pueden ir entre comillas simples o dobles.
- Las líneas vacías y las que empiezan por `#` se ignoran.
- Se recarga al guardar el archivo (o con la acción «Recargar configuración» de la paleta).
- Tamaño máximo 64 KB; si lo supera, se usan los valores por defecto.
- Un error no rompe la app: la línea afectada vuelve a su valor por defecto y se muestra un aviso. Una clave repetida se avisa y gana la última.
- Si una clave está en el archivo, manda sobre la ventana de Ajustes, y Ajustes escribe en el mismo archivo.

## Claves

| Clave | Valores | Por defecto | Se aplica |
|---|---|---|---|
| `font-family` | Nombre de fuente instalada; no puede estar vacío | `Monaspace Krypton NF` | Al recargar, a los paneles abiertos |
| `font-size` | Número de 10 a 24 (admite coma decimal) | `13` | Al recargar |
| `intensity` | `sutil`, `equilibrado`, `inmersivo` (también `subtle`, `balanced`, `immersive`; Ajustes escribe siempre el valor en español para no romper configs existentes) | `equilibrado` | Al recargar |
| `prompt` | `true` o `false`: prompt de Construct | `true` | Solo en sesiones nuevas |
| `autosuggest` | `true` o `false`: sugerencia en gris desde el historial | `true` | Solo en sesiones nuevas |
| `prompt-user-host` | `always`, `ssh` (solo en una sesión SSH o como root; como el prompt es el del zsh local de Construct, en la práctica equivale a «solo como root») o `never`: segmento `usuario@equipo` al principio del prompt. Como root sale en rojo; por SSH se marca con `⇄` | `always` | Solo en sesiones nuevas |
| `prompt-path` | `full` (`~/Proyectos Apps/Construct`, recortada por la izquierda con `…/` para dejar al menos 30 columnas libres) o `short` (`~/P/Construct`) | `full` | Solo en sesiones nuevas |
| `background-opacity` | Número de 0,5 a 1; fuera de rango se ajusta | `1` | Al recargar |
| `quake-hotkey` | Atajo global, ver abajo | `ctrl+grave` | Al recargar |
| `shell` | Ruta absoluta de un ejecutable existente | el `$SHELL` del sistema, o `/bin/zsh` | Solo en sesiones nuevas |
| `greeting-name` | Nombre del saludo «Wake up, …». Se quitan controles, caracteres bidi e invisibles y saltos de línea, y se corta a 32 caracteres; vacío equivale a no ponerlo | el nombre de pila de tu cuenta de macOS | En el siguiente saludo |

## Formato de atajos

Modificadores separados por `+` y la tecla al final: `cmd`, `ctrl`, `alt`, `shift`. La tecla es un carácter o uno de `grave`, `left`, `right`, `up`, `down`, `return`, `escape`, `tab`, `space`, `plus` (el `+` se escribe `plus`). Ejemplos: `ctrl+grave`, `cmd+alt+space`.

Un atajo global sin `cmd`, `ctrl` ni `alt` se rechaza en Ajustes (se dispararía al escribir), y tampoco puede coincidir con un atajo del menú.

## Ejemplo

```
# Apariencia
font-family = Monaspace Krypton NF
font-size = 14
intensity = inmersivo
background-opacity = 0.9
greeting-name = Neo

# Shell
prompt = true
prompt-user-host = always
prompt-path = full
autosuggest = true
shell = /bin/zsh

# Ventana Quake
quake-hotkey = ctrl+grave
```

## Otros archivos

- Historial propio para autocompletado y paleta: `~/Library/Application Support/Macterminal/history.json` (permisos 0600, hasta 2000 entradas, nunca se envía). Si se corrompe, se aparta como `history.json.corrupt` y se empieza vacío.
- El prompt se inyecta con un `ZDOTDIR` temporal que carga tu `~/.zshrc` real sin modificarlo.
