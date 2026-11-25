import MacterminalCore
import SwiftUI

/// Lo que se dibuja de un bloque por encima del texto: separador, contorno de selección, anillo
/// de foco, chip de salida, acciones y barra de progreso. Los rellenos van en
/// `BlocksBackdropView`, por debajo del texto, para no apagarlo.
struct BlockChromeView: View {
  let block: CommandBlock
  let frame: BlockFrame
  let geometry: BlockGeometry
  let state: BlockOverlayState
  let actions: BlockActions
  let accessibilityLabel: String
  @State private var isActionFocused = false

  private var isSelected: Bool { state.selectedID == block.id }
  private var isHovered: Bool { state.hoveredRow.map(frame.rows.contains) ?? false }
  private var showsActions: Bool { isHovered || isSelected || isActionFocused }

  var body: some View {
    ZStack(alignment: .top) {
      Color.clear
        .contentShape(.rect)
        .contextMenu { menu }
        .reportsRegion(.block(block.id), to: state)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text(String(localized: "Copy Command", comment: "Context menu item and VoiceOver action on a command block: copies the command that was run."))) { actions.copyCommand(block) }
        .accessibilityAction(named: Text(String(localized: "Copy Output", comment: "Context menu item, button and VoiceOver action on a command block: copies the text the command printed."))) { actions.copyOutput(block) }
        .accessibilityAction(named: Text(String(localized: "Repeat", comment: "Button on a command block that runs the same command again. Verb."))) { actions.repeatCommand(block) }
      if frame.showsHeader { header }
    }
    .overlay(alignment: .top) {
      if frame.showsHeader && frame.rows.lowerBound > geometry.visibleRows.lowerBound {
        BlockTokens.hair.frame(height: 0.5).accessibilityHidden(true)
      }
    }
    .overlay {
      if isActionFocused {
        Rectangle().strokeBorder(BlockTokens.accent, lineWidth: 2).accessibilityHidden(true)
      } else if isSelected {
        Rectangle().strokeBorder(BlockTokens.hairStrong, lineWidth: 1).accessibilityHidden(true)
      }
    }
  }

  private var header: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        if showsActions {
          BlockActionButtons(block: block, actions: actions, isFocused: $isActionFocused)
            .reportsRegion(.control("actions-\(block.id)"), to: state)
            .transition(.opacity)
        }
        // El chip tapa lo que la shell pinte a la derecha del prompt (la hora) con el mismo
        // fondo que tiene el bloque debajo del texto, así no se ve como una caja aparte.
        BlockChipView(block: block)
          .padding(.horizontal, 4)
          .background {
            BlockFill(isFailure: block.hasFailed, rows: frame.rows, id: block.id, state: state)
              .background(BlockTokens.background)
          }
      }
      .font(.system(size: 11.5).monospacedDigit())
      .frame(height: max(geometry.cellHeight, 18))
      .padding(.horizontal, 16)
      .animation(BlockTokens.hover, value: showsActions)
      if block.state == .running {
        RunningProgressBar(startedInstant: block.startedInstant)
      }
      Spacer(minLength: 0)
    }
  }

  @ViewBuilder private var menu: some View {
    Button(String(localized: "Copy", comment: "Button on a command block that copies the command text to the clipboard. Verb, not a noun.")) { actions.copyCommand(block) }
      .disabled(actions.command(of: block) == nil)
    Button(String(localized: "Copy Output", comment: "Context menu item, button and VoiceOver action on a command block: copies the text the command printed.")) { actions.copyOutput(block) }
      .disabled(!actions.canCopyOutput(block))
    Button(String(localized: "Repeat", comment: "Button on a command block that runs the same command again. Verb.")) { actions.repeatCommand(block) }
      .disabled(!actions.canRepeat(block))
  }
}

/// Copiar confirma en el propio botón ("Copied", 1,4 s) además del toast.
private struct BlockActionButtons: View {
  static let confirmation: Duration = .milliseconds(1_400)

  enum Action: Hashable { case copy, copyOutput, repeatCommand }

  let block: CommandBlock
  let actions: BlockActions
  /// Foco de teclado en alguna acción: el bloque muestra su anillo de 2 pt.
  @Binding var isFocused: Bool
  @State private var copiedAt: ContinuousClock.Instant?
  @FocusState private var focusedAction: Action?

  var body: some View {
    HStack(spacing: 2) {
      Button(copiedAt == nil ? String(localized: "Copy", comment: "Button on a command block that copies the command text to the clipboard. Verb, not a noun.") : String(localized: "Copied", comment: "Label of the Copy button for one second after the command was copied, and toast text. Past participle.")) {
        actions.copyCommand(block)
        copiedAt = .now
      }
      .buttonStyle(BlockActionButtonStyle(confirmed: copiedAt != nil))
      .disabled(actions.command(of: block) == nil)
      .focused($focusedAction, equals: .copy)
      if actions.canCopyOutput(block) {
        Button(String(localized: "Copy Output", comment: "Context menu item, button and VoiceOver action on a command block: copies the text the command printed.")) { actions.copyOutput(block) }
          .buttonStyle(BlockActionButtonStyle())
          .focused($focusedAction, equals: .copyOutput)
      }
      Button(String(localized: "Repeat", comment: "Button on a command block that runs the same command again. Verb.")) { actions.repeatCommand(block) }
        .buttonStyle(BlockActionButtonStyle())
        .disabled(!actions.canRepeat(block))
        .focused($focusedAction, equals: .repeatCommand)
        .help(String(localized: "Writes the command to the prompt without running it", comment: "Tooltip of the Repeat button on a command block."))
    }
    .onChange(of: focusedAction) { _, action in isFocused = action != nil }
    .onDisappear { isFocused = false }
    .task(id: copiedAt) {
      guard copiedAt != nil else { return }
      do { try await Task.sleep(for: Self.confirmation) } catch { return }
      copiedAt = nil
    }
  }
}

/// Barra indeterminada de 1 pt bajo la cabecera, solo cuando el comando pasa de 2 s. Con Reduce
/// Motion queda fija al 35 %.
private struct RunningProgressBar: View {
  static let period = 1.2

  let startedInstant: ContinuousClock.Instant?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    // Se comprueba cada medio segundo si ya pasó de 2 s; solo entonces se anima a 30 fps.
    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
      if isLong {
        if reduceMotion {
          BlockTokens.accent.opacity(0.35)
        } else {
          sweep
        }
      }
    }
    .frame(height: 1)
    .clipped()
    .accessibilityHidden(true)
  }

  private var sweep: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
      GeometryReader { proxy in
        let phase = context.date.timeIntervalSinceReferenceDate
          .truncatingRemainder(dividingBy: Self.period) / Self.period
        let width = proxy.size.width * 0.3
        BlockTokens.accent.opacity(0.6)
          .frame(width: width)
          .offset(x: (proxy.size.width + width) * phase - width)
      }
    }
  }

  private var isLong: Bool {
    startedInstant.map { ContinuousClock.now - $0 > BlockChip.longCommand } ?? false
  }
}

extension View {
  /// Publica el rectángulo de esta vista para que `BlocksOverlayHostingView` deje pasar el clic.
  func reportsRegion(_ region: BlockOverlayState.Region, to state: BlockOverlayState) -> some View {
    onGeometryChange(for: CGRect.self) { $0.frame(in: .named(BlocksOverlayView.coordinateSpace)) }
      action: { state.setRegion($0, for: region) }
      .onDisappear { state.setRegion(nil, for: region) }
  }
}
