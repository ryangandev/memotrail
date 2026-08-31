import SwiftUI

struct InboxView: View {
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  private let entries = PreviewEntry.samples
  @State private var isShowingAccount = false

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: MTSpacing.s8) {
          header
          CaptureCard()
          entrySection
        }
        .padding(.horizontal, MTSpacing.s4)
        .padding(.top, MTSpacing.s6)
        .padding(.bottom, MTSpacing.s12)
      }
      .background(MTColor.canvas)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          HStack(spacing: MTSpacing.s2) {
            Text("M")
              .font(.system(size: 14, weight: .semibold, design: .serif))
              .foregroundStyle(MTColor.accentInk)
              .frame(width: 28, height: 28)
              .background(MTColor.accent, in: UnevenRoundedRectangle(cornerRadii: .init(topLeading: 8, bottomLeading: 3, bottomTrailing: 8, topTrailing: 8)))

            Text("MemoTrail")
              .font(.system(size: 18, weight: .medium, design: .serif))
              .foregroundStyle(MTColor.ink)
          }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("Search", systemImage: "magnifyingglass") {}
          Button("Profile", systemImage: "person.crop.circle.fill") {
            isShowingAccount = true
          }
          .accessibilityLabel("Open account for \(user.name)")
        }
      }
      .toolbarBackground(MTColor.surface, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .sheet(isPresented: $isShowingAccount) {
        AccountView(
          user: user,
          isBusy: isAuthenticationBusy,
          signOut: signOut
        )
      }
    }
  }

  private var header: some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Text("SUNDAY, AUGUST 30")
          .font(MTTypography.caption)
          .tracking(1.1)
          .foregroundStyle(MTColor.inkFaint)

        Text("Inbox")
          .font(MTTypography.display)
          .foregroundStyle(MTColor.ink)
      }

      Spacer()

      Button("New entry", systemImage: "plus") {}
        .labelStyle(.iconOnly)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(MTColor.accentInk)
        .frame(width: 42, height: 42)
        .background(MTColor.accent, in: RoundedRectangle(cornerRadius: MTRadius.medium))
        .accessibilityLabel("New entry")
    }
  }

  private var entrySection: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(alignment: .firstTextBaseline) {
        Text("UNSORTED")
          .font(MTTypography.label)
          .tracking(0.7)
          .foregroundStyle(MTColor.ink)

        Text("4 entries")
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkFaint)

        Spacer()

        Button("Select") {}
          .font(MTTypography.label)
          .foregroundStyle(MTColor.accent)
      }

      LazyVStack(spacing: 0) {
        ForEach(entries) { entry in
          EntryCard(entry: entry)

          if entry.id != entries.last?.id {
            Divider()
              .overlay(MTColor.border)
          }
        }

        Divider()
          .overlay(MTColor.border)

        Button("Show 1 more entry") {}
          .font(MTTypography.label)
          .foregroundStyle(MTColor.accent)
          .frame(maxWidth: .infinity)
          .frame(height: 46)
      }
      .background(MTColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large)
          .stroke(MTColor.border, lineWidth: 1)
      }
    }
  }
}

#Preview {
  InboxView(
    user: AuthenticatedUser(email: "ryan@example.com", name: "Ryan"),
    isAuthenticationBusy: false,
    signOut: {}
  )
}
