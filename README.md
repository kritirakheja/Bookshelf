# Bookshelf

A personal library app for iPhone, built with SwiftUI and SwiftData. Catalogue the books you own, track what you're reading, and keep a shelf of your top recommendations.

## Features

- **Explore**: your unread books as a cover grid, filterable by category
- **Reading**: books in progress, with start dates; swipe to mark finished
- **Favourites**: a ranked shelf of up to 10 books, each with a "why I recommend it" note
- **Profile**: photo, name and reading stats (pages read, books per year, rating breakdown, top authors)
- **Adding books**: scan the ISBN barcode, type an ISBN, or enter details by hand. Title, author, cover and suggested categories come from [Open Library](https://openlibrary.org/developers/api)
- **Cover scan**: when a barcode isn't recognised (or there isn't one), photograph the front cover. The text is read on-device with Vision and matched against Open Library by title and author
- Star ratings, finish dates, notes, and multiple categories per book
- **Backup & sync** (optional): sign up with email and password to back up the library to [Supabase](https://supabase.com) and keep it in sync across devices. Without an account, everything stays on the device

## Requirements

- Xcode 26 or later, iOS 17+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # add your bundle ID and Apple team ID
xcodegen generate
open Bookshelf.xcodeproj
```

The Xcode project is generated from `project.yml` and isn't checked in. `Config/Local.xcconfig` holds your personal signing settings and is git-ignored. You only need it to run on a real device; the simulator works without it.

### Backup & sync (optional)

1. Create a free Supabase project.
2. In its SQL Editor, run [`supabase/schema.sql`](supabase/schema.sql). It creates the tables, a private storage bucket, and row-level security so each account only sees its own data.
3. Under Authentication → Sign In / Providers, turn off **Confirm email** (the confirmation link can't open the app).
4. Put the project host and publishable key in `Config/Local.xcconfig` (see the example file).

Without these settings the app builds and works as before, with the sync section hidden.

Barcode scanning needs a real iPhone (the simulator has no camera). In the simulator, the app seeds a few sample books on first launch.

## Tests

```sh
xcodebuild test -scheme Bookshelf -destination 'platform=iOS Simulator,name=iPhone 17'
```

Tests that call live services (Open Library, and your Supabase project if configured) are skipped by default. Run them with `TEST_RUNNER_LIVE_TESTS=1`. The Supabase test creates throwaway `@example.com` accounts and deletes their data afterwards.
