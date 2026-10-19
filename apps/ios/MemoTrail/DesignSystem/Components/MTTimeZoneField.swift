import SwiftUI

/// A labeled IANA time zone choice. Options show the offset on `referenceDate`, grouped like
/// the Web select: the current value when unlisted, common time zones, then all time zones.
/// A time zone always has a value, so the field has no required mark, and it always shows its
/// label. Specified in packages/design-system/components/time-zone-field.yaml.
struct MTTimeZoneField: View {
  let label: String
  @Binding var selection: String
  var referenceDate = ""
  var note: String?
  /// Opens the list as the field appears, as when a summary's Change action replaces itself
  /// with this field.
  var startsChoosing = false
  @State private var isChoosing = false

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      MTFieldLabel(title: label, note: note)
      Button {
        isChoosing = true
      } label: {
        HStack(spacing: MTSpacing.s2) {
          Text(TimeZoneOptions.optionLabel(selection, reference: referenceDate))
            .font(MTFont.body)
            .foregroundStyle(MTColor.ink)
            .lineLimit(1)
          Spacer(minLength: 0)
          Image(.chevron)
            .font(.mtIcon(MTSize.Icon.s11, weight: .semibold))
            .rotationEffect(.degrees(90))
            .foregroundStyle(MTColor.inkFaint)
        }
        .mtFieldSurface(isFocused: isChoosing)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(label)
      .accessibilityValue(TimeZoneOptions.optionLabel(selection, reference: referenceDate))
      .sheet(isPresented: $isChoosing) {
        MTTimeZonePicker(title: label, selection: $selection, referenceDate: referenceDate)
      }
    }
    .onAppear { if startsChoosing { isChoosing = true } }
  }
}

private struct MTTimeZonePicker: View {
  let title: String
  @Binding var selection: String
  let referenceDate: String
  @State private var query = ""
  @Environment(\.dismiss) private var dismiss
  private var reference: Date { TimeZoneOptions.referenceDate(referenceDate) }

  var body: some View {
    let reference = reference
    NavigationStack {
      List {
        if !TimeZoneOptions.all.contains(selection), matches(selection, reference: reference) {
          Section("Current time zone") { row(selection, reference: reference) }
        }
        let common = TimeZoneOptions.common.filter { matches($0, reference: reference) }
        if !common.isEmpty {
          Section("Common time zones") {
            ForEach(common, id: \.self) { row($0, reference: reference) }
          }
        }
        let others = TimeZoneOptions.all.filter {
          !TimeZoneOptions.common.contains($0) && matches($0, reference: reference)
        }
        if !others.isEmpty {
          Section("All time zones") {
            ForEach(others, id: \.self) { row($0, reference: reference) }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(MTColor.canvas)
      .overlay {
        if !query.isEmpty,
          !TimeZoneOptions.all.contains(where: { matches($0, reference: reference) })
        {
          ContentUnavailableView.search(text: query)
        }
      }
      .searchable(
        text: $query, placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Search city or region"
      )
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
    }
  }

  private func row(_ identifier: String, reference: Date) -> some View {
    Button {
      selection = identifier
      dismiss()
    } label: {
      HStack(spacing: MTSpacing.s3) {
        Text(TimeZoneOptions.optionLabel(identifier, at: reference))
          .font(MTFont.body)
          .foregroundStyle(MTColor.ink)
        Spacer(minLength: 0)
        if identifier == selection {
          Image(.check).font(.mtIcon(MTSize.Icon.s14, weight: .semibold)).foregroundStyle(
            MTColor.accent)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(MTColor.surface)
    .accessibilityAddTraits(identifier == selection ? .isSelected : [])
  }

  private func matches(_ identifier: String, reference: Date) -> Bool {
    let text = query.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return true }
    return identifier.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(
      text)
      || TimeZoneOptions.optionLabel(identifier, at: reference)
        .localizedCaseInsensitiveContains(text)
  }
}
