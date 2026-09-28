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

struct NativeSettingsView: View {
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void
  @AppStorage("native-appearance") private var appearance = NativeAppearance.system
  @State private var showingAccount = false

  var body: some View {
    Form {
      Section("Account") {
        Button {
          showingAccount = true
        } label: {
          Label(user.name, systemImage: "person.crop.circle")
        }
        NavigationLink("Dates & time zone") {
          Form {
            LabeledContent("Time zone", value: TimeZone.current.identifier)
            Text(
              "The app currently follows your device's date and time preferences. Each record keeps its own recorded time zone."
            )
            .foregroundStyle(MTColor.inkMuted)
          }.navigationTitle("Dates & time zone")
        }
      }
      Section("Appearance") {
        Picker("Appearance", selection: $appearance) {
          ForEach(NativeAppearance.allCases, id: \.self) { value in Text(value.title).tag(value) }
        }
      }
      Section("Library") {
        NavigationLink("Collections") {
          CollectionsView(client: client, ownerID: user.id, embedded: true)
        }
        NavigationLink("Tags") {
          OrganizationView(client: client, ownerID: user.id, initialKind: .tag)
        }
        NavigationLink("Organization settings") {
          OrganizationView(client: client, ownerID: user.id)
        }
      }
      Section("Archive") {
        NavigationLink("Export archive") { ExportView(client: client, ownerID: user.id) }
      }
      Section("Beta") {
        NavigationLink("AI assistance") { AISettingsView(client: client, ownerID: user.id) }
        Text("AI features are paused.").font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
      }
      #if DEBUG
        Section("Development") {
          NavigationLink("Design System") { DesignSystemGallery() }
        }
      #endif
    }
    .scrollContentBackground(.hidden).background(MTColor.canvas)
    .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showingAccount) {
      AccountView(user: user, isBusy: isAuthenticationBusy, signOut: signOut)
    }
  }
}
