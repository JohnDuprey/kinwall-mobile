import KinwallKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Kinwall" in the share sheet: sends what's shared to the family's Kinwall (POST api/share, KinwallKit
/// Share.swift) right here in the sheet. A link goes as it is (Kinwall reads the page). An Apple or
/// Google Maps place (a link, or text with one) asks "Restaurant or place?" first: a restaurant for the
/// binder, a place for Contacts, or a place to visit for Outings. A photo or some text is read on the device (native/ios/ShareReader.swift): an ISBN
/// barcode goes as a book straight away; with Apple Intelligence the model's guess goes on as that
/// kind, with "Not a menu?" to pick another; otherwise, or when the model isn't sure, it asks
/// "What is this?". Several photos (a menu over pages) are read one at a time and go as one text,
/// guessed a menu when the model can't tell. A recipe, restaurant or book shows what Kinwall would
/// save (SharePreview.swift, POST api/share with preview) with Add to Kinwall; an event shows what
/// Kinwall read, to fix and add to a calendar or save to Outings here (EventReview.swift). A book to pick opens in the
/// app; anything saved shows Kinwall's line, and the sheet closes itself after about 3 s unless it's touched.
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
  private var waiting: CheckedContinuation<Share.Kind, Never>?
  private func choose(_ k: Share.Kind) { waiting?.resume(returning: k); waiting = nil }
  /// A guess Kinwall couldn't use (no restaurant name in it): "Not a menu?" picks again from these words.
  private var guessedPages: [String]?
  /// A menu photo's QR code lines ("Order online: …"), sent over a restaurant's words.
  private var links: [String] = []
  private lazy var notThat = UIButton(configuration: .plain(), primaryAction: UIAction { [weak self] _ in
    guard let self, let pages = self.guessedPages else { return }
    Task { @MainActor in await self.pickAgain(pages) }
  })
  private lazy var choices = choiceStack([("Restaurant", .restaurant, "fork.knife"), ("Book", .book, "book"), ("Event", .event, "calendar")])
  /// "Restaurant or place?" for a Maps place: the binder, Contacts, or Outings' places to visit.
  private lazy var placeChoices = choiceStack([("Restaurant", .restaurant, "fork.knife"), ("Place", .place, "mappin.and.ellipse"), ("Place to visit", .outing, "figure.walk")])
  private func choiceStack(_ items: [(String, Share.Kind, String)]) -> UIStackView {
    let buttons = items.map { title, kind, icon in
      var config = UIButton.Configuration.plain()
      config.title = title
      config.image = UIImage(systemName: icon)
      config.imagePadding = 8
      let b = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.choose(kind) })
      b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
      return b
    }
    let stack = UIStackView(arrangedSubviews: buttons)
    stack.axis = .vertical
    stack.spacing = 4
    return stack
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    view.tintColor = UIColor(Color.kinwallAction) // filled buttons (Done) match Add to Kinwall
    label.text = "Opening in Kinwall…" // what was shared isn't known yet
    label.font = .preferredFont(forTextStyle: .headline)
    label.textAlignment = .center
    label.numberOfLines = 0
    for b in [done, notThat] { b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true }
    for v in [notThat, choices, placeChoices, done] { v.isHidden = true }
    spinner.startAnimating()
    // Any touch keeps a saved result's sheet open (it closes itself otherwise).
    let touch = UITapGestureRecognizer(target: self, action: #selector(touchedSheet))
    touch.cancelsTouchesInView = false
    view.addGestureRecognizer(touch)
    let stack = UIStackView(arrangedSubviews: [spinner, label, notThat, choices, placeChoices, done])
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
      // Apple Maps shares a place as its link and a location vCard (name, phone, address, website),
      // which isn't a contact; Google Maps as text with its name and address first and the link last,
      // or the link alone.
      let inText = shared.texts.lazy.compactMap(Share.mapsPlace(in:)).first
      if let place = shared.urls.first(where: Share.isMapsPlace) ?? inText?.url {
        let fromText: Share.PlaceCard? = shared.texts.lazy.map { Share.placeCard(text: $0) }.first { $0.name != nil }
        let card: Share.PlaceCard = shared.vcard.map { Share.placeCard(vCard: $0) } ?? inText?.card ?? fromText ?? Share.PlaceCard()
        return await sendPlace(place, card: card)
      }
      if let vcard = shared.vcard { return await importContacts(vcard) }
      if let link = shared.urls.first ?? shared.texts.lazy.compactMap(Share.onlyLink).first {
        return await send(.init(url: link.absoluteString), reading: "Reading the page…")
      }
      if let text = shared.texts.first(where: { $0.nilIfBlank != nil }) {
        busy("Reading it…")
        return await sendWords([text])
      }
      if !shared.images.isEmpty {
        let photos = shared.images, one = photos.count == 1
        let read = await ShareReader.read(count: photos.count, load: { await Shared.data(photos[$0]) }) { [weak self] n in
          self?.busy(one ? "Reading the photo…" : "Reading photo \(n + 1) of \(photos.count)…")
        }
        guard let read else { return finish(one ? "Kinwall couldn't open this photo." : "Kinwall couldn't open these photos.") }
        links = read.links
        if let isbn = read.isbn { return await send(.init(kind: .book, text: isbn), reading: "Looking up the book…") }
        guard !read.pages.isEmpty else { return finish(one ? "Kinwall couldn't find any words in this photo." : "Kinwall couldn't find any words in these photos.") }
        return await sendWords(read.pages)
      }
      finish("Share a link, a photo, some text or a contact to add it to Kinwall.")
    }
  }

  /// Photos' words (each photo a page) or shared text: the model's guess goes on as that kind
  /// (its card or the event's fields say "Looks like…", with "Not a menu?"), else "What is this?".
  /// Several photos are most likely a menu, so without the model's guess the sheet guesses that. An
  /// event goes to its fields (checkEvent) with the words as read under the model's lines.
  private func sendWords(_ pages: [String]) async {
    let raw = Share.joinPages(pages)
    let modelGuess = await ShareReader.guess(pages)
    let guess: (kind: Share.Kind, text: String?)? = modelGuess.map { ($0.kind, $0.text) } ?? (pages.count > 1 ? (.restaurant, nil) : nil)
    let kind: Share.Kind
    var text = guess?.text
    if let guess { kind = guess.kind } else {
      showChoices()
      kind = await wait()
    }
    for v in [notThat, choices, done] { v.isHidden = true }
    cancelling(false)
    if text == nil { busy("Reading it…"); text = await ShareReader.tidied(pages, kind: kind) ?? raw }
    if kind == .event { return await checkEvent(Share.eventText(text, raw: raw), pages: pages, guessed: guess != nil) }
    await send(request(kind, text), reading: "Reading it…", guessed: guess != nil ? pages : nil)
  }

  /// An event: what Kinwall read, with the calendars to add it to, to fix and add here (EventReview),
  /// or open in the app. A Kinwall too old to say what it read opens the app's event sheet, as before.
  private func checkEvent(_ text: String, pages: [String], guessed: Bool) async {
    busy("Reading the event…")
    async let calendars = Share.calendars()
    async let minutes = Share.eventMinutes()
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
    let host = embed(EventReview(draft: draft, guessed: guessed, calendars: addable, minutes: await minutes,
      add: { [weak self] event, calendarId in
        switch await Share.send(.init(kind: .event, event: event, save: true, calendarId: calendarId)) {
        case .failed(let message): return message
        case .done(let saved): self?.closeReview(); self?.saved(saved); return nil
        }
      },
      saveToOutings: { [weak self] event in
        // The words go too: Kinwall reads the cost, ticket dates and ages from them.
        switch await Share.send(.outing(event, text: text)) {
        case .failed(let message): return message
        case .done(let saved): self?.closeReview(); self?.saved(saved); return nil
        }
      },
      notEvent: { [weak self] in
        self?.closeReview()
        Task { @MainActor in await self?.pickAgain(pages) }
      },
      cancel: { context?.completeRequest(returningItems: nil) }))
    review = host
  }

  /// "Not an event?": "What is this?", then on as if picked first.
  private func pickAgain(_ pages: [String]) async {
    let raw = Share.joinPages(pages)
    showChoices()
    let kind = await wait()
    for v in [choices, done] { v.isHidden = true }
    cancelling(false)
    busy("Reading it…")
    let text = await ShareReader.tidied(pages, kind: kind)
    if kind == .event { return await checkEvent(Share.eventText(text, raw: raw), pages: pages, guessed: false) }
    await send(request(kind, text ?? raw), reading: "Reading it…")
  }

  /// A Maps place: "Restaurant or place?", then its card (a restaurant for the binder, or a contact).
  private func sendPlace(_ url: URL, card: Share.PlaceCard) async {
    showChoices("Restaurant or place?", placeChoices)
    let kind = await wait()
    for v in [placeChoices, done] { v.isHidden = true }
    cancelling(false)
    await send(.init(kind: kind, place: url, card: card), reading: "Reading the place…")
  }

  /// What to send for words of a kind: a menu with its QR code lines first.
  private func request(_ kind: Share.Kind, _ text: String?) -> Share.Request? {
    Share.request(kind: kind, text: kind == .restaurant ? text.map { Share.withLinks(links, $0) } : text)
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

  private func wait() async -> Share.Kind { await withCheckedContinuation { waiting = $0 } }

  /// "What is this?" with Restaurant, Book and Event (or another question and its buttons); Cancel closes the sheet.
  private func showChoices(_ question: String = "What is this?", _ buttons: UIStackView? = nil) {
    spinner.stopAnimating()
    label.text = question
    notThat.isHidden = true
    (buttons ?? choices).isHidden = false
    cancelling(true)
    done.isHidden = false
  }

  /// What's shared: web links, text, the photos (up to `maxPhotos`, in the order shared; read later,
  /// one at a time, to stay under a share extension's memory limit), and any vCards' text.
  struct Shared {
    var urls: [URL] = [], texts: [String] = [], images: [NSItemProvider] = [], vcard: String?
    static let maxPhotos = 10

    static func data(_ p: NSItemProvider) async -> Data? {
      await withCheckedContinuation { done in _ = p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in done.resume(returning: data) } }
    }

    static func read(_ context: NSExtensionContext?) async -> Shared {
      let items = context?.inputItems as? [NSExtensionItem] ?? []
      let providers = items.flatMap { $0.attachments ?? [] }
      var s = Shared(vcard: await ContactImport.sharedVCard(context))
      for p in providers {
        if p.hasItemConformingToTypeIdentifier(UTType.url.identifier), !p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, url.scheme == "https" || url.scheme == "http" { s.urls.append(url) }
        else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), !p.hasItemConformingToTypeIdentifier(UTType.vCard.identifier),
                let text = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String { s.texts.append(text) }
        else if s.images.count < maxPhotos, p.hasItemConformingToTypeIdentifier(UTType.image.identifier) { s.images.append(p) }
      }
      // A page's title that comes with its link isn't something to add on its own.
      if s.urls.isEmpty, s.images.isEmpty { s.texts += items.compactMap { $0.attributedContentText?.string } }
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

  /// Asks Kinwall what it would save (preview), for SharePreview's Add to Kinwall; a Kinwall too old
  /// for previews saves it straight away. `guessed`: the words behind a guess, for "Not a menu?".
  private func send(_ request: Share.Request?, reading: String, guessed: [String]? = nil) async {
    guard var request else { return finish("Nothing to add.") }
    request.preview = true
    busy(reading)
    switch await Share.send(request) {
    case .failed(let message):
      finish(message)
      // A guess that didn't fit (a "menu" with no name): pick what it is instead.
      if let guessed, let kind = request.kind {
        guessedPages = guessed
        notThat.configuration?.title = Share.notLabel(kind)
        notThat.isHidden = false
      }
    case .done(let r) where r.preview != nil: showPreview(r, save: request.saving(r), guessed: guessed)
    case .done(let r) where r.needsReview: review(r)
    case .done(let r): saved(r)
    }
  }

  /// What Kinwall would save, with Add to Kinwall (SharePreview); "Not a menu?" when it was a guess.
  private func showPreview(_ r: Share.Result, save: Share.Request, guessed: [String]?) {
    spinner.stopAnimating()
    spinner.isHidden = true
    label.isHidden = true
    let context = extensionContext
    review = embed(SharePreview(kind: r.kind, preview: r.preview!, guessed: guessed != nil,
      add: { [weak self] in
        switch await Share.send(save) {
        case .failed(let message): return message
        case .done(let saved): self?.closeReview(); self?.saved(saved); return nil
        }
      },
      notThat: { [weak self] in
        self?.closeReview()
        if let guessed { Task { @MainActor in await self?.pickAgain(guessed) } }
      },
      cancel: { context?.completeRequest(returningItems: nil) }))
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
