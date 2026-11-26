import KinwallKit
import SwiftUI

/// A recipe, restaurant or book the share sheet read (ShareViewController.showPreview), before it's
/// saved: the photo or cover, the name, Kinwall's short lines (servings and counts, cuisine and phone,
/// author and shelf) and, when it's already in Kinwall, what saving does to it. Add to Kinwall saves it
/// (the same share without preview); the ✕ closes the sheet. Laid out like EventReview.
struct SharePreview: View {
  let kind: Share.Kind
  let preview: Share.Preview
  let guessed: Bool
  /// Saves it: an error line to show, or nil once it's saved (the sheet moves on).
  let add: (Share.RecipeKind?) async -> String?
  let notThat: () -> Void
  let cancel: () -> Void

  @State private var working = false
  @State private var error: String?
  @State private var recipeKind: Share.RecipeKind?

  var body: some View {
    NavigationStack {
      List {
        Section {
          if let s = preview.imageUrl, let url = URL(string: s) {
            AsyncImage(url: url) { image in
              if kind == .book { image.resizable().scaledToFit() } else { image.resizable().scaledToFill() }
            } placeholder: { Color.secondary.opacity(0.15) }
              .frame(height: kind == .book ? 220 : 180).frame(maxWidth: .infinity).clipped()
              .listRowInsets(EdgeInsets())
              .accessibilityHidden(true)
          }
          VStack(alignment: .leading, spacing: 4) {
            Text(preview.title).font(.title3.bold())
            ForEach(preview.lines, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
          }
          .padding(.vertical, 4)
          if let already = preview.already {
            Label(already, systemImage: "info.circle").font(.subheadline)
          }
          if kind == .recipe, let detected = preview.recipe?.kind {
            Picker(selection: Binding(get: { recipeKind ?? detected }, set: { recipeKind = $0 })) {
              ForEach(Share.RecipeKind.allCases, id: \.self) { choice in
                Text(recipeLabel(choice)).tag(choice)
              }
            } label: { Text(NSLocalizedString("Type", comment: "Recipe type")) }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
            .accessibilityLabel(NSLocalizedString("Type", comment: "Recipe type"))
            .accessibilityValue(recipeLabel(recipeKind ?? detected))
          }
        }
        if let error { Section { Text(error).foregroundStyle(.red) } }
      }
      .disabled(working)
      .safeAreaInset(edge: .bottom) { buttons }
      // "Looks like a menu" when the sheet guessed, else "Check the restaurant".
      .navigationTitle(guessed ? Share.guessLine(kind, text: "") : Share.checkTitle(kind))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: cancel) { Image(systemName: "xmark") }.accessibilityLabel("Cancel").disabled(working)
        }
      }
    }
  }

  private var buttons: some View {
    VStack(spacing: 4) {
      Button {
        Task { working = true; error = await add(recipeKind); working = false }
      } label: {
        Group { if working { ProgressView() } else { Text("Add to Kinwall").bold() } }.frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.borderedProminent)
      .tint(.kinwallAction)
      .foregroundStyle(.white)
      .disabled(working)
      if guessed { Button(action: notThat) { Text(Share.notLabel(kind)).frame(maxWidth: .infinity, minHeight: 44) }.disabled(working) }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.bar)
  }

  private func recipeLabel(_ kind: Share.RecipeKind) -> String {
    switch kind {
    case .meal: NSLocalizedString("Main dish", comment: "Recipe type")
    case .side: NSLocalizedString("Side", comment: "Recipe type")
    case .dessert: NSLocalizedString("Dessert", comment: "Recipe type")
    case .basic: NSLocalizedString("Basic", comment: "Recipe type")
    }
  }
}

extension Color {
  /// The share sheet's main button (Add to Kinwall, Add to calendar): a solid blue with white text that
  /// reads as tappable in light and dark (the system tint drew it pale in dark mode, like a disabled
  /// button). About 4.9:1 against white.
  static let kinwallAction = Color(red: 0.16, green: 0.45, blue: 0.85)
}
