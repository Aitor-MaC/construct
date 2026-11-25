import MacterminalCore
import SwiftUI

/// Chip de salida de la cabecera: `✓` / `✗ código` / `—` y la duración. Si este chip vio el
/// comando en marcha y duró ≥ 2 s, al terminar se decodifica en 240 ms (momento firma 1);
/// con Reduce Motion aparece el texto final.
struct BlockChipView: View {
  let block: CommandBlock

  var body: some View {
    if block.state == .finished {
      FinishedChip(block: block)
    } else {
      TimelineView(.periodic(from: .now, by: 0.1)) { _ in
        Text(BlockChip(block: block, now: .now).duration)
          .foregroundStyle(BlockTokens.muted)
      }
    }
  }
}

private struct FinishedChip: View {
  static let decodeDuration: Duration = .milliseconds(240)
  static let frameInterval: Duration = .milliseconds(16)
  /// Margen para el retraso entre la marca D y el primer dibujo del chip terminado.
  static let justFinishedWindow: Duration = .seconds(1)

  let block: CommandBlock
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var decoding: (status: String, duration: String)?

  var body: some View {
    let chip = BlockChip(block: block, now: .now)
    HStack(spacing: 8) {
      Text(decoding?.status ?? chip.status)
        .foregroundStyle(statusColor(chip.tone))
        .padding(.horizontal, chip.tone == .failure ? 8 : 2)
        .frame(height: 18)
        .background(chip.tone == .failure ? BlockTokens.failureFill : .clear, in: .rect(cornerRadius: 4))
      Text(decoding?.duration ?? chip.duration)
        .foregroundStyle(BlockTokens.muted)
    }
    .task(id: block.id) { await decodeIfJustFinished(chip) }
  }

  private func statusColor(_ tone: BlockChip.Tone) -> Color {
    switch tone {
    case .success: BlockTokens.success
    case .failure: BlockTokens.failureText
    case .unknown, .running: BlockTokens.muted
    }
  }

  /// Solo decodifica si el bloque acaba de terminar: un bloque antiguo que vuelve a la vista al
  /// desplazarse no repite la animación. El fin se calcula con el inicio y la duración del bloque,
  /// medidos con el mismo `ContinuousClock` del tracker.
  private func decodeIfJustFinished(_ chip: BlockChip) async {
    guard chip.decodes, !reduceMotion, let started = block.startedInstant,
      let duration = block.duration,
      ContinuousClock.now - (started + duration) < Self.justFinishedWindow
    else { return }
    var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: block.id.hashValue))
    let start = ContinuousClock.now
    while true {
      let progress = (ContinuousClock.now - start) / Self.decodeDuration
      guard progress < 1 else { break }
      decoding = (
        DecodeText.frame(final: chip.status, progress: progress, using: &rng),
        DecodeText.frame(final: chip.duration, progress: progress, using: &rng)
      )
      do { try await Task.sleep(for: Self.frameInterval) } catch { break }
    }
    decoding = nil
  }
}
