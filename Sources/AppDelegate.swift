import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = CountdownModel()
    private let loginItem = LoginItem()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var alarm: Timer?

    private let titleFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hosting = NSHostingController(rootView: PopoverView(model: model, loginItem: loginItem))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        model.onChange = { [weak self] in self?.updateStatusItem() }
        model.onFinish = { [weak self] in self?.timerFinished() }
        updateStatusItem()

        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared
        NotificationDelegate.shared.onOpen = { [weak self] in self?.showPopover() }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Status item

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        let symbol: String
        var title: String?
        switch model.phase {
        case .idle:
            symbol = "timer"
        case .running:
            symbol = "timer"
            title = CountdownModel.format(model.remainingSeconds)
        case .paused:
            symbol = "pause.circle"
            title = CountdownModel.format(model.remainingSeconds)
        case .finished:
            symbol = "bell.fill"
            title = "Time's up"
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Countdown")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = title == nil ? .imageOnly : .imageLeading
        button.attributedTitle = NSAttributedString(
            string: title.map { " " + $0 } ?? "",
            attributes: [.font: titleFont])
        button.appearsDisabled = model.phase == .paused
        button.toolTip = title.map { "Countdown – \($0)" } ?? "Countdown"
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        stopAlarm()
        loginItem.refresh()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        // Closing the popover counts as acknowledging a finished timer.
        model.dismiss()
    }

    // MARK: - Right-click menu

    private func showContextMenu() {
        popover.performClose(nil)
        let menu = NSMenu()

        switch model.phase {
        case .running, .paused:
            menu.addItem(item(model.phase == .paused ? "Resume" : "Pause", #selector(togglePause)))
            menu.addItem(item("Add 5 Minutes", #selector(addFive)))
            menu.addItem(item("Cancel Timer", #selector(cancelTimer)))
        case .finished:
            menu.addItem(item("Snooze 5 Minutes", #selector(addFive)))
            menu.addItem(item("Restart", #selector(restartTimer)))
            menu.addItem(item("Done", #selector(dismissTimer)))
        case .idle:
            let title = "Start \(CountdownModel.describe(model.enteredSeconds))"
            let start = item(title, #selector(startTimer))
            start.isEnabled = model.enteredSeconds > 0
            menu.addItem(start)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Countdown", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func startTimer() { model.start() }
    @objc private func togglePause() { model.togglePause() }
    @objc private func addFive() { stopAlarm(); model.add(minutes: 5) }
    @objc private func cancelTimer() { model.cancel() }
    @objc private func restartTimer() { stopAlarm(); model.restart() }
    @objc private func dismissTimer() { stopAlarm(); model.dismiss() }

    // MARK: - Completion

    private func timerFinished() {
        postNotification()
        startAlarm()
    }

    private func postNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Time's up!"
        content.body = "Your \(CountdownModel.describe(model.lastDuration)) timer has finished."
        // Sound comes from the alarm below so it plays even if notifications are off.
        let request = UNNotificationRequest(identifier: "countdown.finished", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Plays the chime a few times, stopping early once the user responds.
    private func startAlarm() {
        stopAlarm()
        var plays = 0
        let ring = { [weak self] in
            guard let self, self.model.phase == .finished, plays < 5 else {
                self?.stopAlarm()
                return
            }
            plays += 1
            NSSound(named: "Glass")?.play()
        }
        ring()
        alarm = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated { ring() }
        }
    }

    private func stopAlarm() {
        alarm?.invalidate()
        alarm = nil
    }
}

/// Shows banners while the app is active and opens the popover when one is clicked.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()
    @MainActor var onOpen: (() -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in self.onOpen?() }
        completionHandler()
    }
}
