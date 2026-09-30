@preconcurrency import Supabase
import SwiftUI

enum NativeAppearance: String, CaseIterable, Sendable {
  case system, light, dark
  var title: String { rawValue.capitalized }
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

/// Web `/settings`: the account, what MemoTrail calls you, your Timeline starting point, the
/// default time zone, appearance, and the paths to AI status, organization, and export.
struct NativeSettingsView: View {
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  @AppStorage("native-appearance") private var appearance = NativeAppearance.system
  @State private var controller: SettingsController
  @State private var preferredName = ""
  @State private var birthDate = ""
  @State private var timezone = "UTC"
  @Environment(AppNavigator.self) private var navigator

  init(
    client: SupabaseClient, user: AuthenticatedUser, isAuthenticationBusy: Bool,
    signOut: @escaping @MainActor () async -> Void
  ) {
    self.client = client
    self.user = user
    self.isAuthenticationBusy = isAuthenticationBusy
    self.signOut = signOut
    _controller = State(initialValue: SettingsController(client: client, ownerID: user.id))
  }

  private var accountName: String { controller.profile?.preferredName ?? user.name }

  var body: some View {
    MTPage(width: .compact) {
      MTPageHeader(
        eyebrow: "Your private space", title: "Settings",
        description: "Manage your account and the way MemoTrail works for you.")
      account
      preferences
      privacyNote
    }
    .scrollDismissesKeyboard(.interactively)
    .refreshable { await load() }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
  }

  private var account: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      SettingsSectionHeading(title: "Account", detail: "Your current MemoTrail identity") {
        MTBadge(title: "Connected", size: .micro, uppercase: true)
      }
      accountCard
      if let message = controller.loadErrorMessage {
        Label(message, icon: .warning)
          .font(MTFont.caption)
          .foregroundStyle(MTColor.warm)
      }
      if controller.profile != nil {
        SettingsFormCard(
          title: "What should we call you?",
          detail: "Used in your Home greeting. Leave blank to use your Google name."
        ) {
          MTTextField(
            label: "Preferred name", text: $preferredName, prompt: user.name, maxLength: 80
          )
          .textContentType(.nickname)
          .accessibilityIdentifier("settings-preferred-name")
        } action: {
          saveButton(
            "Save name", field: .preferredName,
            isChanged: preferredName != (controller.profile?.preferredName ?? "")
          ) {
            await controller.savePreferredName(preferredName)
          }
        }
        SettingsFormCard(
          title: "Timeline starting point",
          detail:
            "Your birth date stays private and lets Timeline show your story from its real beginning."
        ) {
          MTDateField(label: "Birth date", value: $birthDate)
        } action: {
          saveButton(
            "Save birth date", field: .birthDate,
            isChanged: birthDate != (controller.profile?.birthDate ?? "")
          ) {
            await controller.saveBirthDate(birthDate)
          }
        }
      }
    }
  }

  /// Web `accountCard`: the initial, name, email, and sign-in method, then Sign out.
  private var accountCard: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      HStack(spacing: MTSpacing.s4) {
        Text(accountName.first.map { String($0).uppercased() } ?? user.initial)
          .font(MTFont.body.weight(.semibold))
          .foregroundStyle(MTColor.accentInk)
          .frame(width: 48, height: 48)
          .background(MTColor.accent, in: Circle())
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(accountName)
            .font(MTFont.cardTitle)
            .foregroundStyle(MTColor.ink)
            .lineLimit(1)
          Text(user.email)
            .font(MTFont.caption.weight(.regular))
            .foregroundStyle(MTColor.inkMuted)
            .lineLimit(1)
          Text("Google Sign-In")
            .font(.caption2)
            .foregroundStyle(MTColor.inkFaint)
            .padding(.top, 3)
        }
        .accessibilityElement(children: .combine)
      }
      Button("Sign out") { Task { await signOut() } }
        .mtButtonStyle(isLoading: isAuthenticationBusy, fillsWidth: true)
        .disabled(isAuthenticationBusy)
        .accessibilityIdentifier("settings-sign-out")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s5)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border, lineWidth: 1)
    }
  }

  private var preferences: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      SettingsSectionHeading(
        title: "Preferences", detail: "Controls already available in this version")
      if controller.profile != nil {
        SettingsFormCard(
          title: "Default time zone",
          detail:
            "Used for new exact times. Existing moments keep the time zone recorded with them."
        ) {
          MTTimeZoneField(label: "Time zone", selection: $timezone)
        } action: {
          saveButton(
            "Save time zone", field: .timezone,
            isChanged: timezone != (controller.profile?.timezone ?? "UTC")
          ) {
            await controller.saveTimezone(timezone)
          }
        }
      }
      VStack(spacing: 0) {
        SettingsPreferenceRow(
          icon: .settings, title: "Appearance",
          detail: "Follow this device or choose a consistent light or dark theme."
        ) {
          Picker("Appearance mode", selection: $appearance) {
            ForEach(NativeAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("settings-appearance")
        }
        MTListDivider()
        SettingsPreferenceLink(
          icon: .sparkle, title: "AI capabilities · Beta",
          detail: "Off and unavailable while we rethink how AI can help."
        ) {
          AISettingsView()
        }
        MTListDivider()
        SettingsWorkspaceLink(
          icon: .archive, title: "Archive organization",
          detail: "Open the Library to manage Collections and tags across items.",
          route: .collections)
        MTListDivider()
        SettingsPreferenceLink(
          icon: .archive, title: "Export archive",
          detail: "Create a complete portable copy of your private archive."
        ) {
          ExportView(client: client, ownerID: user.id)
        }
        #if DEBUG
          MTListDivider()
          SettingsPreferenceLink(
            icon: .dashboard, title: "Design System",
            detail: "Every native component and state, for review builds."
          ) {
            DesignSystemGallery()
          }
        #endif
      }
      .background(MTColor.surfaceRaised)
      .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border, lineWidth: 1)
      }
    }
  }

  /// Web `privacyNote`.
  private var privacyNote: some View {
    HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s3) {
      Image(.check)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(MTColor.accent)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text("Private by default")
          .font(MTFont.label)
          .foregroundStyle(MTColor.ink)
        Text("Your account and archive are not shared with other MemoTrail users.")
          .font(MTFont.caption.weight(.regular))
          .foregroundStyle(MTColor.inkMuted)
          .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
      }
      .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, MTSpacing.s5)
    .padding(.vertical, MTSpacing.s4)
    .background(MTColor.accentSubtle, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .accessibilityElement(children: .combine)
  }

  /// Web saves each setting on its own, enabled only once it changes, and confirms with a toast.
  private func saveButton(
    _ title: String, field: SettingsController.Field, isChanged: Bool,
    save: @escaping @MainActor () async -> SettingsController.SaveResult
  ) -> some View {
    Button(title) {
      // Saving submits the field, like a Web form, so the keyboard closes.
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      Task {
        let result = await save()
        if result.isSaved {
          MTToastCenter.shared.success(result.message)
          syncDrafts()
          if field == .preferredName { navigator.profileRevision += 1 }
        } else {
          MTToastCenter.shared.error(result.message)
        }
      }
    }
    .mtButtonStyle(isLoading: controller.savingField == field)
    .disabled(!isChanged || controller.savingField != nil)
  }

  private func load() async {
    await controller.load()
    syncDrafts()
  }

  /// Shows the saved profile in each field.
  private func syncDrafts() {
    guard let profile = controller.profile else { return }
    preferredName = profile.preferredName ?? ""
    birthDate = profile.birthDate ?? ""
    timezone = profile.timezone
  }
}

/// Web `sectionHeading`: an uppercase title, a quiet line beneath, and an optional status.
private struct SettingsSectionHeading<Trailing: View>: View {
  let title: String
  let detail: String
  private let trailing: Trailing

  init(title: String, detail: String, @ViewBuilder trailing: () -> Trailing) {
    self.title = title
    self.detail = detail
    self.trailing = trailing()
  }

  var body: some View {
    HStack(alignment: .center, spacing: MTSpacing.s4) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title.uppercased())
          .font(MTFont.label.weight(.semibold))
          .tracking(0.6)
          .foregroundStyle(MTColor.ink)
          .accessibilityAddTraits(.isHeader)
        Text(detail)
          .font(MTFont.caption.weight(.regular))
          .foregroundStyle(MTColor.inkFaint)
      }
      Spacer(minLength: 0)
      trailing
    }
    .padding(.top, MTSpacing.s4)
  }
}

extension SettingsSectionHeading where Trailing == EmptyView {
  init(title: String, detail: String) {
    self.init(title: title, detail: detail) { EmptyView() }
  }
}

/// A Web settings form card: a serif title and note, the field, then its save action.
private struct SettingsFormCard<Field: View, Action: View>: View {
  let title: String
  let detail: String
  private let field: Field
  private let action: Action

  init(
    title: String, detail: String, @ViewBuilder field: () -> Field,
    @ViewBuilder action: () -> Action
  ) {
    self.title = title
    self.detail = detail
    self.field = field()
    self.action = action()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      VStack(alignment: .leading, spacing: MTSpacing.s1) {
        Text(title)
          .font(MTFont.cardTitle)
          .foregroundStyle(MTColor.ink)
          .accessibilityAddTraits(.isHeader)
        Text(detail)
          .font(MTFont.caption.weight(.regular))
          .foregroundStyle(MTColor.inkFaint)
          .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
      }
      .fixedSize(horizontal: false, vertical: true)
      field
      action
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s5)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border, lineWidth: 1)
    }
  }
}

/// A preference row with its icon tile, serif title, and control beneath.
private struct SettingsPreferenceRow<Control: View>: View {
  let icon: MTIcon
  let title: String
  let detail: String
  private let control: Control

  init(icon: MTIcon, title: String, detail: String, @ViewBuilder control: () -> Control) {
    self.icon = icon
    self.title = title
    self.detail = detail
    self.control = control()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      SettingsPreferenceLabel(icon: icon, title: title, detail: detail)
      control
    }
    .padding(MTSpacing.s4)
  }
}

/// A preference row that opens its own page.
private struct SettingsPreferenceLink<Destination: View>: View {
  let icon: MTIcon
  let title: String
  let detail: String
  @ViewBuilder let destination: () -> Destination

  var body: some View {
    NavigationLink(destination: destination) {
      SettingsLinkRow(icon: icon, title: title, detail: detail)
    }
    .buttonStyle(MTListRowButtonStyle())
    // The row is named by its title; the detail line explains where it leads.
    .accessibilityLabel(title)
    .accessibilityHint(detail)
  }
}

/// A preference row that leaves Settings for a workspace page, like Web's Settings links outside
/// `/settings`. The Settings sheet closes first; Settings in the More tab pushes the page.
private struct SettingsWorkspaceLink: View {
  let icon: MTIcon
  let title: String
  let detail: String
  let route: WorkspaceRoute
  @Environment(AppNavigator.self) private var navigator
  @Environment(\.isSettingsSheet) private var isSettingsSheet

  var body: some View {
    Button {
      if isSettingsSheet {
        navigator.routeAfterSettings = route
      } else {
        navigator.morePath.append(route)
      }
    } label: {
      SettingsLinkRow(icon: icon, title: title, detail: detail)
    }
    .buttonStyle(MTListRowButtonStyle())
    .accessibilityLabel(title)
    .accessibilityHint(detail)
  }
}

/// A link row: the label, then a chevron.
private struct SettingsLinkRow: View {
  let icon: MTIcon
  let title: String
  let detail: String

  var body: some View {
    HStack(spacing: MTSpacing.s3) {
      SettingsPreferenceLabel(icon: icon, title: title, detail: detail)
      Spacer(minLength: 0)
      Image(.chevron)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(MTColor.ink)
    }
    .padding(MTSpacing.s4)
    .frame(minHeight: 76)
    .contentShape(Rectangle())
  }
}

private struct SettingsPreferenceLabel: View {
  let icon: MTIcon
  let title: String
  let detail: String

  var body: some View {
    HStack(spacing: MTSpacing.s3) {
      Image(icon)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(MTColor.accent)
        .frame(width: 42, height: 42)
        .background(MTColor.accentSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(MTFont.cardTitle)
          .foregroundStyle(MTColor.ink)
        Text(detail)
          .font(MTFont.caption.weight(.regular))
          .foregroundStyle(MTColor.inkFaint)
          .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}
