import Combine
import Foundation

/// Countdown state machine. Time is tracked against an absolute end date, so the
/// countdown stays accurate across sleep and run-loop hiccups.
@MainActor
final class CountdownModel: ObservableObject {
    enum Phase: Equatable {
        case idle, running, paused, finished
    }

    static let hourRange = 0...23
    static let minuteRange = 0...59

    @Published private(set) var phase: Phase = .idle { didSet { onChange?() } }
    @Published private(set) var remainingSeconds = 0 { didSet { onChange?() } }
    @Published private(set) var totalSeconds = 0
    @Published private(set) var endDate: Date?

    /// The duration entered in the setup view, persisted between launches.
    /// (Reassigning a @Published property in its own didSet re-triggers the
    /// observer, so only clamp when out of range.)
    @Published var hours: Int {
        didSet {
            guard Self.hourRange.contains(hours) else { return hours = hours.clamped(to: Self.hourRange) }
            defaults?.set(hours, forKey: Keys.hours)
        }
    }
    @Published var minutes: Int {
        didSet {
            guard Self.minuteRange.contains(minutes) else { return minutes = minutes.clamped(to: Self.minuteRange) }
            defaults?.set(minutes, forKey: Keys.minutes)
        }
    }

    /// Called after anything shown in the menu bar changes.
    var onChange: (() -> Void)?
    /// Called once when a countdown reaches zero.
    var onFinish: (() -> Void)?

    private(set) var lastDuration = 0
    private var pausedRemaining: TimeInterval = 0
    private var ticker: Timer?
    private let now: () -> Date
    private let defaults: UserDefaults?

    private enum Keys {
        static let hours = "hours"
        static let minutes = "minutes"
    }

    init(now: @escaping () -> Date = Date.init, defaults: UserDefaults? = .standard) {
        self.now = now
        self.defaults = defaults
        if let defaults, defaults.object(forKey: Keys.minutes) != nil {
            hours = defaults.integer(forKey: Keys.hours).clamped(to: Self.hourRange)
            minutes = defaults.integer(forKey: Keys.minutes).clamped(to: Self.minuteRange)
        } else {
            hours = 0
            minutes = 25
        }
    }

    var enteredSeconds: Int { hours * 3600 + minutes * 60 }

    var progress: Double {
        totalSeconds > 0 ? Double(remainingSeconds) / Double(totalSeconds) : 0
    }

    // MARK: - Actions

    /// Starts a countdown using the hours and minutes entered in the setup view.
    func start() {
        start(seconds: enteredSeconds)
    }

    func start(seconds: Int) {
        guard seconds > 0 else { return }
        lastDuration = seconds
        totalSeconds = seconds
        endDate = now().addingTimeInterval(TimeInterval(seconds))
        phase = .running
        startTicker()
        tick()
    }

    func pause() {
        guard phase == .running, let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSince(now()))
        self.endDate = nil
        stopTicker()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        endDate = now().addingTimeInterval(pausedRemaining)
        phase = .running
        startTicker()
        tick()
    }

    func togglePause() {
        phase == .paused ? resume() : pause()
    }

    /// Extends a running or paused countdown, or starts a new one ("snooze") otherwise.
    func add(minutes extra: Int) {
        let seconds = extra * 60
        switch phase {
        case .running:
            endDate = endDate?.addingTimeInterval(TimeInterval(seconds))
            totalSeconds += seconds
            tick()
        case .paused:
            pausedRemaining += TimeInterval(seconds)
            totalSeconds += seconds
            remainingSeconds = Int(pausedRemaining.rounded(.up))
        case .idle, .finished:
            start(seconds: seconds)
        }
    }

    func restart() {
        start(seconds: lastDuration)
    }

    func cancel() {
        reset()
    }

    /// Acknowledges a finished countdown.
    func dismiss() {
        guard phase == .finished else { return }
        reset()
    }

    /// Recomputes the remaining time from the clock. Driven by the ticker.
    func tick() {
        guard phase == .running, let endDate else { return }
        let remaining = endDate.timeIntervalSince(now())
        if remaining <= 0 {
            stopTicker()
            self.endDate = nil
            remainingSeconds = 0
            phase = .finished
            onFinish?()
        } else {
            let seconds = Int(remaining.rounded(.up))
            if seconds != remainingSeconds { remainingSeconds = seconds }
        }
    }

    private func reset() {
        stopTicker()
        endDate = nil
        pausedRemaining = 0
        remainingSeconds = 0
        totalSeconds = 0
        phase = .idle
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        // .common keeps the countdown updating while menus are being tracked.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - Formatting

    /// "4:05", "25:00", "1:30:00".
    static func format(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    /// "25 min", "1 hr", "1 hr 30 min".
    static func describe(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) hr"
        default: return "\(h) hr \(m) min"
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
