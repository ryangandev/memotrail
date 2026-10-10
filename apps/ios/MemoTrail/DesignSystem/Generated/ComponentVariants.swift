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
  case iconButtonVariants = "icon-button-variants"
  case iconButtonSizes = "icon-button-sizes"
  case iconButtonStates = "icon-button-states"
  case iconSet = "icon-set"
  case iconSizes = "icon-sizes"
  case iconColor = "icon-color"
  case searchFieldSizes = "search-field-sizes"
  case searchFieldHiddenLabel = "search-field-hidden-label"
  case searchFieldDisabled = "search-field-disabled"
  case selectFieldSizes = "select-field-sizes"
  case selectFieldGroups = "select-field-groups"
  case selectFieldDisabled = "select-field-disabled"
  case textFieldSizes = "text-field-sizes"
  case textFieldStates = "text-field-states"
  case timeZoneFieldOffsets = "time-zone-field-offsets"
  case toastTones = "toast-tones"
  case toastLongMessage = "toast-long-message"

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
    case .iconButtonVariants: "IconButton"
    case .iconButtonSizes: "IconButton"
    case .iconButtonStates: "IconButton"
    case .iconSet: "Icon"
    case .iconSizes: "Icon"
    case .iconColor: "Icon"
    case .searchFieldSizes: "SearchField"
    case .searchFieldHiddenLabel: "SearchField"
    case .searchFieldDisabled: "SearchField"
    case .selectFieldSizes: "SelectField"
    case .selectFieldGroups: "SelectField"
    case .selectFieldDisabled: "SelectField"
    case .textFieldSizes: "TextField"
    case .textFieldStates: "TextField"
    case .timeZoneFieldOffsets: "TimeZoneField"
    case .toastTones: "Toast"
    case .toastLongMessage: "Toast"
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
    case .searchFieldSizes: "Every size, from the compact filter search to the large page search."
    case .searchFieldHiddenLabel:
      """
      A large search whose label is hidden because the page title names it, with trailing content \
      after the query, a shortcut hint on Web and a count on iOS.
      """
    case .searchFieldDisabled: "A disabled search, faded to the field opacity."
    case .selectFieldSizes: "Every size, from a compact sort order to a standalone default view."
    case .selectFieldGroups:
      """
      A required choice whose options sit in titled groups, after an All records option outside \
      any group.
      """
    case .selectFieldDisabled: "A disabled small select, faded to the field opacity."
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
    }
  }

  var accessibilityIdentifier: String { "specimen-\(rawValue)" }
}
