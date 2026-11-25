/// Lo que hace una fila al elegirla: lanzar una acción o escribir texto en el prompt sin ⏎.
public enum PaletteResult: Sendable, Hashable {
  case action(TerminalAction)
  case insert(String)
}
