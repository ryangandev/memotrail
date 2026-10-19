import SwiftUI

/// The shared field surface's size. Each field takes its own generated size enum, from its
/// component spec, and converts it here, so removing a size from a spec breaks the build.
enum MTFieldSize: CaseIterable, Sendable {
  case small, medium, large

  /// The Web field heights (34, 42, 48) raised slightly for native touch targets.
  var height: CGFloat {
    switch self {
    case .small: MTSize.Field.small
    case .medium: MTSize.Field.medium
    case .large: MTSize.Field.large
    }
  }

  var radius: CGFloat { self == .small ? MTRadius.small : MTRadius.medium }

  init(_ size: MTTextFieldSize) {
    switch size {
    case .small: self = .small
    case .medium: self = .medium
    case .large: self = .large
    }
  }

  init(_ size: MTSearchFieldSize) {
    switch size {
    case .small: self = .small
    case .medium: self = .medium
    case .large: self = .large
    }
  }

  init(_ size: MTSelectFieldSize) {
    switch size {
    case .small: self = .small
    case .medium: self = .medium
    case .large: self = .large
    }
  }

  init(_ size: MTDateFieldSize) {
    switch size {
    case .small: self = .small
    case .medium: self = .medium
    case .large: self = .large
    }
  }
}

/// The label above a field, with a warm required mark and an optional quiet note.
/// Controls carry their own accessibility label, so this visual label is hidden from VoiceOver.
struct MTFieldLabel: View {
  let title: String
  var isRequired = false
  var note: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s2) {
      Text("\(title)\(isRequired ? Text(" *").foregroundStyle(MTColor.warm) : Text(""))")
        .font(MTFont.label)
        .foregroundStyle(MTColor.inkMuted)
      if let note {
        Text(note).font(MTFont.note).foregroundStyle(MTColor.inkFaint)
      }
    }
    .accessibilityHidden(true)
  }
}

private struct MTFieldSurface: ViewModifier {
  let size: MTFieldSize
  let isFocused: Bool
  var isInvalid = false
  var focus: (() -> Void)?
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.mtFieldFill) private var fill

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: size.radius)
    content
      .padding(.horizontal, MTSpacing.s3)
      .frame(maxWidth: .infinity, minHeight: size.height, alignment: .leading)
      .background {
        let surface = ZStack {
          // The Web focus ring: a 3 point accent halo outside the border.
          if isFocused { shape.stroke(MTState.Focus.halo, lineWidth: MTState.Focus.haloStroke) }
          shape.fill(isEnabled ? fill : MTColor.surfaceSubtle)
        }
        if let focus {
          // Taps around the text also focus it. The gesture stays on the decorative
          // background so VoiceOver sees only the text field itself.
          surface.contentShape(shape).onTapGesture(perform: focus).accessibilityHidden(true)
        } else {
          surface
        }
      }
      .overlay {
        shape.strokeBorder(border, lineWidth: MTSize.Stroke.thin)
      }
      .contentShape(shape)
      .opacity(isEnabled ? 1 : MTState.Disabled.Opacity.field)
      .animation(MTEasing.enter.animation(duration: MTMotion.quick), value: isFocused)
  }

  // Focus wins over an error, as on Web, so the field reads as active while it is corrected.
  private var border: Color {
    if isFocused { return MTColor.accent }
    return isInvalid ? MTColor.warm : MTColor.borderStrong
  }
}

extension View {
  /// The shared field surface: height, border, focus ring, and the invalid and disabled
  /// treatments.
  func mtFieldSurface(
    size: MTFieldSize = .medium, isFocused: Bool = false, isInvalid: Bool = false,
    focus: (() -> Void)? = nil
  ) -> some View {
    modifier(MTFieldSurface(size: size, isFocused: isFocused, isInvalid: isInvalid, focus: focus))
  }

  fileprivate func mtFieldAccessibility(_ label: String, isRequired: Bool) -> some View {
    accessibilityLabel(isRequired ? "\(label), required" : label)
  }

  @ViewBuilder fileprivate func mtLineLimit(_ lines: ClosedRange<Int>?) -> some View {
    if let lines { lineLimit(lines) } else { self }
  }
}

/// A labeled single-line input, or with a vertical axis a growing textarea. `lines` sets the
/// textarea's visible range, like Web `rows`, without affecting the label. An `error` draws the
/// warm border and its message below the field, and VoiceOver reads it as the hint.
/// Specified in packages/design-system/components/text-field.yaml.
struct MTTextField: View {
  let label: String
  @Binding var text: String
  var prompt: String?
  var size: MTTextFieldSize = MTTextFieldDefaults.size
  var isRequired = MTTextFieldDefaults.isRequired
  var note: String?
  var hidesLabel = MTTextFieldDefaults.hidesLabel
  var error: String?
  var maxLength: Int?
  var axis: Axis = .horizontal
  var lines: ClosedRange<Int>?
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      if !hidesLabel { MTFieldLabel(title: label, isRequired: isRequired, note: note) }
      // Like a Web input, a labeled field stays empty without a prompt; a field that hides its
      // label shows it as the placeholder instead.
      TextField(
        label, text: $text,
        prompt: Text(prompt ?? (hidesLabel ? label : "")).foregroundStyle(MTColor.inkFaint),
        axis: axis
      )
      .mtLineLimit(lines)
      .font(MTFont.body)
      .foregroundStyle(MTColor.ink)
      .focused($isFocused)
      .padding(.vertical, axis == .vertical ? MTLayout.Field.textareaInset : 0)
      .mtFieldSurface(size: MTFieldSize(size), isFocused: isFocused, isInvalid: error != nil) {
        isFocused = true
      }
      .mtFieldAccessibility(label, isRequired: isRequired)
      .accessibilityHint(error ?? "")
      .onChange(of: text) {
        if let maxLength, text.count > maxLength { text = String(text.prefix(maxLength)) }
      }
      if let error {
        // The field's hint already reads the message, so VoiceOver skips the visible copy.
        Text(error).font(MTFont.caption).foregroundStyle(MTColor.warm).accessibilityHidden(true)
      }
    }
  }
}

/// A search input with one focus surface for the icon, text, clear action, and trailing content.
/// Specified in packages/design-system/components/search-field.yaml.
struct MTSearchField<Trailing: View>: View {
  let label: String
  @Binding var text: String
  var prompt: String?
  var size: MTSearchFieldSize
  var hidesLabel: Bool
  var maxLength: Int?
  /// Each increase moves keyboard focus into the field.
  var focusRequest: Int
  private let trailing: Trailing
  @FocusState private var isFocused: Bool

  init(
    _ label: String, text: Binding<String>, prompt: String? = nil,
    size: MTSearchFieldSize = MTSearchFieldDefaults.size,
    hidesLabel: Bool = MTSearchFieldDefaults.hidesLabel, maxLength: Int? = nil,
    focusRequest: Int = 0, @ViewBuilder trailing: () -> Trailing
  ) {
    self.label = label
    _text = text
    self.prompt = prompt
    self.size = size
    self.hidesLabel = hidesLabel
    self.maxLength = maxLength
    self.focusRequest = focusRequest
    self.trailing = trailing()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      if !hidesLabel { MTFieldLabel(title: label) }
      HStack(spacing: MTSpacing.s2) {
        Image(.search)
          .font(.mtIcon(size == .small ? MTSize.Icon.s14 : MTSize.Icon.s16, weight: .medium))
          .foregroundStyle(MTColor.inkFaint)
          .accessibilityHidden(true)
        TextField(
          label, text: $text, prompt: prompt.map { Text($0).foregroundStyle(MTColor.inkFaint) }
        )
        .font(MTFont.body)
        .foregroundStyle(MTColor.ink)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .focused($isFocused)
        .accessibilityLabel(label)
        if !text.isEmpty {
          Button {
            text = ""
          } label: {
            Image(systemName: "xmark.circle.fill").font(.mtIcon(MTSize.Icon.s15))
          }
          .buttonStyle(.plain)
          .foregroundStyle(MTColor.inkFaint)
          .frame(width: MTLayout.Field.accessory, height: MTLayout.Field.accessory)
          .contentShape(Rectangle())
          .accessibilityLabel("Clear \(label.lowercased())")
        }
        trailing
      }
      .mtFieldSurface(size: MTFieldSize(size), isFocused: isFocused) { isFocused = true }
    }
    .onChange(of: text) {
      if let maxLength, text.count > maxLength { text = String(text.prefix(maxLength)) }
    }
    .onChange(of: focusRequest) { isFocused = true }
  }
}

extension MTSearchField where Trailing == EmptyView {
  init(
    _ label: String, text: Binding<String>, prompt: String? = nil,
    size: MTSearchFieldSize = MTSearchFieldDefaults.size,
    hidesLabel: Bool = MTSearchFieldDefaults.hidesLabel, maxLength: Int? = nil,
    focusRequest: Int = 0
  ) {
    self.init(
      label, text: text, prompt: prompt, size: size, hidesLabel: hidesLabel, maxLength: maxLength,
      focusRequest: focusRequest
    ) {
      EmptyView()
    }
  }
}

/// A titled run of options inside an `MTSelectField` menu, like a Web `optgroup`.
struct MTSelectGroup<Value: Hashable>: Hashable {
  var title: String?
  let options: [Value]
}

/// A labeled single choice presented as a native menu with a check beside the selection.
/// Specified in packages/design-system/components/select-field.yaml.
struct MTSelectField<Value: Hashable>: View {
  let label: String
  @Binding var selection: Value
  let groups: [MTSelectGroup<Value>]
  let title: (Value) -> String
  var size: MTSelectFieldSize
  var isRequired: Bool
  var note: String?
  var hidesLabel: Bool

  init(
    label: String, selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String,
    size: MTSelectFieldSize = MTSelectFieldDefaults.size,
    isRequired: Bool = MTSelectFieldDefaults.isRequired, note: String? = nil,
    hidesLabel: Bool = MTSelectFieldDefaults.hidesLabel
  ) {
    self.init(
      label: label, selection: selection, groups: [MTSelectGroup(options: options)], title: title,
      size: size, isRequired: isRequired, note: note, hidesLabel: hidesLabel)
  }

  init(
    label: String, selection: Binding<Value>, groups: [MTSelectGroup<Value>],
    title: @escaping (Value) -> String, size: MTSelectFieldSize = MTSelectFieldDefaults.size,
    isRequired: Bool = MTSelectFieldDefaults.isRequired, note: String? = nil,
    hidesLabel: Bool = MTSelectFieldDefaults.hidesLabel
  ) {
    self.label = label
    _selection = selection
    self.groups = groups
    self.title = title
    self.size = size
    self.isRequired = isRequired
    self.note = note
    self.hidesLabel = hidesLabel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      if !hidesLabel { MTFieldLabel(title: label, isRequired: isRequired, note: note) }
      Menu {
        // Titled sections of checkable items, because a menu Picker drops section titles.
        ForEach(groups, id: \.self) { group in
          if let heading = group.title {
            Section(heading) { options(group) }
          } else {
            Section { options(group) }
          }
        }
      } label: {
        HStack(spacing: MTSpacing.s2) {
          // A long choice wraps once rather than hiding its end, as at larger text sizes.
          Text(title(selection))
            .font(MTFont.body)
            .foregroundStyle(MTColor.ink)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
          Spacer(minLength: 0)
          Image(.chevron)
            .font(.mtIcon(MTSize.Icon.s11, weight: .semibold))
            .rotationEffect(.degrees(90))
            .foregroundStyle(MTColor.inkFaint)
        }
        .mtFieldSurface(size: MTFieldSize(size))
      }
      .buttonStyle(.plain)
      .mtFieldAccessibility(label, isRequired: isRequired)
      .accessibilityValue(title(selection))
    }
  }

  private func options(_ group: MTSelectGroup<Value>) -> some View {
    ForEach(group.options, id: \.self) { option in
      Toggle(
        title(option),
        isOn: Binding(get: { selection == option }, set: { if $0 { selection = option } }))
    }
  }
}

extension MTCheckboxSize {
  fileprivate var box: CGFloat {
    switch self {
    case .small: MTSize.Checkbox.small
    case .medium: MTSize.Checkbox.medium
    }
  }

  fileprivate var radius: CGFloat {
    switch self {
    case .small: MTRadius.xxsmall
    case .medium: MTRadius.checkbox
    }
  }

  fileprivate var check: CGFloat {
    switch self {
    case .small: MTSize.Icon.s10
    case .medium: MTSize.Icon.s12
    }
  }

  fileprivate var label: Font {
    switch self {
    case .small: MTFont.caption
    case .medium: MTFont.label
    }
  }

  fileprivate var detail: Font {
    switch self {
    case .small: MTFont.fine
    case .medium: MTFont.caption
    }
  }
}

/// A checkbox with a label and optional explanation, matching the Web form toggles.
/// Specified in packages/design-system/components/checkbox.yaml.
struct MTCheckbox: View {
  let title: String
  var detail: String?
  @Binding var isOn: Bool
  var size: MTCheckboxSize = MTCheckboxDefaults.size
  /// Names the whole row for UI tests. The row is one accessibility element, so the identifier
  /// goes on that element rather than on a modifier around the checkbox.
  var identifier: String?
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    if let identifier {
      control.accessibilityIdentifier(identifier)
    } else {
      control
    }
  }

  private var control: some View {
    Button {
      isOn.toggle()
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s3) {
        RoundedRectangle(cornerRadius: size.radius)
          .fill(isOn ? MTState.Selected.fill : MTColor.surface)
          .strokeBorder(
            isOn ? MTState.Selected.fill : MTColor.borderStrong, lineWidth: MTSize.Stroke.thin
          )
          .frame(width: size.box, height: size.box)
          .overlay {
            if isOn {
              Image(.check).font(.mtIcon(size.check, weight: .bold))
                .foregroundStyle(MTState.Selected.onFill)
            }
          }
          .alignmentGuide(.firstTextBaseline) {
            $0[VerticalAlignment.center] + MTLayout.Checkbox.baselineOffset
          }
        VStack(alignment: .leading, spacing: MTSpacing.s0_5) {
          Text(title).font(size.label).foregroundStyle(MTColor.ink)
          if let detail {
            Text(detail).font(size.detail).foregroundStyle(MTColor.inkMuted)
          }
        }
        Spacer(minLength: 0)
      }
      .frame(minHeight: MTSize.hitTarget)
      .contentShape(Rectangle())
      .opacity(isEnabled ? 1 : MTState.Disabled.Opacity.choice)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
    .accessibilityValue(isOn ? "On" : "Off")
    .accessibilityAddTraits(.isToggle)
  }
}

/// Places fields in equal columns while each keeps `minimumColumnWidth`, like the Web
/// `repeat(auto-fit, minmax(240px, 1fr))` field rows, and stacks them on narrow screens.
struct MTFieldGrid: Layout {
  var minimumColumnWidth = MTLayout.FieldGrid.minimumColumnWidth
  var spacing: CGFloat = MTSpacing.s4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard !subviews.isEmpty else { return .zero }
    let width =
      proposal.width
      ?? subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +) + spacing
      * CGFloat(subviews.count - 1)
    let frames = frames(width: width, subviews: subviews)
    return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    for (index, frame) in frames(width: bounds.width, subviews: subviews).enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        proposal: ProposedViewSize(frame.size))
    }
  }

  private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
    let columns = max(
      1, min(subviews.count, Int((width + spacing) / (minimumColumnWidth + spacing))))
    let columnWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    var frames: [CGRect] = []
    var y: CGFloat = 0
    for start in stride(from: 0, to: subviews.count, by: columns) {
      let row = start..<min(start + columns, subviews.count)
      let height =
        row.map {
          subviews[$0].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
        }
        .max() ?? 0
      for (column, _) in row.enumerated() {
        frames.append(
          CGRect(
            x: CGFloat(column) * (columnWidth + spacing), y: y, width: columnWidth, height: height)
        )
      }
      y += height + spacing
    }
    return frames
  }
}
