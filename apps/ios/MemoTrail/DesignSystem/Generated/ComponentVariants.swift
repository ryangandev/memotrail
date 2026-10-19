// Generated from packages/design-system/components. Do not edit directly.

// Badge, from packages/design-system/components/badge.yaml.

/// The badge's color treatment. Glass and inverse tones are for photos and maps; success and danger
/// are for outcomes.
enum MTBadgeTone: String, CaseIterable, Sendable {
  case accent
  case neutral
  case warm
  case success
  case danger
  case outline
  case inverse
  case solidAccent
  case glassAccent
  case glassNeutral
}

/// The badge's text size. Micro fits dense cards, small is the default, and medium sits beside 22
/// px controls.
enum MTBadgeSize: String, CaseIterable, Sendable {
  case micro
  case small
  case medium
}

/// Badge parameter defaults.
enum MTBadgeDefaults {
  static let tone = MTBadgeTone.accent
  static let size = MTBadgeSize.small
  static let uppercase = false
}

// Button, from packages/design-system/components/button.yaml.

/// The action's emphasis. Primary is the main action, secondary an alternative, ghost a quiet one,
/// and danger a destructive one.
enum MTButtonVariant: String, CaseIterable, Sendable {
  case primary
  case secondary
  case ghost
  case danger
}

/// The control's height, padding, and text size. Small fits dense rows and toolbars, and large
/// stands alone.
enum MTButtonSize: String, CaseIterable, Sendable {
  case small
  case medium
  case large
}

/// Button parameter defaults.
enum MTButtonDefaults {
  static let variant = MTButtonVariant.primary
  static let size = MTButtonSize.medium
  static let isLoading = false
  static let fillsWidth = false
}

// CaptureComposer, from packages/design-system/components/capture-composer.yaml.

/// Where the composer sits. Page is a raised card with its own question, on the Home Dashboard;
/// dialog is the open body of Quick Capture, which titles it.
enum MTCaptureComposerStyle: String, CaseIterable, Sendable {
  case page
  case dialog
}

/// CaptureComposer parameter defaults.
enum MTCaptureComposerDefaults {
  static let style = MTCaptureComposerStyle.page
}

// Checkbox, from packages/design-system/components/checkbox.yaml.

/// The box and text size. Small fits dense option rows under a field, and medium stands on its own.
enum MTCheckboxSize: String, CaseIterable, Sendable {
  case small
  case medium
}

/// Checkbox parameter defaults.
enum MTCheckboxDefaults {
  static let size = MTCheckboxSize.medium
}

// DateField, from packages/design-system/components/date-field.yaml.

/// The precision of the value. Day stores yyyy-MM-dd, month yyyy-MM, and year yyyy, and the
/// calendar opens at that view.
enum MTDateFieldGranularity: String, CaseIterable, Sendable {
  case day
  case month
  case year
}

/// The control's height and corner radius, from the size.field scale. Small fits filter rows, and
/// large stands alone, as the birth date does.
enum MTDateFieldSize: String, CaseIterable, Sendable {
  case small
  case medium
  case large
}

/// DateField parameter defaults.
enum MTDateFieldDefaults {
  static let granularity = MTDateFieldGranularity.day
  static let size = MTDateFieldSize.medium
  static let includesTime = false
  static let isRequired = false
}

// Dialog, from packages/design-system/components/dialog.yaml.

/// How the iOS sheet sizes itself. A form sheet opens at full height with its close action in the
/// navigation bar, and a fitted sheet sizes to short content and scrolls only when it outgrows the
/// screen.
enum MTDialogSize: String, CaseIterable, Sendable {
  case form
  case fitted
}

/// Dialog parameter defaults.
enum MTDialogDefaults {
  static let size = MTDialogSize.form
  static let isBusy = false
}

// IconButton, from packages/design-system/components/icon-button.yaml.

/// The action's emphasis, with Button's variants. Ghost is the default, because most icon actions
/// are quiet chrome; primary and secondary are for a standalone add or edit action, and danger for
/// a destructive one.
enum MTIconButtonVariant: String, CaseIterable, Sendable {
  case primary
  case secondary
  case ghost
  case danger
}

/// The square's side. Small fits dense rows and composer headers, and large stands alone.
enum MTIconButtonSize: String, CaseIterable, Sendable {
  case small
  case medium
  case large
}

/// IconButton parameter defaults.
enum MTIconButtonDefaults {
  static let variant = MTIconButtonVariant.ghost
  static let size = MTIconButtonSize.medium
  static let isLoading = false
}

// Image, from packages/design-system/components/image.yaml.

/// How the photo fills the frame. Cover crops it to fill, for thumbnails and cards; contain shows
/// it whole, for viewing a photo.
enum MTImageFit: String, CaseIterable, Sendable {
  case cover
  case contain
}

/// Image parameter defaults.
enum MTImageDefaults {
  static let fit = MTImageFit.cover
}

// PageFrame, from packages/design-system/components/page-frame.yaml.

/// The page's maximum width. Compact suits forms and focused reading, standard lists and search,
/// wide dashboards and card grids, and canvas dense spatial views.
enum MTPageFrameWidth: String, CaseIterable, Sendable {
  case compact
  case standard
  case wide
  case canvas
}

/// PageFrame parameter defaults.
enum MTPageFrameDefaults {
  static let width = MTPageFrameWidth.standard
}

// RichText, from packages/design-system/components/rich-text.yaml.

/// How the editor sits on its surface. Form is a bordered field among other fields; embedded draws
/// no field, because a host such as the capture composer already draws the surface.
enum MTRichTextVariant: String, CaseIterable, Sendable {
  case form
  case embedded
}

/// RichText parameter defaults.
enum MTRichTextDefaults {
  static let variant = MTRichTextVariant.form
}

// SearchField, from packages/design-system/components/search-field.yaml.

/// The control's height and corner radius, from the size.field scale. Small fits filter panels, and
/// large leads a page or the command palette.
enum MTSearchFieldSize: String, CaseIterable, Sendable {
  case small
  case medium
  case large
}

/// SearchField parameter defaults.
enum MTSearchFieldDefaults {
  static let size = MTSearchFieldSize.medium
  static let hidesLabel = false
}

// SectionHeader, from packages/design-system/components/section-header.yaml.

/// The heading's weight. Section is a serif title for a region of content; list is the small
/// uppercase heading above a list.
enum MTSectionHeaderVariant: String, CaseIterable, Sendable {
  case section
  case list
}

/// Where the detail sits. Start keeps it beside the title, for a count; end moves it to the far
/// edge, for a total that lines up with the list below.
enum MTSectionHeaderDetailAlign: String, CaseIterable, Sendable {
  case start
  case end
}

/// SectionHeader parameter defaults.
enum MTSectionHeaderDefaults {
  static let variant = MTSectionHeaderVariant.section
  static let detailAlign = MTSectionHeaderDetailAlign.start
}

// SelectField, from packages/design-system/components/select-field.yaml.

/// The control's height and corner radius, from the size.field scale. Small fits filter rows, and
/// large stands alone.
enum MTSelectFieldSize: String, CaseIterable, Sendable {
  case small
  case medium
  case large
}

/// SelectField parameter defaults.
enum MTSelectFieldDefaults {
  static let size = MTSelectFieldSize.medium
  static let isRequired = false
  static let hidesLabel = false
}

// SeparatedList, from packages/design-system/components/separated-list.yaml.

/// Which edge the lines share. Start fits facts read from the leading edge; end lines them up with
/// a trailing edge, such as attribution under a list.
enum MTSeparatedListAlign: String, CaseIterable, Sendable {
  case start
  case end
}

/// SeparatedList parameter defaults.
enum MTSeparatedListDefaults {
  static let align = MTSeparatedListAlign.start
}

// Skeleton, from packages/design-system/components/skeleton.yaml.

/// The placeholder's shape. Fill takes the whole container, like a photo still arriving; block is a
/// card or paragraph; line is one line of text; circle is an avatar.
enum MTSkeletonShape: String, CaseIterable, Sendable {
  case fill
  case block
  case line
  case circle
}

/// Skeleton parameter defaults.
enum MTSkeletonDefaults {
  static let shape = MTSkeletonShape.block
  static let isAnimated = true
}

// TextField, from packages/design-system/components/text-field.yaml.

/// The control's height and corner radius, from the size.field scale. Small fits filter rows and
/// compact panels, and large stands alone.
enum MTTextFieldSize: String, CaseIterable, Sendable {
  case small
  case medium
  case large
}

/// TextField parameter defaults.
enum MTTextFieldDefaults {
  static let size = MTTextFieldSize.medium
  static let isRequired = false
  static let hidesLabel = false
}

// Toast, from packages/design-system/components/toast.yaml.

/// What happened. Success confirms a change, info reports a neutral outcome, and error reports a
/// failure, in the warm color and for longer.
enum MTToastTone: String, CaseIterable, Sendable {
  case success
  case info
  case error
}

/// Toast parameter defaults.
enum MTToastDefaults {
  static let tone = MTToastTone.info
}

// UploadProgress, from packages/design-system/components/upload-progress.yaml.

/// Where the progress shows. Inline sits in a form beside its label and count; overlay covers a
/// photo tile with a scrim and shows only the ring.
enum MTUploadProgressVariant: String, CaseIterable, Sendable {
  case inline
  case overlay
}

/// UploadProgress parameter defaults.
enum MTUploadProgressDefaults {
  static let variant = MTUploadProgressVariant.inline
}

/// A gallery specimen from a component spec. The Web gallery marks it with data-specimen and
/// the iOS gallery with `accessibilityIdentifier`, so UI tests find every specimen on both.
enum MTComponentSpecimen: String, CaseIterable, Sendable {
  case badgeTones = "badge-tones"
  case badgeSizes = "badge-sizes"
  case badgeTags = "badge-tags"
  case badgeTruncation = "badge-truncation"
  case badgePhotoOverlay = "badge-photo-overlay"
  case buttonVariants = "button-variants"
  case buttonDisabled = "button-disabled"
  case buttonLoading = "button-loading"
  case buttonSizes = "button-sizes"
  case buttonLink = "button-link"
  case captureComposerPage = "capture-composer-page"
  case captureComposerDialog = "capture-composer-dialog"
  case checkboxSizes = "checkbox-sizes"
  case checkboxStates = "checkbox-states"
  case dateFieldPrecision = "date-field-precision"
  case dateFieldWithTime = "date-field-with-time"
  case dateFieldSizes = "date-field-sizes"
  case dateFieldStates = "date-field-states"
  case dialogConfirmation = "dialog-confirmation"
  case dialogForm = "dialog-form"
  case dialogShortChoice = "dialog-short-choice"
  case dialogLongContent = "dialog-long-content"
  case emptyStateWithAction = "empty-state-with-action"
  case emptyStateInformational = "empty-state-informational"
  case emptyStateButton = "empty-state-button"
  case focusedRecordHome = "focused-record-home"
  case iconButtonVariants = "icon-button-variants"
  case iconButtonSizes = "icon-button-sizes"
  case iconButtonStates = "icon-button-states"
  case iconSet = "icon-set"
  case iconSizes = "icon-sizes"
  case iconColor = "icon-color"
  case imageStates = "image-states"
  case imageFit = "image-fit"
  case pageFrameWidths = "page-frame-widths"
  case pageHeaderFull = "page-header-full"
  case pageHeaderTitleOnly = "page-header-title-only"
  case photoViewerPaged = "photo-viewer-paged"
  case recordCardPhoto = "record-card-photo"
  case recordCardMark = "record-card-mark"
  case richTextContent = "rich-text-content"
  case richTextForm = "rich-text-form"
  case richTextEmbedded = "rich-text-embedded"
  case searchFieldSizes = "search-field-sizes"
  case searchFieldHiddenLabel = "search-field-hidden-label"
  case searchFieldDisabled = "search-field-disabled"
  case sectionHeaderSection = "section-header-section"
  case sectionHeaderList = "section-header-list"
  case sectionHeaderLong = "section-header-long"
  case selectFieldSizes = "select-field-sizes"
  case selectFieldGroups = "select-field-groups"
  case selectFieldDisabled = "select-field-disabled"
  case separatedListDefault = "separated-list-default"
  case separatedListWord = "separated-list-word"
  case separatedListEndAligned = "separated-list-end-aligned"
  case skeletonShapes = "skeleton-shapes"
  case skeletonStill = "skeleton-still"
  case skeletonComposed = "skeleton-composed"
  case textFieldSizes = "text-field-sizes"
  case textFieldStates = "text-field-states"
  case timeZoneFieldOffsets = "time-zone-field-offsets"
  case toastTones = "toast-tones"
  case toastLongMessage = "toast-long-message"
  case uploadProgressInline = "upload-progress-inline"
  case uploadProgressOverlay = "upload-progress-overlay"

  /// The component the specimen shows.
  var component: String {
    switch self {
    case .badgeTones: "Badge"
    case .badgeSizes: "Badge"
    case .badgeTags: "Badge"
    case .badgeTruncation: "Badge"
    case .badgePhotoOverlay: "Badge"
    case .buttonVariants: "Button"
    case .buttonDisabled: "Button"
    case .buttonLoading: "Button"
    case .buttonSizes: "Button"
    case .buttonLink: "Button"
    case .captureComposerPage: "CaptureComposer"
    case .captureComposerDialog: "CaptureComposer"
    case .checkboxSizes: "Checkbox"
    case .checkboxStates: "Checkbox"
    case .dateFieldPrecision: "DateField"
    case .dateFieldWithTime: "DateField"
    case .dateFieldSizes: "DateField"
    case .dateFieldStates: "DateField"
    case .dialogConfirmation: "Dialog"
    case .dialogForm: "Dialog"
    case .dialogShortChoice: "Dialog"
    case .dialogLongContent: "Dialog"
    case .emptyStateWithAction: "EmptyState"
    case .emptyStateInformational: "EmptyState"
    case .emptyStateButton: "EmptyState"
    case .focusedRecordHome: "FocusedRecord"
    case .iconButtonVariants: "IconButton"
    case .iconButtonSizes: "IconButton"
    case .iconButtonStates: "IconButton"
    case .iconSet: "Icon"
    case .iconSizes: "Icon"
    case .iconColor: "Icon"
    case .imageStates: "Image"
    case .imageFit: "Image"
    case .pageFrameWidths: "PageFrame"
    case .pageHeaderFull: "PageHeader"
    case .pageHeaderTitleOnly: "PageHeader"
    case .photoViewerPaged: "PhotoViewer"
    case .recordCardPhoto: "RecordCard"
    case .recordCardMark: "RecordCard"
    case .richTextContent: "RichText"
    case .richTextForm: "RichText"
    case .richTextEmbedded: "RichText"
    case .searchFieldSizes: "SearchField"
    case .searchFieldHiddenLabel: "SearchField"
    case .searchFieldDisabled: "SearchField"
    case .sectionHeaderSection: "SectionHeader"
    case .sectionHeaderList: "SectionHeader"
    case .sectionHeaderLong: "SectionHeader"
    case .selectFieldSizes: "SelectField"
    case .selectFieldGroups: "SelectField"
    case .selectFieldDisabled: "SelectField"
    case .separatedListDefault: "SeparatedList"
    case .separatedListWord: "SeparatedList"
    case .separatedListEndAligned: "SeparatedList"
    case .skeletonShapes: "Skeleton"
    case .skeletonStill: "Skeleton"
    case .skeletonComposed: "Skeleton"
    case .textFieldSizes: "TextField"
    case .textFieldStates: "TextField"
    case .timeZoneFieldOffsets: "TimeZoneField"
    case .toastTones: "Toast"
    case .toastLongMessage: "Toast"
    case .uploadProgressInline: "UploadProgress"
    case .uploadProgressOverlay: "UploadProgress"
    }
  }

  /// What the specimen shows, from its spec's description.
  var summary: String {
    switch self {
    case .badgeTones: "Every tone at the default small size."
    case .badgeSizes:
      "Every size in the default accent tone, beside the uppercase treatment at each size."
    case .badgeTags:
      "Tags written with a leading # in Latin and CJK scripts, at the medium size Dashboard uses."
    case .badgeTruncation:
      """
      A long label and a long tag stay on one line and truncate at the tail inside a narrow \
      container.
      """
    case .badgePhotoOverlay:
      "Uppercase micro glass and inverse tones over a photo, where record cards place them."
    case .buttonVariants: "Every variant at the default medium size."
    case .buttonDisabled: "Every variant disabled, faded to the disabled opacity."
    case .buttonLoading: "Every variant loading, with the spinner before the label."
    case .buttonSizes: "Every size in the secondary variant, each with a leading icon."
    case .buttonLink: "Navigation drawn as a button, with Web ButtonLink and an iOS NavigationLink."
    case .captureComposerPage:
      "The Dashboard composer as a raised card with its question, an empty note, and its actions."
    case .captureComposerDialog:
      "The Quick Capture body without a card or question, sharing the same draft."
    case .checkboxSizes:
      "Both sizes, unchecked and checked, with a description on each checked one."
    case .checkboxStates:
      "A controlled option, a long description that wraps, disabled, and disabled while checked."
    case .dateFieldPrecision:
      "Day, month, and year precision, each with a value from the same September."
    case .dateFieldWithTime: "A date with its time of day, which opens a separate time picker."
    case .dateFieldSizes: "Every size, from the small filter date to the large birth date."
    case .dateFieldStates:
      """
      Empty with its placeholder, required, and disabled, and on Web a picker-only field that \
      opens the calendar instead of taking typing.
      """
    case .dialogConfirmation:
      """
      A compact confirmation to remove a memory that says where it goes, with Cancel and a danger \
      action.
      """
    case .dialogForm:
      """
      A form dialog to edit a memory, with a title and a date field, and a save that keeps the \
      dialog busy for a moment.
      """
    case .dialogShortChoice: "A short choice of what to add, sized to its two options."
    case .dialogLongContent:
      "A wide dialog whose long story scrolls while its footer stays in reach."
    case .emptyStateWithAction:
      "An icon, a title, a description, and one action, as an empty Library shows."
    case .emptyStateInformational:
      "A title and a description without an icon or action, for a section that fills in on its own."
    case .emptyStateButton: "The whole state as one button that starts the missing record."
    case .focusedRecordHome:
      "A record page with its photos, facts, Story, and tags, and Edit beside the title."
    case .iconButtonVariants:
      "Every variant at the default medium size, with add, edit, more, and remove icons."
    case .iconButtonSizes:
      "Every size in the ghost variant, with the close icon a dialog header uses."
    case .iconButtonStates:
      "A ghost action at rest, disabled, and loading, where the spinner replaces the icon."
    case .iconSet:
      """
      Every icon the platform draws, at 20, each with its name and a mark on those that draw on \
      only one platform.
      """
    case .iconSizes: "The calendar icon at 14, 16, 18, and 24 on the size.icon scale."
    case .iconColor:
      "Icons take the color of their text, shown beside ink, muted, accent, and warm labels."
    case .imageStates:
      "A loaded photo, one still loading, and one that failed to load, side by side."
    case .imageFit: "The same tall photo cropped to fill a wide frame and shown whole inside it."
    case .pageFrameWidths: "Every width variant with its maximum width and the pages it suits."
    case .pageHeaderFull: "An eyebrow, a title, a description, and two actions beside the copy."
    case .pageHeaderTitleOnly: "A title alone, as a focused page with nothing else to say opens."
    case .photoViewerPaged:
      "Three saved photos that open on the second, with Previous, the position, and Next."
    case .recordCardPhoto:
      """
      A card with a cover photo and a photo count, then its date, name, a Location line, story, \
      and tags.
      """
    case .recordCardMark: "A card without a photo or map, showing its mark over a soft accent wash."
    case .richTextContent: "A saved note with a paragraph, emphasis, a link, a quote, and a list."
    case .richTextForm: "The bordered editor with a placeholder, as in the Entry editor."
    case .richTextEmbedded: "The editor without a field, as inside the capture composer."
    case .searchFieldSizes: "Every size, from the compact filter search to the large page search."
    case .searchFieldHiddenLabel:
      """
      A large search whose label is hidden because the page title names it, with trailing content \
      after the query, a shortcut hint on Web and a count on iOS.
      """
    case .searchFieldDisabled: "A disabled search, faded to the field opacity."
    case .sectionHeaderSection:
      """
      Section headers alone, with a count beside the title, with a description, and with a \
      trailing action.
      """
    case .sectionHeaderList:
      "List headers with a count beside the title and at the far edge, and with a trailing action."
    case .sectionHeaderLong: "A long section title and its trailing action in a narrow column."
    case .selectFieldSizes: "Every size, from a compact sort order to a standalone default view."
    case .selectFieldGroups:
      """
      A required choice whose options sit in titled groups, after an All records option outside \
      any group.
      """
    case .selectFieldDisabled: "A disabled small select, faded to the field opacity."
    case .separatedListDefault:
      """
      Facts and links with the default spacing, wrapping in narrower frames without a separator at \
      a line's edge.
      """
    case .separatedListWord: "Plain facts with word spacing, reading like a sentence."
    case .separatedListEndAligned: "Attribution links whose lines share the trailing edge."
    case .skeletonShapes:
      "Every shape at its default size, with a fill skeleton inside a photo-sized frame."
    case .skeletonStill:
      "A block and two lines with the shimmer turned off, as reduced motion draws them."
    case .skeletonComposed:
      "A circle beside two lines and a block below them, the way a loading record row is built."
    case .textFieldSizes: "Every size, holding a nickname, a preferred name, and a full name."
    case .textFieldStates:
      "Empty with a placeholder, required, disabled, and invalid with its message."
    case .timeZoneFieldOffsets:
      """
      The same zone on a winter and a summer reference date, each showing the offset that applied \
      that day.
      """
    case .toastTones: "Success, info, and error, each with its icon and stripe."
    case .toastLongMessage: "An error long enough to wrap onto a second line."
    case .uploadProgressInline:
      "Three of five photos uploaded, with the label and count beside the ring."
    case .uploadProgressOverlay:
      "The ring alone over a photo tile, as a new photo's tile shows while it uploads."
    }
  }

  var accessibilityIdentifier: String { "specimen-\(rawValue)" }
}
