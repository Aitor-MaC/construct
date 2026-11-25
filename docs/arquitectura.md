# Arquitectura de Construct

Terminal de macOS con lluvia estilo Matrix, bloques de comando, historial e IA local. Este documento describe el código construido (SwiftTerm `main@1488fac9`).

## Índice
1. [Módulos](#1-módulos)
2. [Flujo de bytes: PTY a overlays](#2-flujo-de-bytes-pty-a-overlays)
3. [Secuencia de `# pregunta`](#3-secuencia-de--pregunta)
4. [Orden de capas de la vista](#4-orden-de-capas-de-la-vista)
5. [Modelo de amenazas resumido](#5-modelo-de-amenazas-resumido)
6. [Diferencias con el plan](#diferencias-con-el-plan)

## 1. Módulos

```mermaid
flowchart LR
  subgraph App["Construct.app (AppKit + SwiftUI, MainActor)"]
    APP["App: MyApp, AppDelegate, ActionRegistry, AppCommands"]
    WIN["Windows: ventanas, pestañas, splits, Quake, atajo global"]
    PANE["Pane: Workspace, PaneLayers, RainSignals, WindowToastLayer"]
    TERM["Terminal: TerminalPaneController, MatrixTerminalView"]
    RAIN["Rain: RainCanvasView, CRTOverlayView, WakeUpGreetingView"]
    BLK["Blocks: overlay, chips, navegación"]
    PAL["Palette: PaletteController, PaletteView"]
    SET["Settings: escena Settings"]
    OVL["Overlays: MatrixFindBar, SuggestionCardView, ToastView"]
  end
  subgraph Pkg["Packages/MacterminalCore"]
    TP["MacterminalTerminal: OSCBridge, SuggestionFlow, LinkPolicy, PasteSanitizer, TitleSanitizer"]
    CORE["MacterminalCore: Shell, Config, Rain, Assist, Layout, Palette, Overlays"]
  end
  ST["SwiftTerm (dependencia externa)"]
  APP --> WIN --> PANE
  PANE --> TERM & RAIN & BLK & OVL
  APP --> PAL & SET
  TERM --> TP --> ST
  TP --> CORE
  PANE --> CORE
  BLK --> CORE
  PAL --> CORE
  SET --> CORE
```

`MacterminalCore` es lógica pura sin AppKit y se prueba con `swift test`. `MacterminalTerminal` es el único producto que depende de SwiftTerm, de modo que el puente OSC también se prueba sin la app. `Pane` es el montaje: cablea los módulos y es dueño de `Workspace` (un único `ConfigStore`, `HistoryStore` y `CommandSuggester`).

## 2. Flujo de bytes: PTY a overlays

```mermaid
flowchart LR
  PTY[("zsh en PTY (LocalProcess)")]
  MTV["MatrixTerminalView.feed"]
  SW["SwiftTerm Terminal: parser, buffer, OSC 133 y 7"]
  H["registerOscHandler 7777 / 0 / 1 / 2"]
  Q["OSCBridge: cola ordenada, nonce, ancla de fila"]
  OP["OSCParser.parse(payload, nonce)"]
  BT["BlockTracker (MainActor)"]
  HI["HistoryStore (actor, history.json 0600)"]
  AI["SuggestionFlow + CommandSuggester"]
  OV["Overlays: bloques, chips, tarjeta IA, barra de busqueda"]
  RN["Rain: ViewportSnapshot"]
  PTY -->|bytes| MTV --> SW
  SW -->|"OSC 7777"| H --> Q
  Q -->|"sin nonce valido"| X(["descartado"])
  Q --> OP -->|ShellEvent| BT
  BT -->|"comando terminado"| HI
  BT -->|aiRequest| AI
  BT --> OV
  AI --> OV
  SW -->|"buffer visible"| RN
```

El estado de la app sale solo de OSC 7777 con nonce de 32 hex por proceso. El handler es síncrono y encola; tras cada `feed` se drena en tramos de 256 hacia `BlockTracker`. Si la cola pasa de 4096 se llama a `desynchronize()` y se rearma con el siguiente `A` autenticado. OSC 133/7 los gestiona SwiftTerm, nunca la app. Las filas son absolutas del buffer; la lluvia recibe filas de la vista mediante `ViewportSnapshot`.

## 3. Secuencia de `# pregunta`

```mermaid
sequenceDiagram
  actor U as Usuario
  participant Z as zsh (widget accept-line)
  participant B as OSCBridge
  participant P as TerminalPaneController
  participant F as SuggestionFlow
  participant M as Foundation Models (on-device)
  participant C as SuggestionCardView
  U->>Z: escribe almohadilla, espacio y la pregunta, y pulsa Enter
  Z->>B: OSC 7777 con nonce, verbo ai y base64 (la linea se vacia, no se ejecuta)
  B->>B: valida nonce, decodifica, toma insertionToken()
  B->>P: onAIRequest(texto, token)
  P->>F: request(texto, token, cwd)
  F->>M: suggest(for, cwd) con sesion nueva
  alt responde antes de 20 s
    M-->>F: CommandSuggestion
    F-->>C: tarjeta con el comando
    U->>C: Insertar
    C->>P: insertIntoPrompt(texto, token)
    P->>B: comprueba token vigente, cola vacia, PromptInsertion.validate
    B-->>P: inserted (sin retorno de carro)
  else timeout, error o no disponible
    F-->>C: mensaje de error en la tarjeta
  end
  Note over U,Z: el usuario revisa la linea y ejecuta con Enter
```

La IA recibe solo la petición y el cwd, nunca la salida del terminal. `insertIntoPrompt` devuelve `inserted`, `notAtPrompt`, `stale` o `unsafe`. Con `stale` (otro prompt desde la petición) o con eventos pendientes en la cola (A11) no se escribe nada. Nunca se envía `\r`: ejecutar siempre lo decide el usuario.

## 4. Orden de capas de la vista

```mermaid
flowchart BT
  L1["Capa 1: RainCanvasView + cursor fosforo (contenedor, debajo)"]
  L2["Capa 2: Fondos de bloque (BlocksBackdropView)"]
  L3["Capa 3: MatrixTerminalView (texto, transparente)"]
  L4["Capa 4: Controles de bloque (BlocksOverlayHostingView)"]
  L5["Capa 5: CRTOverlayView"]
  L6["Capa 6: WakeUpGreetingView"]
  L7["Capa 7: MatrixFindBar (Cmd+F)"]
  L8["Capa 8: Tarjeta de la IA (SuggestionCardLayer)"]
  L9["Ventana: WindowToastLayer y paleta (PaletteController.show over)"]
  L1 --> L2 --> L3 --> L4 --> L5 --> L6 --> L7 --> L8 --> L9
```

De abajo arriba. Las capas 1 y 2 son hermanas de la terminal, bajo ella; de la 4 a la 8 son subvistas de la terminal, para que la barra Cmd+F quede sobre controles y CRT. El fondo y su opacidad son del contenedor de la ventana: las capas del panel son transparentes. La tarjeta recibe el foco al aparecer y lo devuelve a la terminal al cerrarse.

## 5. Modelo de amenazas resumido

```mermaid
flowchart LR
  subgraph NC["No confiable"]
    OUT["Salida del PTY: cualquier programa, cat de archivos, red"]
    MOD["Texto generado por el modelo"]
    CFG["Archivos de config e historial en disco"]
  end
  subgraph CTL["Controles"]
    N["Nonce por proceso + OSCParser: limites, base64, UTF-8, sin bidi"]
    QU["Cola acotada 4096, tramos de 256, desincronizacion"]
    INS["insertIntoPrompt: token + PromptInsertion.validate, sin retorno de carro"]
    SAN["OSC 52 ignorado, LinkPolicy, TitleSanitizer, PasteSanitizer"]
    DEC["DECRQCRA desactivado: enableRectangularAreaChecksum = false"]
    FS["ZDOTDIR 0700 con O_NOFOLLOW, history 0600, config limitada a 64 KB"]
  end
  OUT --> N & QU & SAN & DEC
  MOD --> INS
  CFG --> FS
```

Tabla resumida de amenazas y mitigaciones.

| Amenaza | Mitigación |
|---|---|
| La salida de un programa falsifica bloques, cwd, historial o IA | Nonce por proceso entregado en `MACTERMINAL_NONCE`; el `.zshenv` lo guarda sin exportar y hace `unset`; sin nonce válido se descarta |
| Flood de secuencias | Descarte previo a encolar, cola de 4096, tramos de 256, `desynchronize()` |
| Escritura no deseada en el PTY por IA, historial o paleta | Único punto `insertIntoPrompt(_:token:)`, prompt vigente, validación, sin `\r` |
| Portapapeles, enlaces y títulos | OSC 52 de escritura ignorado y lectura sin respuesta; solo `http`, `https` y `mailto` con Cmd+clic; títulos saneados |
| Desbordamiento en `reflowNarrower` de SwiftTerm (CWE-787) | Pin a `1488fac9`, que incluye la corrección 12de9933; volver a un pin por versión al publicarse la siguiente release |
| Datos personales | Historial 0600, sin comandos con espacio inicial ni `# …`; logs sin texto de comandos, salida ni rutas |
| Scripts temporales manipulados | Directorio 0700 con `O_NOFOLLOW`, archivos con `O_EXCL` y `rename`; el `~/.zshrc` real no se toca |

Sin red ni autenticación propias: la IA corre en el dispositivo. Entitlement único `automation.apple-events`, con Hardened Runtime.

## Diferencias con el plan

- Búsqueda: el plan preveía `TerminalFindBar` de SwiftTerm; se usa `MatrixFindBar` propia, sin resaltado de todas las coincidencias (decisiones.md, R14).
- DECRQCRA: `ScreenChecksumFilter` propio sustituido por `enableRectangularAreaChecksum = false` (F5 I1).
- SwiftTerm: el plan fijaba 1.99.3; el código usa `main@1488fac9`.
- Capas: el plan solo citaba "Pane: montaje"; el orden real de capas está en `PaneLayers.swift` y se dibuja aquí. Los toasts son de la ventana, no del panel.
- Paleta: se presenta sobre la ventana (`PaletteController.show(over:)`), no como capa del panel.
