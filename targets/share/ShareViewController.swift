import KinwallKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Kinwall" in the share sheet: sends what's shared to the family's Kinwall (POST api/share, KinwallKit
/// Share.swift) right here in the sheet. A link or an Apple Maps place goes as it is (Kinwall reads
/// the page). A photo or some text is read on the device (native/ios/ShareReader.swift): an ISBN
/// barcode goes as a book straight away; with Apple Intelligence the sheet shows the model's guess
/// ("Looks like a menu: …") with Add to Kinwall and "Not a menu?"; otherwise, or when the model
/// isn't sure, it asks "What is this?". An event shows what Kinwall read, to fix and add to a calendar
/// here (EventReview.swift) or open in the app. A book to pick opens in the app; anything saved shows
/// Kinwall's line, and the sheet closes itself after about 3 s unless it's touched.
/// A shared contact (a vCard) is reviewed and imported the same way (ContactImport.swift).
/// It signs in with what the app keeps in the shared Keychain group (KinwallKit AppSignIn).
final class ShareViewController: UIViewController {
  private let label = UILabel()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private lazy var done = UIButton(configuration: .filled(), primaryAction: UIAction(title: "Done") { [weak self] _ in
    self?.extensionContext?.completeRequest(returningItems: nil)
  })
  private var savedResult: Share.Result?
  private var touched = false
  private var review: UIViewController?
  private enum Choice { case add, kind(Share.Kind) }
  private var waiting: CheckedContinuation<Choice, Never>?
  private func choose(_ c: Choice) { waiting?.resume(returning: c); waiting = nil }
  private lazy var add = UIButton(configuration: .filled(), primaryAction: UIAction(title: "Add to Kinwall") { [weak self] _ in self?.choose(.add) })
  private lazy var notThat = UIButton(configuration: .plain(), primaryAction: UIAction { [weak self] _ in self?.showChoices() })
  private lazy var choices: UIStackView = {
    let buttons = [("Restaurant", Share.Kind.restaurant, "fork.knife"), ("Book", .book, "book"), ("Event", .event, "calendar")].map { title, kind, icon in
      var config = UIButton.Configuration.plain()
      config.title = title
      config.image = UIImage(systemName: icon)
      config.imagePadding = 8
      let b = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.choose(.kind(kind)) })
      b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
      return b
    }
    let stack = UIStackView(arrangedSubviews: buttons)
    stack.axis = .vertical
    stack.spacing = 4
    return stack
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    label.text = "Opening in Kinwall…" // what was shared isn't known yet
    label.font = .preferredFont(forTextStyle: .headline)
    label.textAlignment = .center
    label.numberOfLines = 0
    for b in [add, done, notThat] { b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true }
    for v in [add, notThat, choices, done] { v.isHidden = true }
    spinner.startAnimating()
    // Any touch keeps a saved result's sheet open (it closes itself otherwise).
    let touch = UITapGestureRecognizer(target: self, action: #selector(touchedSheet))
    touch.cancelsTouchesInView = false
    view.addGestureRecognizer(touch)
    let stack = UIStackView(arrangedSubviews: [spinner, label, add, notThat, choices, done])
    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { @MainActor in
      let shared = await Shared.read(extensionContext)
      // Maps shares a place as its link and a location vCard, which isn't a contact.
      if let place = shared.urls.first(where: Share.isMapsPlace) {
        return await send(.init(url: place.absoluteString, name: shared.vcard.flatMap(Share.vCardName)), reading: "Adding the place…")
      }
      if let vcard = shared.vcard { return await importContacts(vcard) }
      if let link = shared.urls.first ?? shared.texts.lazy.compactMap(Share.onlyLink).first {
        return await send(.init(url: link.absoluteString), reading: "Reading the page…")
      }
      if let text = shared.texts.first(where: { $0.nilIfBlank != nil }) {
        busy("Reading it…")
        return await sendWords(text)
      }
      if let image = shared.image {
        busy("Reading the photo…")
        guard let read = ShareReader.read(image) else { return finish("Kinwall couldn't open this photo.") }
        if let isbn = read.isbn { return await send(.init(kind: .book, text: isbn), reading: "Adding the book…") }
        guard let text = read.text else { return finish("Kinwall couldn't find any words in this photo.") }
        return await sendWords(text)
      }
      finish("Share a link, a photo, some text or a contact to add it to Kinwall.")
    }
  }

  /// A photo's words or shared text: the model's guess to confirm, else "What is this?". An event goes
  /// to its fields (checkEvent) with the words as read under the model's lines.
  private func sendWords(_ raw: String) async {
    var kind: Share.Kind
    var text: String? = nil
    var guessed = false
    let guess = await ShareReader.guess(raw)
    if let guess, guess.kind == .event {
      kind = .event; text = guess.text; guessed = true
    } else if let guess {
      label.text = Share.guessLine(guess.kind, text: guess.text)
      notThat.configuration?.title = Share.notLabel(guess.kind)
      spinner.stopAnimating()
      for v in [add, notThat, done] { v.isHidden = false }
      cancelling(true)
      switch await wait() {
      case .add: kind = guess.kind; text = guess.text
      case .kind(let k): kind = k; if k == guess.kind { text = guess.text }
      }
    } else {
      showChoices()
      guard case .kind(let k) = await wait() else { return }
      kind = k
    }
    for v in [add, notThat, choices, done] { v.isHidden = true }
    cancelling(false)
    if text == nil { busy("Reading it…"); text = await ShareReader.tidied(raw, kind: kind) ?? raw }
    if kind == .event { return await checkEvent(Share.eventText(text, raw: raw), raw: raw, guessed: guessed) }
    await send(Share.request(kind: kind, text: text), reading: "Adding to Kinwall…")
  }

  /// An event: what Kinwall read, with the calendars to add it to, to fix and add here (EventReview),
  /// or open in the app. A Kinwall too old to say what it read opens the app's event sheet, as before.
  private func checkEvent(_ text: String, raw: String, guessed: Bool) async {
    busy("Reading the event…")
    async let calendars = Share.calendars()
    let outcome = await Share.send(.init(kind: .event, text: text))
    guard case .done(let r) = outcome, let draft = r.event else {
      if case .failed(let message) = outcome { return finish(message) }
      if case .done(let r) = outcome { review(r) }
      return
    }
    // No calendar this phone can add to (none writable, or they couldn't be read): EventReview would
    // have no Add button, so leave it for the app to check instead.
    guard let addable = await calendars, !addable.isEmpty else { return review(r) }
    spinner.stopAnimating()
    spinner.isHidden = true
    label.isHidden = true
    let context = extensionContext
    let host = embed(EventReview(draft: draft, guessed: guessed, calendars: addable,
      add: { [weak self] event, calendarId in
        switch await Share.send(.init(kind: .event, event: event, save: true, calendarId: calendarId)) {
        case .failed(let message): return message
        case .done(let saved): self?.closeReview(); self?.saved(saved); return nil
        }
      },
      notEvent: { [weak self] in
        self?.closeReview()
        Task { @MainActor in await self?.pickAgain(raw) }
      },
      cancel: { context?.completeRequest(returningItems: nil) }))
    review = host
  }

  /// "Not an event?": "What is this?", then on as if picked first.
  private func pickAgain(_ raw: String) async {
    showChoices()
    guard case .kind(let kind) = await wait() else { return }
    for v in [choices, done] { v.isHidden = true }
    cancelling(false)
    busy("Reading it…")
    let text = await ShareReader.tidied(raw, kind: kind)
    if kind == .event { return await checkEvent(Share.eventText(text, raw: raw), raw: raw, guessed: false) }
    await send(Share.request(kind: kind, text: text ?? raw), reading: "Adding to Kinwall…")
  }

  private func closeReview() {
    review?.willMove(toParent: nil)
    review?.view.removeFromSuperview()
    review?.removeFromParent()
    review = nil
    label.isHidden = false
  }

  /// Cancel is a plain button under the choices; Done the filled one under a result.
  private func cancelling(_ on: Bool) {
    var config: UIButton.Configuration = on ? .plain() : .filled()
    config.title = on ? "Cancel" : "Done"
    done.configuration = config
  }

  private func wait() async -> Choice { await withCheckedContinuation { waiting = $0 } }

  /// "What is this?" with Restaurant, Book and Event; Cancel closes the sheet.
  private func showChoices() {
    spinner.stopAnimating()
    label.text = "What is this?"
    for v in [add, notThat] { v.isHidden = true }
    choices.isHidden = false
    cancelling(true)
    done.isHidden = false
  }

  /// What's shared: web links, text, the first photo, and any vCards' text.
  struct Shared {
    var urls: [URL] = [], texts: [String] = [], image: Data?, vcard: String?

    static func read(_ context: NSExtensionContext?) async -> Shared {
      let items = context?.inputItems as? [NSExtensionItem] ?? []
      let providers = items.flatMap { $0.attachments ?? [] }
      var s = Shared(vcard: await ContactImport.sharedVCard(context))
      for p in providers {
        if p.hasItemConformingToTypeIdentifier(UTType.url.identifier), !p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, url.scheme == "https" || url.scheme == "http" { s.urls.append(url) }
        else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), !p.hasItemConformingToTypeIdentifier(UTType.vCard.identifier),
                let text = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String { s.texts.append(text) }
        else if s.image == nil, p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
          s.image = await withCheckedContinuation { done in _ = p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in done.resume(returning: data) } }
        }
      }
      // A page's title that comes with its link isn't something to add on its own.
      if s.urls.isEmpty, s.image == nil { s.texts += items.compactMap { $0.attributedContentText?.string } }
      return s
    }
  }

  private func busy(_ text: String) {
    label.text = text
    spinner.isHidden = false
    spinner.startAnimating()
  }

  private func finish(_ text: String) {
    spinner.stopAnimating()
    spinner.isHidden = true
    label.isHidden = false // the event form hid it
    label.text = text
    done.isHidden = false
  }

  private func send(_ request: Share.Request?, reading: String) async {
    guard let request else { return finish("Nothing to add.") }
    busy(reading)
    switch await Share.send(request) {
    case .failed(let message): finish(message)
    case .done(let r) where r.needsReview: review(r)
    case .done(let r): saved(r)
    }
  }

  /// Saved: Kinwall's line; the sheet closes itself after about 3 s unless it's touched.
  private func saved(_ r: Share.Result) {
    finish(r.summary)
    savedResult = r
    touched = false
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(3))
      if !touched, savedResult == r { extensionContext?.completeRequest(returningItems: nil) }
    }
  }

  @objc private func touchedSheet() { touched = true }

  /// Opens a result in the app (src/links.ts routeFor, to=shared): something to check (an event, a book
  /// to pick). A share sheet usually isn't allowed to open its app; then the
  /// link waits in the shared Keychain for the app's next start (PendingLink), and the sheet says to open Kinwall.
  private func review(_ r: Share.Result) {
    guard let link = Share.appLink(r.link) else { return finish(r.summary) }
    extensionContext?.open(link) { [weak self] opened in
      Task { @MainActor in
        if opened { self?.extensionContext?.completeRequest(returningItems: nil) } else {
          AppSignIn.leaveForApp(link)
          self?.finish("\(r.summary)\nOpen Kinwall to check it.")
        }
      }
    }
  }

  private func importContacts(_ vcard: String) async {
    label.text = "Reading contact…"
    let result = await ContactImport.preview(vcard)
    spinner.stopAnimating()
    spinner.isHidden = true
    switch result {
    case .failure(let failure):
      label.text = failure.message
      done.isHidden = false
    case .success(let rows):
      label.isHidden = true
      let context = extensionContext
      embed(ContactReview(rows: rows) { context?.completeRequest(returningItems: nil) })
    }
  }

  @discardableResult
  private func embed(_ root: some View) -> UIViewController {
    let host = UIHostingController(rootView: root)
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    host.didMove(toParent: self)
    return host
  }

  // MARK: Signed-in requests (ContactImport.swift)

  typealias SignInNeeded = AppSignIn.SignInNeeded
  struct Failure: Decodable { let error: String? }

  /// POSTs JSON to the family's server, signed in: the reply and its status, or nil when signed out.
  static func post(_ path: String, _ body: Any, timeout: TimeInterval) async throws -> (Data, Int)? {
    try await AppSignIn.post(path, json: try JSONSerialization.data(withJSONObject: body), timeout: timeout)
  }
}
