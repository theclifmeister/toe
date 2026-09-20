import Foundation

/// The last minute of traffic on the network panel's link — the graph row's value.
///
/// toe's own row, with no upstream to port: Omarchy's `panels/network/Panel.qml` shows the
/// connection's numbers and never its traffic, so this is the panel's `About` — one thing
/// worth showing that the tree has no place for (#189). What it holds is a ring of the last
/// sixty per-second rates, down and up, in bytes per second, fed raw interface byte counters
/// and told to work out the rest. The counters are the provider's to read (`sysctl
/// NET_RT_IFLIST2`, whose `if_data64` does not wrap every 4 GiB the way `getifaddrs`'s
/// 32-bit `if_data` does); everything from the reading on is here, so the selftest can feed
/// a minute of readings and check every sample without an interface in sight.
///
/// The model holds whole samples and nothing in between. The view glides the trace across
/// the second between two samples — that is interpolation, and it is the view's, so a sample
/// is either in the ring or not yet taken and the numbers the label prints are the ones the
/// graph is drawn from.
public struct NetworkTraffic: Equatable, Sendable {

    /// One read of an interface's counters: which interface, its lifetime bytes in and out,
    /// and the provider's clock in seconds when it read them. The clock is the caller's —
    /// seconds of uptime, or anything monotonic; nothing here reads a wall clock, and a wall
    /// clock that jumped at an NTP sync would make one rate a lie.
    public struct Reading: Equatable, Sendable {
        public var interface: String
        public var inBytes: UInt64
        public var outBytes: UInt64
        public var at: Double

        public init(interface: String, inBytes: UInt64, outBytes: UInt64, at: Double) {
            self.interface = interface
            self.inBytes = inBytes
            self.outBytes = outBytes
            self.at = at
        }
    }

    /// One second of the link: bytes per second down and up.
    public struct Sample: Equatable, Sendable {
        public var down: Double
        public var up: Double

        public init(down: Double, up: Double) {
            self.down = down
            self.up = up
        }
    }

    /// What the graph row carries: the samples oldest first, never more than `capacity` of
    /// them, and the scale they are drawn against.
    public struct Window: Equatable, Sendable {
        /// Sixty seconds is the window, whatever the panel's width: a narrower panel draws
        /// fewer points per sample, not fewer seconds.
        public static let capacity = 60
        /// The least the top of the graph stands for, in bytes per second. Without a floor an
        /// idle link's keep-alives — a few hundred bytes a second — are blown up to fill the
        /// row and read as traffic; with one they are a flat line along the bottom, and a
        /// download stands as tall as it is. Ten kilobytes is under any real transfer and over
        /// the chatter.
        public static let scaleFloor: Double = 10_000

        public var samples: [Sample]

        public init(samples: [Sample] = []) {
            self.samples = Array(samples.suffix(Self.capacity))
        }

        /// The busiest second in the window, in either direction.
        public var peak: Double {
            samples.reduce(0) { max($0, $1.down, $1.up) }
        }

        /// The value the top of the graph stands for: the window's own maximum, floored.
        public var scale: Double { max(peak, Self.scaleFloor) }

        /// The most recent second, or nil before the first delta.
        public var current: Sample? { samples.last }

        /// What the label over the graph says: "↓ 1.3 MB/s ↑ 48 kB/s". With nothing measured
        /// yet the numbers are dashes, as `NetworkPanel.rateLabel` prints a rate it has not
        /// got, rather than a zero that claims the link is idle.
        public var downLabel: String { "\u{2193} " + (current.map { NetworkTraffic.rateLabel($0.down) } ?? "\u{2014}") }
        public var upLabel: String { "\u{2191} " + (current.map { NetworkTraffic.rateLabel($0.up) } ?? "\u{2014}") }
        public var label: String { downLabel + " " + upLabel }
    }

    public private(set) var window = Window()
    private var last: Reading?

    public init() {}

    /// A reading from the provider, once a second. The first after a start has nothing to
    /// compare with and adds no sample — the graph starts empty on the right and fills
    /// leftwards, rather than opening on sixty seconds of zeroes pretending to be history.
    ///
    /// Two things a counter does that are not traffic. A counter that goes *backwards* is an
    /// interface that went down and came up, or was replaced under the same name, and its
    /// counters started over; the delta would be a huge negative number. That second is
    /// recorded as zero and the ring is kept — the minute before it still happened. And a
    /// reading from a *different interface* — Wi-Fi dropped and Ethernet took over, `en0`
    /// to `en5` — starts a fresh ring: `en5`'s lifetime bytes against `en0`'s last are a spike
    /// from nowhere, and the minute before it was another link's.
    public mutating func push(_ reading: Reading) {
        defer { last = reading }
        guard let last, last.interface == reading.interface else {
            if last != nil { window = Window() }
            return
        }
        let seconds = reading.at - last.at
        // A reading with no time behind it — the same tick delivered twice, or a clock that
        // did not move — has no rate in it; the counters are remembered and the sample skipped.
        guard seconds > 0 else { return }
        let down = reading.inBytes >= last.inBytes ? Double(reading.inBytes - last.inBytes) / seconds : 0
        let up = reading.outBytes >= last.outBytes ? Double(reading.outBytes - last.outBytes) / seconds : 0
        window.samples.append(Sample(down: down, up: up))
        if window.samples.count > Window.capacity {
            window.samples.removeFirst(window.samples.count - Window.capacity)
        }
    }

    /// "0 B/s", "812 B/s", "48 kB/s", "1.3 MB/s", "1.0 GB/s". Decimal units, as
    /// `NetworkPanel.rateLabel` goes to Gbit at 1000 — a link's rate is quoted in powers of
    /// ten, and a graph beside it should agree with the number it stands under. No decimal
    /// below a megabyte, where a tenth of a kilobyte is noise; one from there up, where "1 MB/s"
    /// and "1.9 MB/s" are different downloads. A rate that rounds up to the next unit's floor
    /// moves up a unit rather than printing "1000 kB/s".
    public static func rateLabel(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        if value < 1000 { return "\(Int(value.rounded())) B/s" }
        let kilo = (value / 1000).rounded()
        if kilo < 1000 { return "\(Int(kilo)) kB/s" }
        let mega = value / 1_000_000
        if (mega * 10).rounded() < 10_000 { return String(format: "%.1f MB/s", mega) }
        return String(format: "%.1f GB/s", value / 1_000_000_000)
    }
}
