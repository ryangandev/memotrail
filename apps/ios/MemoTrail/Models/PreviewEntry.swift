import Foundation

struct PreviewEntry: Identifiable {
  let id = UUID()
  let date: String
  let title: String
  let excerpt: String
  let tags: [String]
  let isAISuggested: Bool

  static let samples = [
    PreviewEntry(
      date: "Today, 9:42 AM",
      title: "Why do people need to keep learning?",
      excerpt: "Maybe learning is less about collecting answers and more about keeping our model of the world alive.",
      tags: ["reflection", "learning"],
      isAISuggested: true
    ),
    PreviewEntry(
      date: "Yesterday, 8:16 PM",
      title: "How clear aligners move teeth",
      excerpt: "Small, controlled forces trigger bone remodeling around each tooth. The bone changes rather than the tooth bending.",
      tags: ["learned", "health"],
      isAISuggested: true
    ),
    PreviewEntry(
      date: "Jul 3, 2026",
      title: "First time skiing",
      excerpt: "Fell more times than I can count, then finally linked three turns together before the last run.",
      tags: ["first time", "travel"],
      isAISuggested: false
    ),
  ]
}
