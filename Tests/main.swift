import Foundation

// Minimal test runner for CountdownModel (no XCTest needed, so it builds with
// just the Command Line Tools). Run with `make test`.

final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now += seconds }
}

var failures = 0
var checks = 0

func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", line: Int = #line) {
    checks += 1
    if actual != expected {
        failures += 1
        print("  ✗ line \(line): expected \(expected), got \(actual) \(message)")
    }
}

@MainActor
func test(_ name: String, _ body: (CountdownModel, FakeClock) -> Void) {
    let clock = FakeClock()
    let model = CountdownModel(now: { clock.now }, defaults: nil)
    let before = failures
    body(model, clock)
    model.cancel()
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}

MainActor.assumeIsolated {
    test("formats durations") { _, _ in
        expect(CountdownModel.format(0), "0:00")
        expect(CountdownModel.format(59), "0:59")
        expect(CountdownModel.format(60), "1:00")
        expect(CountdownModel.format(1500), "25:00")
        expect(CountdownModel.format(3599), "59:59")
        expect(CountdownModel.format(3600), "1:00:00")
        expect(CountdownModel.format(5025), "1:23:45")
        expect(CountdownModel.format(-5), "0:00")
        expect(CountdownModel.describe(1500), "25 min")
        expect(CountdownModel.describe(3600), "1 hr")
        expect(CountdownModel.describe(5400), "1 hr 30 min")
    }

    test("defaults to 25 minutes and clamps input") { model, _ in
        expect(model.hours, 0)
        expect(model.minutes, 25)
        model.hours = 30
        expect(model.hours, 23)
        model.minutes = 75
        expect(model.minutes, 59)
        model.minutes = -4
        expect(model.minutes, 0)
    }

    test("starting with zero duration does nothing") { model, _ in
        model.hours = 0
        model.minutes = 0
        model.start()
        expect(model.phase, .idle)
    }

    test("counts down from hours and minutes") { model, clock in
        model.hours = 1
        model.minutes = 30
        model.start()
        expect(model.phase, .running)
        expect(model.remainingSeconds, 5400)
        expect(model.totalSeconds, 5400)
        expect(model.endDate, clock.now + 5400)

        clock.advance(0.5)
        model.tick()
        expect(model.remainingSeconds, 5400, "(rounds up partial seconds)")

        clock.advance(0.5)
        model.tick()
        expect(model.remainingSeconds, 5399)

        clock.advance(3599)
        model.tick()
        expect(model.remainingSeconds, 1800)
        expect(model.progress, 1800.0 / 5400.0)
    }

    test("pause freezes the countdown and resume continues it") { model, clock in
        model.start(seconds: 600)
        clock.advance(10)
        model.tick()
        model.pause()
        expect(model.phase, .paused)
        expect(model.remainingSeconds, 590)
        expect(model.endDate, nil)

        clock.advance(1000)
        model.tick()
        expect(model.phase, .paused)
        expect(model.remainingSeconds, 590)

        model.resume()
        expect(model.phase, .running)
        expect(model.remainingSeconds, 590)
        clock.advance(5)
        model.tick()
        expect(model.remainingSeconds, 585)
    }

    test("adding time extends running and paused timers") { model, clock in
        model.start(seconds: 60)
        model.add(minutes: 5)
        expect(model.remainingSeconds, 360)
        expect(model.totalSeconds, 360)

        clock.advance(60)
        model.tick()
        model.pause()
        model.add(minutes: 1)
        expect(model.remainingSeconds, 360)
        expect(model.totalSeconds, 420)
    }

    test("finishes exactly once at zero") { model, clock in
        var finishCount = 0
        model.onFinish = { finishCount += 1 }
        model.start(seconds: 60)
        clock.advance(59.9)
        model.tick()
        expect(model.remainingSeconds, 1)
        expect(model.phase, .running)

        clock.advance(0.1)
        model.tick()
        expect(model.phase, .finished)
        expect(model.remainingSeconds, 0)
        expect(finishCount, 1)

        clock.advance(10)
        model.tick()
        expect(finishCount, 1)
    }

    test("finishes after sleeping past the end time") { model, clock in
        var finished = false
        model.onFinish = { finished = true }
        model.start(seconds: 300)
        clock.advance(3600)
        model.tick()
        expect(finished, true)
        expect(model.phase, .finished)
    }

    test("snooze, restart and dismiss after finishing") { model, clock in
        model.start(seconds: 120)
        clock.advance(120)
        model.tick()
        expect(model.phase, .finished)

        model.add(minutes: 5)
        expect(model.phase, .running)
        expect(model.remainingSeconds, 300)

        clock.advance(300)
        model.tick()
        model.start(seconds: 120)
        clock.advance(120)
        model.tick()
        model.restart()
        expect(model.phase, .running)
        expect(model.remainingSeconds, 120)

        clock.advance(120)
        model.tick()
        model.dismiss()
        expect(model.phase, .idle)
    }

    test("dismiss only affects finished timers") { model, _ in
        model.start(seconds: 60)
        model.dismiss()
        expect(model.phase, .running)
    }

    test("cancel resets to idle") { model, _ in
        model.start(seconds: 60)
        model.cancel()
        expect(model.phase, .idle)
        expect(model.remainingSeconds, 0)
        expect(model.progress, 0)
    }

    test("notifies on visible changes") { model, clock in
        var changes = 0
        model.onChange = { changes += 1 }
        model.start(seconds: 60)
        let afterStart = changes
        expect(afterStart > 0, true)

        clock.advance(0.2)
        model.tick()
        expect(changes, afterStart, "(no change within the same second)")

        clock.advance(1)
        model.tick()
        expect(changes, afterStart + 1)
    }

    test("persists the entered duration") { _, _ in
        let suite = "dev.lar.Countdown.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = CountdownModel(defaults: defaults)
        first.hours = 2
        first.minutes = 15
        let second = CountdownModel(defaults: defaults)
        expect(second.hours, 2)
        expect(second.minutes, 15)
        defaults.removePersistentDomain(forName: suite)
    }
}

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
