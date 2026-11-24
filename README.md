# My Planner for Mac

A personal productivity, study and budget dashboard that lives on the macOS desktop like a built-in widget. Built for my own daily use while exams : plan the day with real deadlines, track what I study, and keep an eye on money, all in one frosted-glass panel that never needs to be opened.

> **Status:** personal project, in daily use. Not published to the App Store. All data stays on the Mac.

<!-- Add screenshots here
<p align="center">
  <img src="docs/screenshots/today.png" width="260" />
  <img src="docs/screenshots/study.png" width="260" />
  <img src="docs/screenshots/budget.png" width="260" />
</p>
-->

## Why I built it

Most to-do and study apps are either too simple or sit in a window I have to remember to open. I wanted a single panel pinned to the desktop that shows what is due, how much I have studied, and where my money is going, and that keeps my data private on my own machine.

## Features

**Today and Tasks**
- Every task has a **deadline** (in 1/2/4 hours, tonight, tomorrow, or any date and time)
- Live countdown ("Due 9:00 PM · 2h 15m left"); the panel re-checks the clock while it sits on the desktop
- **Expiry states:** pending (circle), expired (red cross and red card), cleared (green tick, flagged if it was completed late)
- Priorities, filters (All / Pending / Expired / Done) and a quick-add bar

**Goals and Habits**
- Goals with a **manually typed target** and editable progress, grouped by week, month or year
- Habits with a one-tap daily check-in, streak counter and a 7-day history, plus ready-made study habit suggestions

**Study (for exam preparation)**
- Daily study target with progress ring, streak and a 7-day chart
- Time by subject, plus a manual "log study time" box
- **Exam countdown** for BPSC and semester exams, also shown on the Today tab
- **Syllabus tracker:** subjects and topics, mark topics as studied and revised, with a "time to revise" list for topics studied 3 or more days ago
- **Mock test log:** score history with average, best, latest and a trend chart

**Focus timer**
- Timer with any custom length (for example 2 hours 30 minutes) or presets from 15 minutes to 3 hours, plus a **stopwatch** mode
- Choose the subject being studied; finished sessions are logged to the Study tab automatically

**Notes**
- Click a note to open it as a **full page** with a continuous editor, title, word and character count, reading time and last-edited time
- Quick-insert buttons (bullet, checkbox, divider, date, time), pin, copy the whole note, save as a text file, and search across all notes

**Budget (full personal finance tracker)**
- Home: amount left to spend, progress against the monthly budget, daily allowance, income / spent / saved, daily spending chart, category limits, upcoming bills
- Activity: every transaction grouped by day, with search and filters, editable and deletable
- Insights: monthly donut chart and comparison with the previous month; yearly income vs spending chart and month-by-month table; **written advice** generated from the data (overspending pace, categories that jumped, low savings rate, small purchases that add up)
- Savings goals (a trip, a gadget, books) with progress and "save ₹X a month to finish on time"
- Recurring bills with "mark as paid", and CSV export
- Every previous month and year is kept and browsable

**The panel itself**
- Frosted glass with a colour theme per tab, animated progress rings
- Pinned at desktop level, so it behaves like a widget; optional "Keep Above Windows"
- Menu bar item: show or hide, panel size (Compact / Comfortable / Large), launch at login, back up and restore, export budget CSV
- One backup file for everything; it can also restore a backup made by my Android budget app

## Tech

- **SwiftUI + AppKit**, Swift Package Manager (no Xcode project)
- Borderless translucent `NSWindow` at desktop window level, `NSVisualEffectView` blur, `NSStatusItem` menu, `SMAppService` for launch at login
- Charts (bars, donut, line, rings) drawn with plain SwiftUI shapes, with no third-party libraries
- Rule-based insights engine that turns monthly and yearly figures into plain-language advice
- Local JSON persistence with `Codable`, including automatic migration from earlier data formats
- Same JSON layout for budget data as the Android app, so backups are interchangeable
- **GitHub Actions** builds a universal (Apple Silicon and Intel) `.app` on every push, ad-hoc signed

## Project structure

```
Sources/MyPlanner/
  App.swift      App and desktop window, theme, Today, Tasks, Goals, Habits, Notes
  Budget.swift   Budget models, advice engine, charts and all budget screens
  Study.swift    Study tracker, syllabus, mock tests, focus timer
Package.swift
Info.plist
.github/workflows/build.yml
```

## Build it yourself

```
swift build -c release
```

Or push to GitHub and download the app from the **Actions** artifacts. The app is not notarised, so on first launch right-click it and choose **Open** (or allow it under *System Settings → Privacy & Security*).

## What I learned

- Making a macOS app behave like a desktop widget (window levels, activation policy, status items, hidden Edit menu for keyboard shortcuts)
- Designing a multi-section SwiftUI interface with shared components and a per-tab theme
- Modelling time-based state (deadline expiry, streaks, month and year history) and evolving a data format without losing existing data
- Automating universal macOS builds with CI

## Roadmap

- [ ] Reminder notifications on macOS
- [ ] Optional iCloud sync with the Android budget app
- [ ] Unit tests for the insights engine and date logic
- [ ] Proper code signing and notarisation

## Author

Built by **[Your Name]**. [LinkedIn](https://linkedin.com/in/your-profile) · [Email](mailto:you@example.com)
