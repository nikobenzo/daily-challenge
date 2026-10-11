<p align="center">
  <a href="https://nikobenzo.github.io/daily-challenge/">
    <img src="docs/assets/hero.jpg" alt="Daily Challenge Tracker: make every day count. The app icon, the Today panel with five goal rings and a water jug at 2,250 ml, and an iPhone Home Screen with Daily Challenge widgets." width="100%">
  </a>
</p>

<h1 align="center">Daily Challenge</h1>

<p align="center">
  <b>A calm, native tracker for your 75-day challenge.</b><br>
  Five daily goals, one tap each, in your Mac menu bar and on your iPhone.
</p>

<p align="center">
  <a href="https://github.com/nikobenzo/daily-challenge/releases/latest"><img alt="Latest Mac release" src="https://img.shields.io/github/v/release/nikobenzo/daily-challenge?label=Mac%20app&logo=apple&logoColor=white&color=1F56E0&style=flat-square"></a>
  <img alt="macOS 14 or newer" src="https://img.shields.io/badge/macOS-14%2B-1F56E0?logo=apple&logoColor=white&style=flat-square">
  <img alt="iPhone app coming soon" src="https://img.shields.io/badge/iPhone-coming%20soon-0B1B3F?logo=apple&logoColor=white&style=flat-square">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white&style=flat-square">
  <img alt="Built with SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-0A84FF?logo=swift&logoColor=white&style=flat-square">
</p>

<p align="center">
  <a href="#install"><b>Install</b></a> ·
  <a href="#features"><b>Features</b></a> ·
  <a href="#screenshots"><b>Screenshots</b></a> ·
  <a href="#privacy"><b>Privacy</b></a> ·
  <a href="https://nikobenzo.github.io/daily-challenge/support.html"><b>Support</b></a>
</p>

<br>

Daily Challenge keeps a 75-day challenge simple. Every day you aim for **four litres of water, a workout, a walk, your diet and Bible reading**. Tick each one off as you go, watch the water jug fill, and let the app keep count of your streak. Add a few personal to-dos on top if you like. Your Mac and iPhone stay in sync through one account, and everything still works offline.

## Features

<table>
  <tr>
    <td width="50%" valign="top">
      <b>💧 Water you can see</b><br>
      A drawn 4 L jug fills with every <b>+ 450 ml</b> pour. Undo the last one or log a custom amount.
    </td>
    <td width="50%" valign="top">
      <b>✅ Five goals, one tap each</b><br>
      Workout, walk, diet and Bible reading sit beside water as rings. A day is complete when all five are done.
    </td>
  </tr>
  <tr>
    <td valign="top">
      <b>🔥 Streaks and history</b><br>
      See your current and best streak, browse a calendar of completed days, and fix a past day on purpose with a clear edit mode.
    </td>
    <td valign="top">
      <b>📝 Extras</b><br>
      Add up to ten personal to-dos, such as stretching or journaling. They never affect your streak, and unfinished ones carry over with a Late label.
    </td>
  </tr>
  <tr>
    <td valign="top">
      <b>📱 Home Screen widgets</b><br>
      Log water, tick goals and check extras straight from the Home Screen, even with the app closed or offline. A water ring is available on the Lock Screen.
    </td>
    <td valign="top">
      <b>🔄 Mac and iPhone in sync</b><br>
      One account keeps both devices up to date. Entries save on the device first and upload when a connection returns.
    </td>
  </tr>
  <tr>
    <td valign="top">
      <b>🔔 Gentle water reminders</b><br>
      Optional reminders at an interval and daily window you choose. They stop once you reach four litres.
    </td>
    <td valign="top">
      <b>🌗 Feels at home</b><br>
      Native SwiftUI in light and dark, with VoiceOver labels and Reduce Motion support. On the Mac it lives in the menu bar, with no Dock icon.
    </td>
  </tr>
</table>

## Screenshots

### iPhone

<p align="center">
  <img src="docs/assets/iphone/01-daily-goal.jpg" alt="Today screen: five clear goals with the water jug and extras" width="24%">
  <img src="docs/assets/iphone/02-home-screen.jpg" alt="Home Screen widgets for water, daily goals and extras" width="24%">
  <img src="docs/assets/iphone/05-history.jpg" alt="History calendar with completed days and streak" width="24%">
  <img src="docs/assets/iphone/07-complete.jpg" alt="All five goals complete for the day" width="24%">
</p>

<details>
<summary><b>More iPhone screenshots</b></summary>
<br>
<p align="center">
  <img src="docs/assets/iphone/03-water.jpg" alt="Close up of water tracking with the + 450 ml button" width="24%">
  <img src="docs/assets/iphone/04-extras.jpg" alt="Close up of extras with Late labels on unfinished items" width="24%">
  <img src="docs/assets/iphone/06-dark-mode.jpg" alt="Today screen in dark mode" width="24%">
</p>
</details>

### Mac menu bar

Click the drop icon in the menu bar and your day is right there. These images follow your GitHub light or dark theme.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/mac/today-extras-dark.png">
    <img src="docs/assets/mac/today-extras-light.png" alt="Mac menu bar popup showing the Today view with goal rings, extras and the water jug" width="360">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/mac/history-dark.png">
    <img src="docs/assets/mac/history-light.png" alt="Mac menu bar popup showing the History calendar and the activity for a selected day" width="360">
  </picture>
</p>

## Install

### Mac

Open Terminal and paste:

```sh
curl -fsSL https://nikobenzo.github.io/daily-challenge/install.sh | bash
```

The script downloads the [latest release](https://github.com/nikobenzo/daily-challenge/releases/latest), checks that it is signed by the developer and notarized by Apple, moves it to Applications and opens it. Nothing is installed if a check fails. You can read the script first in [`site/install.sh`](site/install.sh).

<details>
<summary><b>Prefer to install by hand?</b></summary>
<br>

1. Download the zip from the [latest release](https://github.com/nikobenzo/daily-challenge/releases/latest).
2. Unzip it and drag **Daily Challenge** to Applications.
3. Open it, then click the drop icon in the menu bar.

</details>

Requires macOS 14 or newer on an Apple silicon Mac. The app updates itself, so you only install it once.

### iPhone

**Coming soon to the App Store** as *Daily Challenge Tracker*. It needs iOS 26 or newer.

## Privacy

Daily Challenge collects only what it needs to show your progress and sync it between your devices.

- **No ads, no tracking and no analytics.** There are no third-party SDKs that collect usage data.
- **Your data stays yours.** Your account email and challenge entries are stored with Supabase, and each row can only be read by your own signed-in account.
- **Settings stay on the device.** Reminder times and appearance are never sent anywhere.
- **Delete any time.** Delete your account in the iPhone app, or email us, and your data is removed from the server.

Read the full [privacy policy](https://nikobenzo.github.io/daily-challenge/privacy.html).

## Support

Found a bug or have a question? Email **[yakovetskyi@icloud.com](mailto:yakovetskyi@icloud.com)** and mention your device and app version, or browse the [support page](https://nikobenzo.github.io/daily-challenge/support.html) for common questions. Please report security issues privately as described in [SECURITY.md](SECURITY.md).

## Build from source

Daily Challenge is written in Swift 6 and SwiftUI. The Mac app and the iPhone app share one core library for the challenge rules, storage and sync.

```sh
git clone https://github.com/nikobenzo/daily-challenge.git
cd daily-challenge
swift test
```

<details>
<summary><b>What is inside</b></summary>
<br>

| Area | Built with |
| --- | --- |
| Mac app | SwiftUI and AppKit menu bar popup, Sparkle 2 updates |
| iPhone app | SwiftUI, WidgetKit and App Intents widgets |
| Shared core | Challenge rules, local-first storage and sync in Swift packages |
| Backend | Supabase Postgres and Auth with row-level security |
| Install | Developer ID signed, notarized, installed by a small shell script |

</details>

A working signed build needs your own Supabase project and signing setup. The [developer guide](docs/DEVELOPMENT.md) covers configuration, building, testing and releases in full.

## About

Daily Challenge is a personal project by Mykola Yakovetskyi, built to make a 75-day challenge easier to keep. It is not seeking outside contributions; see [CONTRIBUTING.md](CONTRIBUTING.md) for how to report problems.
