# Bookshelf

A personal library app for iPhone, built with SwiftUI and SwiftData, with one warm look throughout (paper background, brown accent, serif titles, wooden shelves; see `Views/Shared/Theme.swift`). Catalogue the books you own, track what you're reading, keep a shelf of favourite recommendations, remember who has your books, and save the bookstores you love.

## Features

**Tabs**
- **Explore**: Netflix-style browsing of your unread books. A daily featured carousel, then rows you swipe through: Continue reading, Recently added, Quick reads, More from authors you love, and one row per category.
- **Reading**: books in progress with start dates; swipe to mark finished.
- **Favourites**: a ranked shelf of up to 10 books, three per wooden shelf, each with its rank, rating and a "why I recommend it" note.
- **Bookstores**: a map of bookstores you've saved, with *Find nearby* and *Search this area* (Apple Maps, no key needed), directions, and notes.
- **Profile**: photo, name and counts, plus All books, Read, Lent out, Borrowed and Categories. **All books** is displayed like a bookshop: covers face-out on wooden shelves, split into Fiction and Non-fiction.

**Adding books**
- Scan the barcode, search by title or author, type an ISBN, photograph the front cover, or enter details by hand.
- Details, cover, suggested categories and the publisher's description come from [Open Library](https://openlibrary.org/developers/api), with [Google Books](https://developers.google.com/books) as a fallback (recent and regional editions are often only there). English editions are preferred.
- Cover scans use the document scanner (cropped and straightened); the text is read on-device with Vision and matched by title and author.
- Adding a book you already own (same ISBN, or same title and author) is caught before the form opens.

**Each book** has its own page: the cover on a shelf, then simple cards for reading status and rating, favourite, description, lending and notes.
- Status (unread / reading / read) with dates, including "finished in <year>" when only the year is known.
- Star rating, notes, categories, and an **About this book** description (filled in automatically in the background).
- Change the cover (scan it, pick a photo, or choose another edition's cover online).
- **Lending**: lend to a friend (from Contacts or by name) and mark it returned; history is kept.
- **Borrowing**: mark a book as borrowed from someone and give it back later.

**Backup & sync** (optional): sign up with email and password to back up everything to [Supabase](https://supabase.com) and keep it in sync across devices. Without an account, everything stays on the device.

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
2. In its SQL Editor, run [`supabase/schema.sql`](supabase/schema.sql). It creates the `books`, `profiles` and `bookstores` tables, a private storage bucket, and row-level security so each account only sees its own data. It's safe to re-run after updates.
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

Tests that call live services (Open Library, Google Books, Apple Maps, and your Supabase project if configured) are skipped by default. Run them with `TEST_RUNNER_LIVE_TESTS=1`. The Supabase test creates throwaway `@example.com` accounts and deletes their data afterwards.
