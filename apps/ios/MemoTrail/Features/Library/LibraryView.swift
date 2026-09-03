import Supabase
import SwiftUI

struct LibraryView: View {
  let client: SupabaseClient
  let ownerID: UUID

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: MTSpacing.s8) {
          header
          availableSection
          plannedSection
        }
        .padding(.horizontal, MTSpacing.s4)
        .padding(.top, MTSpacing.s6)
        .padding(.bottom, MTSpacing.s12)
      }
      .background(MTColor.canvas)
      .navigationTitle("Library")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(MTColor.surface, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text("YOUR PERSONAL ARCHIVE")
        .font(MTTypography.caption)
        .tracking(1.1)
        .foregroundStyle(MTColor.warm)

      Text("Library")
        .font(MTTypography.display)
        .foregroundStyle(MTColor.ink)

      Text("Open a part of your life without changing or duplicating the Entries behind it.")
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)
    }
  }

  private var availableSection: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      sectionTitle("AVAILABLE NOW", subtitle: "Six ways into the archive")

      ForEach(LibraryDestination.available) { destination in
        NavigationLink {
          availableDestination(destination)
        } label: {
          LibraryDestinationCard(destination: destination, isAvailable: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-\(destination.rawValue)")
      }
    }
  }

  private var plannedSection: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      sectionTitle("PLANNED ARCHIVES", subtitle: "They will join this Library as they are built")

      ForEach(LibraryDestination.planned) { destination in
        LibraryDestinationCard(destination: destination, isAvailable: false)
          .accessibilityElement(children: .combine)
          .accessibilityLabel("\(destination.title), planned")
      }
    }
  }

  private func sectionTitle(_ title: String, subtitle: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(MTTypography.label)
        .tracking(0.7)
        .foregroundStyle(MTColor.ink)

      Spacer()

      Text(subtitle)
        .font(.system(size: 10))
        .foregroundStyle(MTColor.inkFaint)
        .multilineTextAlignment(.trailing)
    }
  }

  @ViewBuilder
  private func availableDestination(_ destination: LibraryDestination) -> some View {
    switch destination {
    case .collections:
      CollectionsView(client: client, ownerID: ownerID, embedded: true)
    case .firstTimes:
      FirstTimesView(client: client, ownerID: ownerID, embedded: true)
    case .homes:
      HomesView(client: client, ownerID: ownerID, embedded: true)
    case .vehicles:
      VehiclesView(client: client, ownerID: ownerID, embedded: true)
    case .goals:
      GoalsView(client: client, ownerID: ownerID, embedded: true)
    case .trash:
      TrashView(client: client, ownerID: ownerID, embedded: true)
    case .people, .places:
      EmptyView()
    }
  }
}

private struct LibraryDestinationCard: View {
  let destination: LibraryDestination
  let isAvailable: Bool

  var body: some View {
    HStack(spacing: MTSpacing.s4) {
      Image(systemName: destination.systemImage)
        .font(.system(size: 19, weight: .medium))
        .foregroundStyle(isAvailable ? MTColor.accent : MTColor.inkFaint)
        .frame(width: 44, height: 44)
        .background(
          isAvailable ? MTColor.accentSubtle : MTColor.surfaceSubtle,
          in: RoundedRectangle(cornerRadius: MTRadius.medium)
        )

      VStack(alignment: .leading, spacing: 4) {
        Text(destination.title)
          .font(MTTypography.titleSmall)
          .foregroundStyle(isAvailable ? MTColor.ink : MTColor.inkMuted)

        Text(destination.summary)
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkFaint)
          .lineLimit(2)
      }

      Spacer(minLength: MTSpacing.s2)

      if isAvailable {
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MTColor.inkFaint)
      } else {
        Text("PLANNED")
          .font(.system(size: 9, weight: .semibold))
          .tracking(0.5)
          .foregroundStyle(MTColor.warm)
          .padding(.horizontal, 7)
          .padding(.vertical, 4)
          .background(MTColor.warmSubtle, in: Capsule())
      }
    }
    .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
    .padding(.horizontal, MTSpacing.s4)
    .padding(.vertical, MTSpacing.s3)
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }
}
