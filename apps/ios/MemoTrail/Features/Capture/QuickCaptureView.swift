import SwiftUI

/// Web `QuickCaptureDialog` at phone width: the shared composer under its own header.
struct QuickCaptureView: View {
  @Bindable var controller: CaptureController
  @Binding var title: String
  @Binding var note: NSAttributedString
  @Binding var occurrence: OccurrenceDraft?
  @Binding var photos: [PhotoDraft]
  let addPhoto: @MainActor (PhotoDraft) async throws -> Void
  let removePhoto: @MainActor (UUID) async throws -> Void
  @Binding var hasLocalDraft: Bool

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    // Web `QuickCaptureDialog` at phone width: a full-screen composer under its own header.
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        CaptureCard(
          note: $note,
          occurrence: $occurrence,
          photos: $photos,
          style: .dialog,
          isSaving: controller.isSaving,
          hasLocalDraft: hasLocalDraft,
          error: controller.captureError,
          focusRequest: 1,
          uploadProgress: controller.photoUploadProgress,
          addPhoto: addPhoto,
          removePhoto: removePhoto,
          save: save
        )

        if controller.hasWaitingCaptures {
          pendingSection
        }
      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollDismissesKeyboard(.interactively)
    .safeAreaInset(edge: .top, spacing: 0) { header }
    .background(MTColor.surfaceRaised.ignoresSafeArea())
  }

  /// Web `dialogHeader`: the composer's question beside a quiet close button.
  private var header: some View {
    HStack(spacing: MTSpacing.s4) {
      HStack(spacing: MTSpacing.s3) {
        CaptureSpark()
        Text("What\u{2019}s on your mind?")
          .font(MTFont.cardTitle)
          .foregroundStyle(MTColor.ink)
          // Wraps in full at accessibility text sizes, like the Dashboard composer's title.
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
      }
      Spacer(minLength: 0)
      MTIconButton(label: "Close quick capture", icon: .close, size: .small) { dismiss() }
        // Like Web's dialog, Escape on a hardware keyboard closes it.
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("close-quick-capture")
    }
    .padding(.horizontal, MTSpacing.s4)
    .padding(.vertical, MTSpacing.s4)
    .frame(minHeight: MTLayout.QuickCapture.barHeight)
    .mtMaterial(MTMaterial.glassPanel)
  }

  /// Web's dialog pending section: what still waits on this iPhone, under the composer, with
  /// Retry now while something can still sync.
  private var pendingSection: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      MTSectionHeader(
        "Pending sync", variant: .list,
        detail: countLabel(
          controller.pendingEntries.count + controller.unreadableCaptures.count, "Entry")
      ) {
        PendingCaptureRetryButton(controller: controller)
      }
      .padding(.horizontal, MTSpacing.s4)
      PendingCaptureList(controller: controller)
        .overlay(alignment: .top) { MTListDivider() }
    }
    .padding(.top, MTSpacing.s5)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("capture-pending-section")
  }

  @MainActor
  private func save() async {
    let didSave = await controller.save(
      title: title, note: note, occurrenceDraft: occurrence, photos: photos)

    if didSave {
      title = ""
      note = NSAttributedString()
      occurrence = nil
      photos = []
      hasLocalDraft = false
      dismiss()
    }
  }
}
