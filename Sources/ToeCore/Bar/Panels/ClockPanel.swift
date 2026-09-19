import Foundation

/// The clock's panel — `panels/clock/Panel.qml`, the calendar: today as the hero, a month grid
/// with ISO week numbers down its side, and the month stepped under it.
///
/// Upstream's `Model.js` is date arithmetic on JavaScript's `Date`, written to be testable
/// under node; this is the same arithmetic on `Calendar`, written to be testable under
/// `make test`. What is left out: the year-progress rail and the memento-mori bar. The first
/// is a second progress bar in a panel that opened to answer "what is the date", and the
/// second takes a birth year toe's config has no row for. The grid is always six weeks, as
/// upstream's is, so the card is the same height in every month and stepping through the
/// year never moves the row under the pointer.
public enum ClockPanel {

    /// Sunday is 0 and Saturday 6 — `Date.getDay()`'s numbering and `Calendar`'s weekday less
    /// one, so a configured week start passes straight through.
    public static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// One cell of the grid.
    public struct Day: Equatable, Sendable {
        public let year: Int
        public let month: Int
        public let day: Int
        /// In the month on view, as against the tail of the one before or the head of the next.
        public let inMonth: Bool
        public let weekend: Bool
        public let today: Bool

        public init(year: Int, month: Int, day: Int, inMonth: Bool, weekend: Bool, today: Bool) {
            self.year = year
            self.month = month
            self.day = day
            self.inMonth = inMonth
            self.weekend = weekend
            self.today = today
        }
    }

    /// One row of the grid: its ISO week number and seven days.
    public struct Week: Equatable, Sendable {
        public let number: Int
        public let days: [Day]
        public init(number: Int, days: [Day]) {
            self.number = number
            self.days = days
        }
    }

    /// What the calendar row carries — everything the view needs and nothing it has to work
    /// out: the weekday headings in the order the week runs, and the six weeks.
    public struct Grid: Equatable, Sendable {
        public let weekdays: [String]
        public let weeks: [Week]
        public init(weekdays: [String], weeks: [Week]) {
            self.weekdays = weekdays
            self.weeks = weeks
        }
    }

    /// A month on view, and where the pointer went from it.
    public struct View: Equatable, Sendable {
        public var year: Int
        public var month: Int
        public init(year: Int, month: Int) {
            self.year = year
            self.month = month
        }
    }

    // MARK: - The arithmetic, `Model.js`

    /// `normalizedWeekStart`: a name, a three-letter name or a number, to 0…6; anything else is
    /// nil, and the caller's default — Monday, since the clock's `ww` is the ISO week.
    public static func weekStart(_ value: String) -> Int? {
        let text = value.trimmingCharacters(in: .whitespaces).lowercased()
        if let index = weekdayNames.firstIndex(where: { $0 == text || $0.prefix(3) == text }) { return index }
        if let number = Int(text) { return ((number % 7) + 7) % 7 }
        return nil
    }

    /// `toggledWeekStart`: between the two conventions people actually switch between. A
    /// calendar starting any other day lands on Monday the first time it is toggled.
    public static func toggledWeekStart(_ start: Int) -> Int {
        start == 1 ? 0 : 1
    }

    /// `weekdayOrder`: the seven weekdays from `start`.
    public static func weekdayOrder(start: Int) -> [Int] {
        (0..<7).map { (start + $0) % 7 }
    }

    /// The ISO 8601 week number of a date: the week owning the Thursday of its Monday-based
    /// week, which is what the clock's `ww` prints.
    public static func isoWeek(year: Int, month: Int, day: Int, calendar: Calendar = gregorian) -> Int {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return 0 }
        return iso.component(.weekOfYear, from: date)
    }

    /// `monthGrid`: six rows of seven days from the week holding the first of the month,
    /// starting on `weekStart`. Every row is numbered by the ISO week owning its Thursday —
    /// the definition itself for a Monday-start week, and the only answer that holds still for
    /// the other starts, where a row straddles two ISO weeks but shares Monday to Thursday
    /// with one of them.
    public static func monthGrid(_ view: View, weekStart: Int, today: DateComponents,
                                 calendar: Calendar = gregorian) -> [Week] {
        let start = ((weekStart % 7) + 7) % 7
        guard let first = calendar.date(from: DateComponents(year: view.year, month: view.month, day: 1)) else {
            return []
        }
        // `Calendar.weekday` is 1 for Sunday; the grid counts from 0.
        let leading = ((calendar.component(.weekday, from: first) - 1) - start + 7) % 7
        var cursor = calendar.date(byAdding: .day, value: -leading, to: first) ?? first
        var weeks: [Week] = []
        for _ in 0..<6 {
            var days: [Day] = []
            var thursday: DateComponents?
            for _ in 0..<7 {
                let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: cursor)
                let weekday = (parts.weekday ?? 1) - 1
                if weekday == 4 { thursday = parts }
                days.append(Day(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0,
                                inMonth: parts.month == view.month && parts.year == view.year,
                                weekend: weekday == 0 || weekday == 6,
                                today: parts.year == today.year && parts.month == today.month && parts.day == today.day))
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            }
            let anchor = thursday ?? calendar.dateComponents([.year, .month, .day], from: cursor)
            weeks.append(Week(number: isoWeek(year: anchor.year ?? 0, month: anchor.month ?? 0,
                                              day: anchor.day ?? 0, calendar: calendar), days: days))
        }
        return weeks
    }

    /// `stepMonth`: `delta` months on, carrying the year.
    public static func step(_ view: View, months delta: Int) -> View {
        let total = view.year * 12 + (view.month - 1) + delta
        let year = Int((Double(total) / 12).rounded(.down))
        return View(year: year, month: total - year * 12 + 1)
    }

    /// The month and year as the label under the grid prints them — "SEPTEMBER 2026" — in
    /// the caller's locale.
    public static func monthLabel(_ view: View, locale: Locale = .current, calendar: Calendar = gregorian) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMM yyyy", options: 0, locale: locale) ?? "MMMM yyyy"
        guard let date = calendar.date(from: DateComponents(year: view.year, month: view.month, day: 1)) else {
            return ""
        }
        return formatter.string(from: date).uppercased()
    }

    /// Two-letter weekday headings in the week's order, from the locale: "MO TU WE…" —
    /// upstream's `weekdayLabel`, the short name cut to two letters and upper-cased.
    public static func weekdayLabels(start: Int, locale: Locale = .current, calendar: Calendar = gregorian) -> [String] {
        var named = calendar
        named.locale = locale
        let symbols = named.shortWeekdaySymbols
        return weekdayOrder(start: start).map { String(symbols[$0].prefix(2)).uppercased() }
    }

    public static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    // MARK: - The rows

    /// The hero's date: "September 19", `Qt.formatDate(today, "MMMM d")` in the locale's order.
    public static func todayLabel(_ today: Date, locale: Locale = .current, calendar: Calendar = gregorian) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        return formatter.string(from: today)
    }

    /// The panel: the hero is today and — once the view has stepped away — the way back to it;
    /// the grid; the month under it with its chevrons; and the door to Calendar, where the
    /// clock's click went before the panel existed.
    public static func rows(view: View, weekStart: Int, today: Date, locale: Locale = .current,
                            calendar: Calendar = gregorian) -> [PanelRow] {
        let todayParts = calendar.dateComponents([.year, .month, .day], from: today)
        let viewingToday = todayParts.year == view.year && todayParts.month == view.month
        let grid = Grid(weekdays: weekdayLabels(start: weekStart, locale: locale, calendar: calendar),
                        weeks: monthGrid(view, weekStart: weekStart, today: todayParts, calendar: calendar))
        return [
            .hero(glyph: Glyphs.calendar, title: todayLabel(today, locale: locale, calendar: calendar),
                  status: viewingToday ? "Today" : "Back to today",
                  action: viewingToday ? .none : .today),
            // The grid is looked at, not landed on; its one control, the week-start toggle
            // on the `W` heading, is a click target `PanelLayout.calendarHit` finds. The month
            // line is where the keyboard lives: ←/→ step it, Return is today.
            PanelRow(.calendar(grid)),
            PanelRow(.monthNav(monthLabel(view, locale: locale, calendar: calendar)), action: .today),
            .separator,
            .action("Open Calendar…", .openCalendar),
        ]
    }
}
