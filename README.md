# Daily Box Score — iOS App

The companion iPhone/iPad app for The Daily Box Score website. It shows every
daily edition, lets readers pick favorite teams (their games appear first and
jump straight to the right page of the PDF), sends a morning notification,
and reads downloaded editions offline. A Teams tab gives every club's full
season game log with an opponent filter; the Editions tab has a date picker
to jump to any day. Styled like a classic newspaper sports page, same as the
website.

The app has no server of its own: it reads the edition list, game index, team
logs, and PDFs straight from the public website feed (`/feed/editions.json`,
`/feed/teams.json`), which is already live and updates every morning.

## What you need

- A **Mac** with **Xcode** installed (free from the Mac App Store).
- Your **Apple Developer account** (you already have one).
- Your iPhone for testing.

## Opening the project

1. Copy the whole `box-score-app` folder to your Mac (AirDrop, iCloud Drive,
   a USB stick — whatever is easiest).
2. Double-click `DailyBoxScore.xcodeproj`. It opens in Xcode.

## First run on your iPhone

1. In Xcode's left sidebar, click the very top item ("DailyBoxScore").
2. Under **Signing & Capabilities**, tick "Automatically manage signing" and
   pick your Apple Developer team from the dropdown.
3. Change the **Bundle Identifier** to something unique to you, e.g.
   `com.yourname.dailyboxscore`. (The placeholder `com.toolstem.dailyboxscore`
   is in the project now.)
4. Plug in your iPhone, pick it as the run destination at the top of the
   Xcode window, and press the ▶ Run button.
5. The first time, your iPhone will ask you to trust the developer certificate
   under Settings → General → VPN & Device Management.

## Sending it to TestFlight (for testing before the App Store)

1. In Xcode: **Product → Archive**. When the archive finishes, the Organizer
   window opens.
2. Click **Distribute App → TestFlight & App Store**.
3. Once uploaded, open **App Store Connect** (appstoreconnect.apple.com),
   add yourself as a tester, and install via the TestFlight app on your phone.

## Submitting to the App Store

The standard flow: App Store Connect → create the app record → fill in the
description, screenshots, and privacy details → submit the TestFlight build
for review. Apple usually reviews within a day or two.

## Starting to charge later (the season pass)

The app is built free-first, with the purchase plumbing already in place:

1. In App Store Connect, create an in-app purchase product with the ID
   `com.toolstem.dailyboxscore.season2027` (non-consumable, $4.99 or whatever
   you choose). Use a new product ID each season (`...season2028`, etc.).
2. In `DailyBoxScore/Services/StoreManager.swift`, flip `paywallEnabled`
   from `false` to `true`.
3. For testing purchases before launch, Xcode can use the included
   `Configuration.storekit` file: in the scheme editor (Product → Scheme →
   Edit Scheme → Run), set "StoreKit Configuration" to that file.

While `paywallEnabled` is false, everything is unlocked and no store UI
appears anywhere in the app.

## Notes

- This code was written without access to a Mac, so Xcode has never compiled
  it. The first build may flag one or two small issues — Xcode will point at
  the exact line. Paste any error into chat and it can be fixed quickly.
- No team logos are used anywhere (names and scores only), which sidesteps
  trademark headaches.
- The morning notification is a simple daily local notification at 7:30 AM.
  Per-team score alerts are a possible later upgrade.
- Possible version-two additions already discussed: a vintage standings page
  and a per-team season view.
