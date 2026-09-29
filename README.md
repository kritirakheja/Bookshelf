# Bookshelf

A personal library app for iPhone, built with SwiftUI and SwiftData. Catalogue the books you own, track what you're reading, and keep a shelf of your top recommendations.

## Features

- **Explore**: your unread books as a cover grid, filterable by category
- **Reading**: books in progress, with start dates; swipe to mark finished
- **Favourites**: a ranked shelf of up to 10 books, each with a "why I recommend it" note
- **Profile**: photo, name and reading stats (pages read, books per year, rating breakdown, top authors)
- **Adding books**: scan the ISBN barcode, type an ISBN, or enter details by hand. Title, author, cover and suggested categories come from [Open Library](https://openlibrary.org/developers/api)
- Star ratings, finish dates, notes, and multiple categories per book
- Everything is stored on the device; no account or server

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

Barcode scanning needs a real iPhone (the simulator has no camera). In the simulator, the app seeds a few sample books on first launch.

## Tests

```sh
xcodebuild test -scheme Bookshelf -destination 'platform=iOS Simulator,name=iPhone 17'
```

One test calls the live Open Library API and is skipped by default. Run it with `TEST_RUNNER_LIVE_TESTS=1`.
