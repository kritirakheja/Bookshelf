# Bookshelf

A personal library app for iPhone, built with SwiftUI and SwiftData, with one clean look throughout (soft off-white background, deep green accent, the [Inter](https://rsms.me/inter/) typeface, bundled under the SIL Open Font License; see `Views/Shared/Theme.swift`). Catalogue the books you own, track what you're reading and how far in you are, keep a shelf of favourite recommendations, remember who has your books, and save the bookstores you love.

## Features

**Tabs**
- **Explore**: your unread books by category. A card per category with its covers scrolling sideways; tap the category name for a grid of all its books. Tapping a cover "picks the book up" as a 3D book (SceneKit) with a spine and page edges: it turns over to show its back cover with the description, like reading the back of a book in a library. Tap to turn it over; Start reading and Full details sit underneath. Search covers all unread books.
- **Reading**: books in progress. The one you updated most recently sits at the top as a large card (percentage, progress bar, the last seven days, *Update progress* and *Finished*); the others follow as compact rows, each with a progress bar. Tap *Update progress*, type the page you're on, and the app shows the percentage read, the pages you read today and the pages left; the book's page adds a chart of the last seven days. Reaching the last page offers to mark the book read. *Finished* does that in one tap.
- **Favourites**: a ranked shelf of up to 10 books you'd recommend most, each with its rank, rating and a "why I recommend it" note. Below it, everything you've read year by year, with an optional goal per year ("27 of 30 books").
- **Bookstores**: a map of bookstores you've saved, with *Find nearby* and *Search this area* (Apple Maps, no key needed), directions, and notes.
- **Profile**: photo, name and counts, plus All books, Read, Lent out, Borrowed and Categories, and a *Sharpen covers* row while any cover is still blurry. **All books** shows covers face-out in rows, split into Fiction and Non-fiction (or as a list).

**Adding books**
- Scan the barcode, search by title or author, type an ISBN, photograph the front cover, or enter details by hand.
- Details, cover, suggested categories and the publisher's description come from [Open Library](https://openlibrary.org/developers/api), with [Google Books](https://developers.google.com/books) as a fallback (recent and regional editions are often only there). English editions are preferred.
- Covers are fetched at full size. Small, blurry ones are swapped in the background for a sharp cover of the same book (Open Library, then [Apple Books](https://performance-partners.apple.com/search-api)): the same artwork when it exists, otherwise another English edition by the same author. The replaced cover is kept and can be put back from *Change cover*; covers you photograph or pick yourself are never swapped.
- Cover scans use the document scanner (cropped and straightened); the text is read on-device with Vision and matched by title and author.
- A missing page count is looked up in the background (the typical length of editions with the same title and author), so progress can show a percentage; you're only asked when nothing is found online.
- Adding a book you already own (same ISBN, or same title and author) is caught before it's saved, however you add it.

**Each book** has its own page, in order of importance: the cover large on a soft blurred wash of its own colours, then the title, what the book is about, its categories and reading status, and one plain list for everything else. The page takes its accent colour (tags, buttons, switch, stars) from the cover, so each book's page has its own colour. The 3D book's buttons on Explore use the same colour.
- Status (unread / reading / read). While reading: progress, as above. Once read: the finish date, as a day, just a year, or "I don't remember".
- Star rating, notes, categories (also editable from *Edit*), and an **About the book** description (filled in automatically in the background).
- Change the cover (scan it, pick a photo, or choose another edition's cover online).
- **Lending**: lend to a friend (from Contacts or by name) and mark it returned; history is kept.
- **Borrowing**: mark a book as borrowed from someone and give it back later.

**Backup & sync** (optional): sign up with email and password to back up your library to [Supabase](https://supabase.com) and keep it in sync across devices: books, covers, reading progress, lending history, your profile and saved bookstores. Yearly goals, a cover's "set by hand" marker and the cover a swap replaced stay on the device. Without an account, everything stays on the device.

## How the code is laid out

- `Models/`: SwiftData models (`Book`, `ReadingEntry`, `Loan`, `BookCategory`, `Bookstore`).
- `Services/`: lookups (`BookLookup` over Open Library, Google Books and Apple Books), covers (`CoverDownloader`, `CoverImage`, `CoverUpgrade`, `CoverColor`), background fill-ins (`DescriptionBackfill`, `PageCountBackfill`), and small pieces of logic (`ReadingYears`, `FavoritesShelf`, `LibraryDuplicates`).
- `Sync/`: Supabase sync (`SyncEngine`, `BookRecord`, `AccountStore`).
- `Views/`: one folder per tab, plus `Shared/` (`Theme`, `Components`, `CoverView`, `CoverStrip`).
- `Preview/`: sample data and the launch arguments used for screenshots and the walkthrough.

## Requirements

- Xcode 26 or later, iOS 17+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # add your bundle ID and Apple team ID
xcodegen generate
open Bookshelf.xcodeproj
```

The Xcode project is generated from `project.yml` and isn't checked in. `Config/Local.xcconfig` holds your personal settings and keys and is git-ignored. You only need signing settings to run on a real device; the simulator works without them.

### Google Books (optional, recommended)

Create a free API key in Google Cloud (enable the **Books API**), ideally restricted to your bundle ID and the Books API, and put it in `Config/Local.xcconfig` as `GOOGLE_BOOKS_KEY`. Without it, lookups use Open Library only.

### Backup & sync (optional)

1. Create a free Supabase project.
2. In its SQL Editor, run [`supabase/schema.sql`](supabase/schema.sql). It creates the `books`, `profiles` and `bookstores` tables, a private storage bucket, and row-level security so each account only sees its own data. It's safe to re-run, and **must be re-run after pulling an update that adds a column** (most recently `progress`, for daily reading progress): the app's sync fails against a table that lacks a column it sends.
3. Under Authentication → Sign In / Providers, turn off **Confirm email** (the confirmation link can't open the app).
4. Put the project host and publishable key in `Config/Local.xcconfig` (see the example file).

Without these settings the app builds and works as before, with the sync section hidden.

### Permissions

The camera (barcode and cover scanning) and location (only while the app is open, for *Find nearby*) are asked for when first used. Contacts are never read: the system picker hands over just the one person you choose.

Barcode and cover scanning need a real iPhone (the simulator has no camera). In the simulator, the app seeds a few sample books and bookstores on first launch.

## Tests

```sh
xcodebuild test -scheme Bookshelf -destination 'platform=iOS Simulator,name=iPhone 17'
```

A second scheme, `BookshelfWalkthrough`, uses the app like a person would (XCUITest): it taps, types and swipes through every flow on a throwaway in-memory sample library (no account, sync or lookups) and saves a screenshot of each step, plus a `log.txt` of anything it couldn't find:

```sh
TEST_RUNNER_SNAP_DIR=/tmp/walkthrough xcodebuild test -scheme BookshelfWalkthrough -destination 'platform=iOS Simulator,name=iPhone 17'
```

Add `TEST_RUNNER_WALK_DARK=1` for dark mode. It doesn't cover the camera, the Contacts and photo pickers, sync, or the map search.

Tests that call live services (Open Library, Google Books, Apple Maps, and your Supabase project if configured) are skipped by default. Run them with `TEST_RUNNER_LIVE_TESTS=1`. The Supabase test creates throwaway `@example.com` accounts and deletes their data afterwards.
