import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: CountdownModel
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        VStack(spacing: 16) {
            switch model.phase {
            case .idle: SetupView(model: model)
            case .running, .paused: RunningView(model: model)
            case .finished: FinishedView(model: model)
            }

            Divider()

            HStack {
                Toggle("Launch at login", isOn: $loginItem.isEnabled)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 300)
    }
}

// MARK: - Idle

private struct SetupView: View {
    @ObservedObject var model: CountdownModel

    private static let presets: [(label: String, minutes: Int)] = [
        ("5m", 5), ("10m", 10), ("15m", 15), ("25m", 25),
        ("30m", 30), ("45m", 45), ("1h", 60), ("2h", 120),
    ]

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 6) {
                NumberField(value: $model.hours, range: CountdownModel.hourRange, unit: "hours")
                Text(":")
                    .font(.system(size: 36, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 22)
                NumberField(value: $model.minutes, range: CountdownModel.minuteRange, unit: "minutes")
            }

            Button {
                model.start()
            } label: {
                Text("Start").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.enteredSeconds == 0)

            VStack(alignment: .leading, spacing: 6) {
                Text("Quick start")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(Self.presets, id: \.minutes) { preset in
                        Button {
                            model.start(seconds: preset.minutes * 60)
                        } label: {
                            Text(preset.label).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

/// A large editable number with up/down steppers.
private struct NumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    /// Parses on every keystroke so the model always holds what's on screen,
    /// even if Return is pressed before the field commits.
    private var text: Binding<String> {
        Binding(
            get: { String(value) },
            set: { newValue in
                let digits = String(newValue.filter(\.isNumber).suffix(2))
                value = (Int(digits) ?? 0).clamped(to: range)
            }
        )
    }

    var body: some View {
        VStack(spacing: 2) {
            stepButton("chevron.up", by: 1)
            TextField("0", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 36, weight: .light, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(width: 72)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                .onKeyPress(.upArrow) { step(1); return .handled }
                .onKeyPress(.downArrow) { step(-1); return .handled }
            stepButton("chevron.down", by: -1)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func stepButton(_ symbol: String, by delta: Int) -> some View {
        Button { step(delta) } label: {
            Image(systemName: symbol)
                .frame(width: 72, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .buttonRepeatBehavior(.enabled)
        .foregroundStyle(.secondary)
    }

    /// Steps with wrap-around, like a clock.
    private func step(_ delta: Int) {
        let count = range.count
        value = range.lowerBound + ((value - range.lowerBound + delta) % count + count) % count
    }
}

// MARK: - Running / paused

private struct RunningView: View {
    @ObservedObject var model: CountdownModel

    private var isPaused: Bool { model.phase == .paused }

    var body: some View {
        VStack(spacing: 12) {
            Text(CountdownModel.format(model.remainingSeconds))
                .font(.system(size: 48, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(isPaused ? .secondary : .primary)
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: model.remainingSeconds)

            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .tint(isPaused ? .secondary : .accentColor)

            Group {
                if isPaused {
                    Text("Paused")
                } else if let endDate = model.endDate {
                    Text("Ends at \(endDate, format: .dateTime.hour().minute())")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    model.togglePause()
                } label: {
                    Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button("+1m") { model.add(minutes: 1) }
                Button("+5m") { model.add(minutes: 5) }

                Button(role: .destructive) {
                    model.cancel()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Cancel timer")
                .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
        }
    }
}

// MARK: - Finished

private struct FinishedView: View {
    @ObservedObject var model: CountdownModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
                .symbolEffect(.bounce, options: .repeat(3))
            Text("Time's up!")
                .font(.title2.bold())
            Text("Your \(CountdownModel.describe(model.lastDuration)) timer finished.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Snooze 5m") { model.add(minutes: 5) }
                Button("Restart") { model.restart() }
                Button {
                    model.dismiss()
                } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
    }
}
