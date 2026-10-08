import Foundation
import Testing
@testable import KinwallKit

@Suite struct ShareTests {
    let page = URL(string: "https://example.org/tacos")!

    @Test func aLinkGoesAloneSoKinwallReadsIt() {
        #expect(Share.request(kind: nil, url: page) == .init(kind: nil, url: page.absoluteString, text: nil, name: nil))
        // Shared text that's only a link is a link.
        #expect(Share.request(kind: nil, text: "  https://example.org/tacos\n")?.url == page.absoluteString)
        // A Maps place keeps its name; a kind picked in Shortcuts goes along.
        let maps = URL(string: "https://maps.apple.com/place?name=Joe%27s")!
        #expect(Share.request(kind: nil, url: maps, name: "Joe's") == .init(kind: nil, url: maps.absoluteString, text: nil, name: "Joe's"))
        #expect(Share.request(kind: .restaurant, url: page)?.kind == .restaurant)
    }

    @Test func textNeedsItsKind() {
        #expect(Share.request(kind: nil, text: "Spring fair Sat May 9") == nil)
        #expect(Share.request(kind: .event, text: " Spring fair\n") == .init(kind: .event, url: nil, text: "Spring fair", name: nil))
        #expect(Share.request(kind: .recipe, text: "Lemon chicken") == nil) // a recipe needs its page
        #expect(Share.request(kind: .book, text: "  ") == nil)
        // A link inside more text is text.
        #expect(Share.request(kind: .event, text: "Party! https://example.org/rsvp")?.text == "Party! https://example.org/rsvp")
    }

    @Test func links() {
        #expect(Share.onlyLink("https://example.org/a b") == nil)
        #expect(Share.onlyLink("mailto:x@example.org") == nil)
        #expect(Share.firstLink(in: "Try this: https://example.org/tacos!")?.host == "example.org")
        #expect(Share.isMapsPlace(URL(string: "https://maps.apple.com/?q=Pizza")!))
        #expect(!Share.isMapsPlace(page))
        for maps in ["https://maps.app.goo.gl/AbCd", "https://goo.gl/maps/AbCd", "https://www.google.com/maps/place/Maple+Park", "https://maps.google.co.uk/?q=Maple+Park", "https://google.com/maps?q=x"] {
            #expect(Share.isMapsPlace(URL(string: maps)!), "\(maps)")
        }
        for not in ["https://www.google.com/search?q=maps", "https://goo.gl/AbCd", "https://notgoogle.com/maps"] {
            #expect(!Share.isMapsPlace(URL(string: not)!), "\(not)")
        }
        let google = Share.mapsPlace(in: "Maple Park\n20 Lake Rd, Springfield\nhttps://maps.app.goo.gl/AbCd")
        #expect(google?.url.absoluteString == "https://maps.app.goo.gl/AbCd" && google?.card == .init(name: "Maple Park", address: "20 Lake Rd, Springfield"))
        #expect(Share.mapsPlace(in: "https://maps.app.goo.gl/AbCd")?.card == .init())
        #expect(Share.placeCard(text: "Maple Park\nOpen now\nhttps://maps.app.goo.gl/AbCd") == .init(name: "Maple Park"), "not an address")
        #expect(Share.mapsPlace(in: "Party! https://example.org/rsvp") == nil)
        #expect(Share.checkTitle(.place) == "Check the place")
        #expect(Share.vCardName("BEGIN:VCARD\r\nVERSION:3.0\r\nN:;Joe's Pizza;;;\r\nFN:Joe's Pizza\\, Main St\r\nEND:VCARD") == "Joe's Pizza, Main St")
        #expect(Share.vCardName("BEGIN:VCARD\nEND:VCARD") == nil)
    }

    @Test func appleMapsPlaceCard() {
        // A made-up place, as Apple Maps shares it with its link.
        let vcard = """
        BEGIN:VCARD\r
        VERSION:3.0\r
        PRODID:-//Apple Inc.//iPhone OS 26.0//EN\r
        N:;Corner Slice\\, Main St;;;\r
        FN:Corner Slice\\, Main St\r
        item1.ADR;type=WORK;type=pref:;;12 Elm St;Springfield;MA;01101;United States\r
        item1.X-ABADR:us\r
        TEL;type=MAIN;type=VOICE;type=pref:(555) 010-0100\r
        item2.URL;type=pref:https://cornerslice.example/\r
        item3.URL:https://maps.apple.com/?address=12%20Elm%20St&ll=42.1,-72.5&q=Corner%20Slice\r
        item3.X-ABLabel:map url\r
        END:VCARD
        """
        let card = Share.placeCard(vCard: vcard)
        #expect(card == .init(name: "Corner Slice, Main St", phone: "(555) 010-0100", address: "12 Elm St, Springfield, MA 01101", website: "https://cornerslice.example/"))
        // Only a map link: no website.
        #expect(Share.placeCard(vCard: "BEGIN:VCARD\nFN:Maple Park\nURL:https://maps.apple.com/?q=Maple%20Park\nEND:VCARD") == .init(name: "Maple Park"))
        let maps = URL(string: "https://maps.apple.com/place?name=Corner%20Slice")!
        let request = Share.Request(kind: .place, place: maps, card: card)
        #expect(request.kind == .place && request.name == card.name && request.phone == card.phone && request.address == card.address && request.website == card.website)
    }

    @Test func answers() {
        let ok = Data(#"{"kind":"event","summary":"Check the event: Spring fair, Sat May 9","link":"https://k/#/calendar?draft=event","review":true}"#.utf8)
        guard case .done(let r) = Share.outcome(status: 200, data: ok) else { Issue.record("not done"); return }
        #expect(r.summary == "Check the event: Spring fair, Sat May 9" && r.needsReview)
        let book = Data(#"{"kind":"book","summary":"Added Wool to the library","link":"https://k/#/trackers/library?book=b1","review":false}"#.utf8)
        guard case .done(let b) = Share.outcome(status: 200, data: book) else { Issue.record("not done"); return }
        #expect(!b.needsReview)
        #expect(Share.outcome(status: 403, data: Data(#"{"error":"Meals is off","summary":"Meals is off"}"#.utf8)) == .failed("Meals is off"))
        // A wall screen's or kid's key: the auth layer's 403 has no summary.
        #expect(Share.outcome(status: 403, data: Data(#"{"error":"display key cannot access this route"}"#.utf8)) == .failed(Share.signInMessage))
        #expect(Share.outcome(status: 401, data: Data()) == .failed(Share.signInMessage))
        #expect(Share.outcome(status: 500, data: Data()) == .failed("Couldn't add it to Kinwall: error 500."))
    }

    @Test func openingTheAppAtTheLink() {
        let link = "https://k.example/#/calendar?draft=event&title=Spring+fair&date=2026-05-09"
        let app = Share.appLink(link)!
        #expect(app.absoluteString == "family.kinwall.app:/open?to=shared&link=https://k.example/%23/calendar?draft%3Devent%26title%3DSpring%2Bfair%26date%3D2026-05-09")
        #expect(URLComponents(url: app, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "to", value: "shared"), URLQueryItem(name: "link", value: link)])
    }

    @Test func prompts() {
        #expect(Share.prompt(.recipe, text: "x") == nil)
        #expect(Share.prompt(.book, text: "WOOL\nHugh Howey")!.hasSuffix("Author: its author\n\nWOOL\nHugh Howey"))
        #expect(Share.prompt(.restaurant, text: "m")!.hasSuffix("Website: its website, only when the text shows it\n\nm"), "a menu's header lines only")
        #expect(Share.prompt(.event, text: "f")!.contains("Place: the venue's name and its full street address and town on one line, like The Rivers Residence, 12 Elm Road, Springfield\nNotes: anything else worth knowing, like what to bring, costs, or how to RSVP"))
    }

    @Test func theModelsGuess() {
        let g = Share.guess("Kind: event\nTitle: Spring Fair\nDate: Saturday, May 9, 2026\nPlace: Lincoln Elementary")
        #expect(g?.kind == .event && g?.text == "Title: Spring Fair\nDate: Saturday, May 9, 2026\nPlace: Lincoln Elementary")
        #expect(Share.guess("\n**Kind:** Book\nTitle: Wool")?.kind == .book)
        #expect(Share.guess("Kind: unsure") == nil)
        #expect(Share.guess("Kind: event") == nil) // nothing to send
        #expect(Share.guess("Title: Wool") == nil)
        #expect(Share.guessPrompt(text: "flyer").hasSuffix("how to RSVP\n\nflyer"))
    }

    @Test func theGuessInOneLine() {
        #expect(Share.guessLine(.event, text: "Title: Spring fair\nDate: Sat May 9\nTime: 10 AM") == "Looks like an event: Spring fair, Sat May 9")
        #expect(Share.guessLine(.book, text: "Title: Wool\nAuthor: Hugh Howey") == "Looks like a book: Wool")
        #expect(Share.guessLine(.restaurant, text: "Menu:\nPizza 12") == "Looks like a menu")
        #expect(Share.guessLine(.book, text: "Title: " + String(repeating: "a", count: 80)).count == "Looks like a book: ".count + 60)
        #expect(Share.notLabel(.event) == "Not an event?" && Share.notLabel(.restaurant) == "Not a menu?")
    }

    @Test func anEventToCheckComesWithWhatWasRead() throws {
        let ok = Data(#"{"kind":"event","summary":"Check the event: Spring fair","link":"https://k/#/calendar?draft=event","review":true,"event":{"title":"Spring fair","date":"2026-05-09","time":"10:00","end":null,"place":null}}"#.utf8)
        guard case .done(let r) = Share.outcome(status: 200, data: ok) else { Issue.record("not done"); return }
        #expect(r.needsReview && r.event == .init(title: "Spring fair", date: "2026-05-09", time: "10:00"))
        // Saved: not to check, even though it's an event.
        let saved = Data(#"{"kind":"event","summary":"Added Spring fair to Family, Sat May 9","link":"https://k/#/calendar?event=e1","review":false}"#.utf8)
        guard case .done(let s) = Share.outcome(status: 200, data: saved) else { Issue.record("not done"); return }
        #expect(!s.needsReview && s.event == nil)
        // Saving sends the checked event, the calendar and save; nothing else.
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Share.Request(kind: .event, event: .init(title: "Swim", date: "2026-05-09"), save: true, calendarId: "c1"))) as! [String: Any]
        #expect(Set(body.keys) == ["kind", "event", "save", "calendarId"])
        #expect(body["event"] as? [String: String] == ["title": "Swim", "date": "2026-05-09"])
    }

    @Test func aPreviewShowsWhatWouldBeSavedThenTheSameShareSavesIt() throws {
        let ok = Data(#"{"kind":"restaurant","summary":"Ready to add: Corner Slice","link":"https://k/#/meals?restaurant=r1","review":true,"preview":{"title":"Corner Slice","imageUrl":null,"exists":true,"lines":["Pizza","555-0100"],"already":"Already in Kinwall: 12 new items will be added.","token":"t1","restaurant":{"items":12}}}"#.utf8)
        guard case .done(let r) = Share.outcome(status: 200, data: ok) else { Issue.record("not done"); return }
        #expect(r.preview == .init(title: "Corner Slice", imageUrl: nil, lines: ["Pizza", "555-0100"], already: "Already in Kinwall: 12 new items will be added.", token: "t1"))
        #expect(Share.checkTitle(.restaurant) == "Check the restaurant" && Share.checkTitle(.book) == "Check the book")
        // The sheet asks for a preview; the save is the same share without it, with the preview's token.
        let asked = Share.Request(kind: .restaurant, text: "Name: Corner Slice", preview: true)
        let save = asked.saving(r)
        #expect(save == .init(kind: .restaurant, text: "Name: Corner Slice", token: "t1"))
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(save)) as! [String: Any]
        #expect(Set(body.keys) == ["kind", "text", "token"])
        // An older Kinwall saves it straight away: no preview, nothing to check.
        let saved = Data(#"{"kind":"recipe","summary":"Imported Tacos","link":"https://k/#/meals?recipe=x","review":false}"#.utf8)
        guard case .done(let s) = Share.outcome(status: 200, data: saved) else { Issue.record("not done"); return }
        #expect(s.preview == nil && !s.needsReview)
    }

    @Test func theModelsLinesThenTheWordsAsRead() {
        #expect(Share.eventText("Title: Swim\nPlace: Oak Pool", raw: "SWIM\n9 Lake Ave") == "Title: Swim\nPlace: Oak Pool\n---\nSWIM\n9 Lake Ave")
        #expect(Share.eventText(nil, raw: "SWIM") == "SWIM")
        #expect(Share.eventText(" SWIM\n", raw: "SWIM") == "SWIM", "no model: the words once")
    }

    @Test func calendarsToAddTo() {
        let cals = [Share.FamilyCalendar(id: "a", name: "Family"), .init(id: "b", name: "School", writable: false), .init(id: "c", name: "Old", enabled: false),
                    .init(id: "d", name: "Work", canEditEvents: false), .init(id: "e", name: "Kids", canEditEvents: nil)]
        #expect(Share.addable(cals).map(\.id) == ["a", "e"])
        let json = Data(#"[{"id":"a","name":"Family","writable":true,"enabled":true,"canEditEvents":true,"kind":"local"}]"#.utf8)
        #expect(try! JSONDecoder().decode([Share.FamilyCalendar].self, from: json) == [.init(id: "a", name: "Family")])
        // The family's default calendar for new events comes first; the rest keep Kinwall's order.
        let marked = Data(#"[{"id":"a","name":"A meal kit","writable":true,"enabled":true,"default":false},{"id":"b","name":"Our Family","writable":true,"enabled":true,"default":true},{"id":"c","name":"Work","writable":true,"enabled":true}]"#.utf8)
        #expect(Share.addable(try! JSONDecoder().decode([Share.FamilyCalendar].self, from: marked)).map(\.id) == ["b", "a", "c"])
    }

    @Test func thePickersKeepTheHouseholdsClock() {
        let start = Share.pickerDate("2026-10-17", "15:00")!, end = Share.pickerDate("2026-10-17", "17:00")!
        #expect(Share.draft(title: " Maya's party ", place: "The Rivers Residence, 12 Elm Road", notes: " Bring a towel\n", day: start, start: start, end: end, allDay: false)
                == .init(title: "Maya's party", date: "2026-10-17", time: "15:00", end: "17:00", place: "The Rivers Residence, 12 Elm Road", notes: "Bring a towel"))
        #expect(Share.draft(title: "Fair", place: " ", day: Share.pickerDate("2026-05-09")!, start: start, end: end, allDay: true)
                == .init(title: "Fair", date: "2026-05-09"))
        #expect(Share.pickerDate(nil, "10:00") == nil)
    }

    // Several photos of one menu (the share sheet, Add to Kinwall).

    @Test func photosAreJoinedWithPageLines() {
        #expect(Share.joinPages(["Pizza\nCheese 12", "  ", "Sides\nFries 3\n"]) == "Pizza\nCheese 12\n--- Page 2 ---\nSides\nFries 3")
        #expect(Share.joinPages(["Only one\n"]) == "Only one")
        #expect(Share.joinPages([]) == "")
    }

    @Test func aLongMenuIsChunkedByPageThenByLine() {
        let short = ["Name: Corner Slice\nPizza\nCheese 12", "Sides\nFries 3"]
        #expect(Share.chunks(short, limit: 100) == [Share.joinPages(short)], "short enough: one go")
        let page = (1...30).map { "Item \($0) 9.99" }.joined(separator: "\n") // ~400 characters
        let three = [page, page, page]
        let parts = Share.chunks(three, limit: 900)
        #expect(parts.count == 2, "two pages fit, then the third")
        #expect(parts.allSatisfy { $0.count <= 900 })
        #expect(parts[1].hasPrefix("--- Page 3 ---"))
        // A page over the limit on its own is split between lines; nothing is lost.
        let long = Share.chunks([page], limit: 150)
        #expect(long.allSatisfy { $0.count <= 150 })
        #expect(long.joined(separator: "\n") == page)
    }

    @Test func aMenuIsTheModelsHeaderLinesOverTheWordsAsRead() {
        let raw = "Pizza\nCheese 12\n--- Page 2 ---\nSides\nFries 3"
        #expect(Share.menuText("Name: Corner Slice\n**Phone:** 555-0100\nMenu:\nPizza\nCheese 12.00\nWebsite: none\nCuisine:", raw: raw)
                == "Name: Corner Slice\nPhone: 555-0100\nWebsite: none\nMenu:\n\(raw)", "the model's own menu lines are dropped")
        #expect(Share.menuText(nil, raw: raw) == raw)
        #expect(Share.menuText("Here you go", raw: raw) == raw)
    }

    // A photo's words and QR codes.

    private func line(_ text: String, _ x: Double, _ y: Double, w: Double = 0.2, h: Double = 0.02, slope: Double = 0) -> Share.TextLine {
        Share.TextLine(text: text, x: x, y: y, width: w, height: h, slope: slope)
    }

    @Test func aRowsPiecesGoOnOneLineInTheReadersOrder() {
        let lines = [line("Starters", 0.1, 0.1), line("Garlic Knots", 0.1, 0.13), line("(6) $5.10 | (12) $9.20", 0.6, 0.131),
                     line("Fresh garlic, butter,", 0.1, 0.16, w: 0.15), line("parsley", 0.27, 0.161, w: 0.05),
                     line("Pretzel Bites", 0.1, 0.19), line("$7.25", 0.33, 0.25), // not level: its own line
                     line("Desserts", 0.7, 0.1), line("0662-259-+8t", 0.82, 0.1, w: 0.05)] // another column; a mailing code
        #expect(Share.readingOrder(lines) == "Starters\nGarlic Knots (6) $5.10 | (12) $9.20\nFresh garlic, butter, parsley\nPretzel Bites\n$7.25\nDesserts\n0662-259-+8t")
        // Level lines far apart that aren't prices are two columns.
        #expect(Share.readingOrder([line("Garden Party", 0.1, 0.5), line("Fig & Goat", 0.6, 0.5)]) == "Garden Party\nFig & Goat")
        #expect(Share.readingOrder([]) == "")
    }

    @Test func pricesReadAfterTheirNamesGoBackOnTheirRows() {
        // Names, then their prices read as a column of their own after them, across dot leaders.
        let kids = [line("Kids Menu", 0.54, 0.40, h: 0.03), line("Chicken Fingers. $6.25", 0.54, 0.44, w: 0.13), line("Mac & Cheese .", 0.54, 0.47, w: 0.08),
                    line("Grilled Cheese", 0.54, 0.50, w: 0.08), line("$6.25", 0.66, 0.471, w: 0.04), line("$6.25", 0.66, 0.502, w: 0.04),
                    line("0555-019-+8t", 0.70, 0.49, w: 0.01, h: 0.06)]
        #expect(Share.readingOrder(kids) == "Kids Menu\nChicken Fingers. $6.25\nMac & Cheese . $6.25\nGrilled Cheese $6.25\n0555-019-+8t")
        // A price a little lower on the right, as on a tilted photo.
        #expect(Share.readingOrder([line("Brownie Sundae", 0.1, 0.30), line("$4.25", 0.7, 0.308, w: 0.05)]) == "Brownie Sundae $4.25")
        // On a tilted photo (the long lines say so) a price sits most of a line lower than its name,
        // nearer the next name down: it's still its own name's.
        let tilted = [line("Fountain Soda and Lemonade, refills free", 0.1, 0.20, w: 0.6, h: 0.04, slope: 0.045), line("Pretzel Bites", 0.1, 0.30, w: 0.1, slope: 0.045),
                      line("$7.25", 0.4, 0.312, w: 0.04, slope: 0.045), line("Loaded Tots", 0.1, 0.32, w: 0.1, slope: 0.045), line("$8.30", 0.4, 0.332, w: 0.04, slope: 0.045)]
        #expect(Share.readingOrder(tilted) == "Fountain Soda and Lemonade, refills free\nPretzel Bites $7.25\nLoaded Tots $8.30")
        // Too far off level: not that row's.
        #expect(Share.readingOrder([line("Brownie Sundae", 0.1, 0.30), line("$4.25", 0.7, 0.33, w: 0.05)]) == "Brownie Sundae\n$4.25")
    }

    @Test func aNameOverTwoLinesIsOneLine() {
        let sweets = [line("Desserts", 0.54, 0.25, h: 0.03), line("Giant Oatmeal", 0.54, 0.29, w: 0.1), line("Raisin Cookie", 0.54, 0.312, w: 0.1), line("$2.25", 0.66, 0.312, w: 0.04),
                      line("Fountain", 0.54, 0.40, w: 0.1), line("Soda Products", 0.54, 0.422, w: 0.1), line("$2.85", 0.66, 0.422, w: 0.04),
                      line("Water", 0.54, 0.45, w: 0.1), line("$2.85", 0.66, 0.45, w: 0.04)]
        #expect(Share.readingOrder(sweets) == "Desserts\nGiant Oatmeal Raisin Cookie $2.25\nFountain Soda Products $2.85\nWater $2.85")
        // Not a description under a name, nor two items with their own prices, nor a heading over an item.
        #expect(Share.readingOrder([line("Nashville Crispy", 0.1, 0.1), line("Fried chicken, slaw $13.50", 0.1, 0.122)]) == "Nashville Crispy\nFried chicken, slaw $13.50")
        #expect(Share.readingOrder([line("Mac & Cheese $6.25", 0.1, 0.1), line("Grilled Cheese $6.25", 0.1, 0.122)]) == "Mac & Cheese $6.25\nGrilled Cheese $6.25")
        #expect(Share.readingOrder([line("Kids Menu", 0.1, 0.06, h: 0.035), line("Chicken Fingers $6.25", 0.1, 0.1)]) == "Kids Menu\nChicken Fingers $6.25")
    }

    @Test func aCloserLookAddsWhatTheWholePhotoMissed() {
        let base = [line("Desserts", 0.5, 0.2), line("Brownie Sundae", 0.5, 0.25), line("Beverages", 0.5, 0.4), line("Water", 0.5, 0.45)]
        let more = [line("Brownie Sundae", 0.5, 0.251), line("$4.25", 0.7, 0.25, w: 0.05), line("$2.85", 0.7, 0.45, w: 0.05)]
        #expect(Share.merged(base, more).map(\.text) == ["Desserts", "Brownie Sundae", "$4.25", "Beverages", "Water", "$2.85"])
        #expect(Share.readingOrder(Share.merged(base, more)) == "Desserts\nBrownie Sundae $4.25\nBeverages\nWater $2.85")
    }

    @Test func aMenusQRCodeGoesByTheWordsBesideIt() {
        let code = line("https://order.cornerslice.example/start", 0.6, 0.7, w: 0.12, h: 0.1)
        let order = [line("Scan To Order Online!", 0.6, 0.82)]
        #expect(Share.linkLines(codes: [code], words: order) == ["Order online: https://order.cornerslice.example/start"])
        #expect(Share.linkLines(codes: [code], words: [line("See our full menu", 0.45, 0.72, w: 0.14)]) == ["Menu link: https://order.cornerslice.example/start"])
        #expect(Share.linkLines(codes: [code], words: [line("Visit our website", 0.75, 0.7)]) == ["Website: https://order.cornerslice.example/start"])
        // Words beside it that say nothing clear, or ordering words too far away: not sure what it's for.
        #expect(Share.linkLines(codes: [code], words: [line("Corner Slice", 0.6, 0.65), line("Order online", 0.1, 0.1)]) == ["QR code: https://order.cornerslice.example/start"])
        // Social media, reviews, Wi-Fi and payments, and payloads that aren't web links, are left out.
        #expect(Share.linkLines(codes: [code], words: [line("Leave us a review!", 0.6, 0.82)]).isEmpty)
        #expect(Share.linkLines(codes: [line("https://www.instagram.com/cornerslice", 0.6, 0.7, w: 0.1, h: 0.1)], words: order).isEmpty)
        #expect(Share.linkLines(codes: [line("WIFI:S:Corner;T:WPA;P:secret;;", 0.6, 0.7, w: 0.1, h: 0.1)], words: order).isEmpty)
        #expect(Share.linkLines(codes: [], words: order).isEmpty, "no QR code: nothing")
        // Several: the ordering one, wherever it is, and one line of each kind.
        let menu = line("https://cornerslice.example/menu.pdf", 0.1, 0.1, w: 0.1, h: 0.1)
        #expect(Share.linkLines(codes: [menu, code, code], words: order + [line("Our menu", 0.1, 0.22)]) == ["Order online: https://order.cornerslice.example/start", "Menu link: https://cornerslice.example/menu.pdf"])
        #expect(Share.withLinks(["Order online: https://x.example"], "Pizza\nCheese 12") == "Order online: https://x.example\nPizza\nCheese 12")
        #expect(Share.withLinks([], "Pizza") == "Pizza")
    }

    @Test func guessLineCountsPages() {
        #expect(Share.guessLine(.restaurant, text: "Name: Corner Slice\nMenu:\nPizza 12", pages: 3) == "Looks like a menu: Corner Slice, 3 pages")
        #expect(Share.guessLine(.restaurant, text: "", pages: 2) == "Looks like a menu: 2 pages")
        #expect(Share.guessLine(.event, text: "Title: Spring fair", pages: 2) == "Looks like an event: Spring fair")
    }
}
