import Cocoa
import SwiftUI

// MARK: - Terminal Window Controller

class TerminalWindowController {
    var windowController: NSWindowController?
    var textView: NSTextView?
    var scrollView: NSScrollView?

    // Create a terminal window for displaying brew command output
    func createWindow() -> NSWindow {
        // Create a window to display brew command output
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        // Configure window
        window.title = "Homebrew Update"
        window.center()
        window.setFrameAutosaveName("HomebrewOutputWindow")
        window.minSize = NSSize(width: 400, height: 300)

        // Create a scrollable text view
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        scrollView?.hasVerticalScroller = true
        scrollView?.hasHorizontalScroller = true
        scrollView?.autohidesScrollers = true

        // Create the text view for displaying output
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        textView?.isEditable = false
        textView?.isSelectable = true
        textView?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView?.textColor = NSColor.textColor
        textView?.backgroundColor = NSColor.textBackgroundColor
        textView?.autoresizingMask = [.width, .height]

        // Set up the scroll view with the text view
        scrollView?.documentView = textView

        // Add a close button at the bottom
        let closeButton = NSButton(frame: NSRect(x: window.frame.width - 110, y: 10, width: 100, height: 32))
        closeButton.title = "Close"
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeWindow)

        // Create the container view for the window content
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))

        // Add the scroll view to the container
        if let scrollView {
            scrollView.frame = NSRect(x: 0, y: 50, width: containerView.frame.width, height: containerView.frame.height - 50)
            scrollView.autoresizingMask = [.width, .height]
            containerView.addSubview(scrollView)
        }

        // Add the close button to the container
        closeButton.frame = NSRect(x: containerView.frame.width - 110, y: 10, width: 100, height: 32)
        closeButton.autoresizingMask = [.minXMargin, .maxYMargin]
        containerView.addSubview(closeButton)

        // Set the container as the window's content view
        window.contentView = containerView

        return window
    }

    // Show the terminal window
    func showWindow() {
        // Create the window if it doesn't exist
        if windowController == nil {
            let window = createWindow()
            windowController = NSWindowController(window: window)
        }

        // Clear previous output
        textView?.string = ""

        // Show the window
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Close the window
    @objc func closeWindow() {
        windowController?.close()
    }

    // Append text to the terminal output
    func appendOutput(_ text: String, color: NSColor = NSColor.textColor) {
        DispatchQueue.main.async {
            guard let textView = self.textView else { return }

            // Create attributed string with the specified color
            let attributedString = NSAttributedString(
                string: text,
                attributes: [
                    .foregroundColor: color,
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                ]
            )

            // Get the current text storage
            let textStorage = textView.textStorage!

            // Append the new text
            textStorage.append(attributedString)

            // Scroll to the end
            textView.scrollToEndOfDocument(nil)
        }
    }
}

// MARK: - Preferences Window Controller

class PreferencesWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    weak var appDelegate: AppDelegate?
    var windowController: NSWindowController?

    // Properties for custom intervals UI
    private var customIntervalsTable: NSTableView?
    private var customIntervalNameField: NSTextField?
    private var customIntervalSecondsField: NSTextField?
    private var customIntervals: [(name: String, interval: TimeInterval)] = []

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
    }

    func showWindow() {
        if windowController == nil {
            let window = createPreferencesWindow()
            windowController = NSWindowController(window: window)
        }

        // Load custom intervals before showing the window
        loadCustomIntervalsIntoTable()

        // Show the window
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func createPreferencesWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        // Configure window
        window.title = "BrewBar Settings"
        window.center()
        window.setFrameAutosaveName("PreferencesWindow")
        window.minSize = NSSize(width: 500, height: 550)

        // Create a tab view to organize settings
        let tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 600, height: 650))
        tabView.translatesAutoresizingMaskIntoConstraints = false

        // Create tabs
        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = "General"
        generalTab.view = createGeneralTabView()

        let commandsTab = NSTabViewItem(identifier: "commands")
        commandsTab.label = "Commands"
        commandsTab.view = createCommandsTabView()

        // Add tabs to the tab view
        tabView.addTabViewItem(generalTab)
        tabView.addTabViewItem(commandsTab)

        // Add the tab view to the window
        window.contentView?.addSubview(tabView)

        // Set up constraints
        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
                tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
                tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
                tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
            ])
        }

        return window
    }

    // Create the general tab view
    func createGeneralTabView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 600))

        // Create a container for better padding
        let container = NSView(frame: NSRect(x: 20, y: 20, width: 540, height: 560))
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        // Setup constraints for container
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])

        // Title
        let titleLabel = NSTextField(labelWithString: "General Settings")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        // Check Interval Group
        let refreshIntervalLabel = NSTextField(labelWithString: "Update Check Interval:")
        refreshIntervalLabel.font = NSFont.systemFont(ofSize: 13)
        refreshIntervalLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(refreshIntervalLabel)

        // Create popup for interval selection
        let intervalPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        intervalPopup.translatesAutoresizingMaskIntoConstraints = false
        intervalPopup.tag = 2001  // Tag for easy retrieval
        container.addSubview(intervalPopup)

        // Get current interval from app delegate
        if let appDelegate {
            // Add all interval options to the popup
            for (name, interval) in appDelegate.intervalOptions.sorted(by: { $0.value < $1.value }) {
                intervalPopup.addItem(withTitle: name)
                intervalPopup.lastItem?.representedObject = interval
            }

            // Set the current selection
            let currentInterval = appDelegate.getCurrentInterval()
            for (index, item) in intervalPopup.itemArray.enumerated() {
                if let itemInterval = item.representedObject as? TimeInterval, itemInterval == currentInterval {
                    intervalPopup.selectItem(at: index)
                    break
                }
            }

            // Set the action
            intervalPopup.target = appDelegate
            intervalPopup.action = #selector(AppDelegate.setInterval(_:))

            // Add notification observer for preference changes (if not already added)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(updateIntervalPopup),
                                                   name: NSNotification.Name("IntervalChanged"),
                                                   object: nil)
        }

        // Custom Intervals Section
        let customIntervalsSectionLabel = NSTextField(labelWithString: "Custom Update Intervals")
        customIntervalsSectionLabel.font = NSFont.boldSystemFont(ofSize: 13)
        customIntervalsSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(customIntervalsSectionLabel)

        // Description for custom intervals
        let customIntervalsDescLabel = NSTextField(labelWithString: "Add custom check intervals by specifying a name and time in seconds:")
        customIntervalsDescLabel.font = NSFont.systemFont(ofSize: 12)
        customIntervalsDescLabel.textColor = NSColor.secondaryLabelColor
        customIntervalsDescLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(customIntervalsDescLabel)

        // Form for adding custom intervals
        let nameLabel = NSTextField(labelWithString: "Name:")
        nameLabel.font = NSFont.systemFont(ofSize: 12)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLabel)

        customIntervalNameField = NSTextField(frame: .zero)
        customIntervalNameField?.placeholderString = "e.g. Every 12 Hours"
        customIntervalNameField?.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(customIntervalNameField!)

        let secondsLabel = NSTextField(labelWithString: "Seconds:")
        secondsLabel.font = NSFont.systemFont(ofSize: 12)
        secondsLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(secondsLabel)

        customIntervalSecondsField = NSTextField(frame: .zero)
        customIntervalSecondsField?.placeholderString = "e.g. 43200 (for 12 hours)"
        customIntervalSecondsField?.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(customIntervalSecondsField!)

        let addButton = NSButton(title: "Add Interval", target: self, action: #selector(addCustomInterval))
        addButton.bezelStyle = .rounded
        addButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(addButton)

        // Table view for custom intervals
        let scrollView = NSScrollView(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        container.addSubview(scrollView)

        let tableView = NSTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("nameColumn"))
        nameColumn.title = "Name"
        nameColumn.minWidth = 150
        nameColumn.width = 200
        tableView.addTableColumn(nameColumn)

        let intervalColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("intervalColumn"))
        intervalColumn.title = "Seconds"
        intervalColumn.minWidth = 80
        intervalColumn.width = 100
        tableView.addTableColumn(intervalColumn)

        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("actionColumn"))
        actionColumn.title = "Action"
        actionColumn.minWidth = 80
        actionColumn.width = 80
        tableView.addTableColumn(actionColumn)

        scrollView.documentView = tableView
        customIntervalsTable = tableView

        // Login at startup checkbox
        let loginItemCheckbox = NSButton(checkboxWithTitle: "Start BrewBar when you log in", target: appDelegate, action: #selector(AppDelegate.toggleLoginItem(_:)))
        loginItemCheckbox.state = appDelegate?.isLoginItemEnabled() ?? false ? .on : .off
        loginItemCheckbox.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(loginItemCheckbox)

        // Notifications checkbox
        let notificationsCheckbox = NSButton(checkboxWithTitle: "Show notifications when updates are available", target: appDelegate, action: #selector(AppDelegate.toggleNotifications(_:)))
        notificationsCheckbox.state = NotificationManager.shared.notificationsEnabled() ? .on : .off
        notificationsCheckbox.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(notificationsCheckbox)

        // Debug logs section
        let logsFolderLabel = NSTextField(labelWithString: "Debug & Diagnostics")
        logsFolderLabel.font = NSFont.boldSystemFont(ofSize: 13)
        logsFolderLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(logsFolderLabel)

        let openLogsButton = NSButton(title: "Open Logs Folder", target: appDelegate, action: #selector(AppDelegate.openLogsFolder))
        openLogsButton.bezelStyle = .rounded
        openLogsButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(openLogsButton)

        // Constraints for title
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        ])

        // Constraints for interval selection
        NSLayoutConstraint.activate([
            refreshIntervalLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            refreshIntervalLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            intervalPopup.centerYAnchor.constraint(equalTo: refreshIntervalLabel.centerYAnchor),
            intervalPopup.leadingAnchor.constraint(equalTo: refreshIntervalLabel.trailingAnchor, constant: 10),
            intervalPopup.widthAnchor.constraint(equalToConstant: 200)
        ])

        // Constraints for custom intervals section
        NSLayoutConstraint.activate([
            customIntervalsSectionLabel.topAnchor.constraint(equalTo: refreshIntervalLabel.bottomAnchor, constant: 30),
            customIntervalsSectionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            customIntervalsDescLabel.topAnchor.constraint(equalTo: customIntervalsSectionLabel.bottomAnchor, constant: 5),
            customIntervalsDescLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            customIntervalsDescLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            nameLabel.topAnchor.constraint(equalTo: customIntervalsDescLabel.bottomAnchor, constant: 15),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            customIntervalNameField!.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            customIntervalNameField!.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 10),
            customIntervalNameField!.widthAnchor.constraint(equalToConstant: 150),

            secondsLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            secondsLabel.leadingAnchor.constraint(equalTo: customIntervalNameField!.trailingAnchor, constant: 15),

            customIntervalSecondsField!.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            customIntervalSecondsField!.leadingAnchor.constraint(equalTo: secondsLabel.trailingAnchor, constant: 10),
            customIntervalSecondsField!.widthAnchor.constraint(equalToConstant: 100),

            addButton.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 10),
            addButton.trailingAnchor.constraint(equalTo: customIntervalSecondsField!.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 150)
        ])

        // Constraints for login and notification options
        NSLayoutConstraint.activate([
            loginItemCheckbox.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 20),
            loginItemCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            notificationsCheckbox.topAnchor.constraint(equalTo: loginItemCheckbox.bottomAnchor, constant: 10),
            notificationsCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        ])

        // Constraints for debug section
        NSLayoutConstraint.activate([
            logsFolderLabel.topAnchor.constraint(equalTo: notificationsCheckbox.bottomAnchor, constant: 30),
            logsFolderLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            openLogsButton.topAnchor.constraint(equalTo: logsFolderLabel.bottomAnchor, constant: 10),
            openLogsButton.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        ])

        return view
    }

    // Create the commands tab view
    func createCommandsTabView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 600))

        // Create a container for better padding
        let container = NSView(frame: NSRect(x: 20, y: 20, width: 540, height: 560))
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        // Setup constraints for container
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])

        // Title
        let titleLabel = NSTextField(labelWithString: "Homebrew Commands")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        // Description
        let descriptionLabel = NSTextField(labelWithString: "Customize the commands used for updating and upgrading Homebrew packages.")
        descriptionLabel.font = NSFont.systemFont(ofSize: 12)
        descriptionLabel.textColor = NSColor.secondaryLabelColor
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(descriptionLabel)

        // Update Command Group
        let updateCommandLabel = NSTextField(labelWithString: "Update Command:")
        updateCommandLabel.font = NSFont.systemFont(ofSize: 13)
        updateCommandLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(updateCommandLabel)

        let updateCommandField = NSTextField(frame: .zero)
        updateCommandField.placeholderString = "Example: update"
        updateCommandField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(updateCommandField)

        // Set the current value
        let updateCommands = BrewBarManager.shared.updateCommand
        if !updateCommands.isEmpty {
            updateCommandField.stringValue = updateCommands.joined(separator: " ")
        } else {
            updateCommandField.stringValue = BrewBarManager.shared.defaultUpdateCommand.joined(separator: " ")
        }

        // Upgrade Command Group
        let upgradeCommandLabel = NSTextField(labelWithString: "Upgrade Command:")
        upgradeCommandLabel.font = NSFont.systemFont(ofSize: 13)
        upgradeCommandLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(upgradeCommandLabel)

        let upgradeCommandField = NSTextField(frame: .zero)
        upgradeCommandField.placeholderString = "Example: upgrade"
        upgradeCommandField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(upgradeCommandField)

        // Set the current value
        let upgradeCommands = BrewBarManager.shared.upgradeCommand
        if !upgradeCommands.isEmpty {
            upgradeCommandField.stringValue = upgradeCommands.joined(separator: " ")
        } else {
            upgradeCommandField.stringValue = BrewBarManager.shared.defaultUpgradeCommand.joined(separator: " ")
        }

        // Help Text
        let helpText = NSTextField(wrappingLabelWithString: "Enter the brew commands without the 'brew' prefix. Use spaces to separate command arguments. For example, use 'upgrade --greedy' to perform greedy upgrades.")
        helpText.font = NSFont.systemFont(ofSize: 12)
        helpText.textColor = NSColor.secondaryLabelColor
        helpText.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(helpText)

        // Save Button
        let saveButton = NSButton(title: "Save Commands", target: self, action: #selector(saveBrewCommands))
        saveButton.bezelStyle = .rounded
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(saveButton)

        // Reset Button
        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetBrewCommands))
        resetButton.bezelStyle = .rounded
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(resetButton)

        // Tag the text fields so we can access them in the action methods
        updateCommandField.tag = 1001
        upgradeCommandField.tag = 1002

        // Constraints for title and description
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            descriptionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        // Constraints for update command
        NSLayoutConstraint.activate([
            updateCommandLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 20),
            updateCommandLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            updateCommandField.topAnchor.constraint(equalTo: updateCommandLabel.bottomAnchor, constant: 5),
            updateCommandField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            updateCommandField.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        // Constraints for upgrade command
        NSLayoutConstraint.activate([
            upgradeCommandLabel.topAnchor.constraint(equalTo: updateCommandField.bottomAnchor, constant: 15),
            upgradeCommandLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            upgradeCommandField.topAnchor.constraint(equalTo: upgradeCommandLabel.bottomAnchor, constant: 5),
            upgradeCommandField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            upgradeCommandField.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        // Constraints for help text
        NSLayoutConstraint.activate([
            helpText.topAnchor.constraint(equalTo: upgradeCommandField.bottomAnchor, constant: 15),
            helpText.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            helpText.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        // Constraints for buttons
        NSLayoutConstraint.activate([
            saveButton.topAnchor.constraint(equalTo: helpText.bottomAnchor, constant: 20),
            saveButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            resetButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            resetButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -10)
        ])

        return view
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return customIntervals.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < customIntervals.count else { return nil }

        let cellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "Cell")

        if tableColumn?.identifier.rawValue == "nameColumn" {
            let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView ?? NSTableCellView(frame: .zero)
            cell.identifier = cellIdentifier

            if cell.textField == nil {
                let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: tableColumn?.width ?? 100, height: 17))
                textField.isBordered = false
                textField.isEditable = false
                textField.drawsBackground = false
                cell.addSubview(textField)
                cell.textField = textField
            }

            cell.textField?.stringValue = customIntervals[row].name
            return cell
        } else if tableColumn?.identifier.rawValue == "intervalColumn" {
            let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView ?? NSTableCellView(frame: .zero)
            cell.identifier = cellIdentifier

            if cell.textField == nil {
                let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: tableColumn?.width ?? 100, height: 17))
                textField.isBordered = false
                textField.isEditable = false
                textField.drawsBackground = false
                cell.addSubview(textField)
                cell.textField = textField
            }

            cell.textField?.stringValue = "\(Int(customIntervals[row].interval))"
            return cell
        } else if tableColumn?.identifier.rawValue == "actionColumn" {
            let cell = NSButton(title: "Remove", target: self, action: #selector(removeCustomInterval))
            cell.bezelStyle = .rounded
            cell.tag = row
            cell.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            return cell
        }

        return nil
    }

    // MARK: - Custom Interval Methods

    func loadCustomIntervalsIntoTable() {
        guard let appDelegate else {
            LoggingUtility.shared.log("loadCustomIntervalsIntoTable: appDelegate is nil")
            return
        }

        // Clear the current intervals
        customIntervals.removeAll()

        // Get the custom intervals dictionary from UserDefaults
        if let customIntervalDict = UserDefaults.standard.dictionary(forKey: appDelegate.customIntervalsKey) as? [String: TimeInterval] {
            LoggingUtility.shared.log("Found \(customIntervalDict.count) custom intervals in UserDefaults")

            // Convert the dictionary to an array of tuples for the table
            for (name, interval) in customIntervalDict.sorted(by: { $0.key < $1.key }) {
                LoggingUtility.shared.log("Adding custom interval: \(name) = \(interval)")
                customIntervals.append((name: name, interval: interval))
            }
        } else {
            LoggingUtility.shared.log("No custom intervals found in UserDefaults")
        }

        // Reload the table view
        customIntervalsTable?.reloadData()

        LoggingUtility.shared.log("Reloaded custom intervals table with \(self.customIntervals.count) items")
    }

    @objc func addCustomInterval() {
        guard let appDelegate,
              let nameField = customIntervalNameField,
              let secondsField = customIntervalSecondsField else { return }

        // Get the name and seconds values
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondsString = secondsField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate input
        guard !name.isEmpty, let seconds = TimeInterval(secondsString), seconds > 0 else {
            // Show an error alert
            let alert = NSAlert()
            alert.messageText = "Invalid Input"
            alert.informativeText = "Please enter a valid name and a positive number of seconds."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        // Get the current custom intervals dictionary
        var customIntervalDict = UserDefaults.standard.dictionary(forKey: appDelegate.customIntervalsKey) as? [String: TimeInterval] ?? [:]

        // Add or update the interval
        customIntervalDict[name] = seconds

        // Save to UserDefaults
        UserDefaults.standard.set(customIntervalDict, forKey: appDelegate.customIntervalsKey)

        // Clear the input fields
        nameField.stringValue = ""
        secondsField.stringValue = ""

        // Reload the table view
        loadCustomIntervalsIntoTable()

        // Force the app delegate to rebuild its interval options and update the menu
        appDelegate.scheduleUpdateTimer()
        appDelegate.menuBarManager.rebuildIntervalSubmenuItems()
    }

    @objc func removeCustomInterval(_ sender: NSButton) {
        guard let appDelegate else { return }

        // Get the row index from the button's tag
        let row = sender.tag
        guard row < customIntervals.count else { return }

        // Get the interval name to remove
        let intervalName = customIntervals[row].name

        // Get the current custom intervals dictionary
        if var customIntervalDict = UserDefaults.standard.dictionary(forKey: appDelegate.customIntervalsKey) as? [String: TimeInterval] {
            // Remove the interval
            customIntervalDict.removeValue(forKey: intervalName)

            // Save to UserDefaults
            UserDefaults.standard.set(customIntervalDict, forKey: appDelegate.customIntervalsKey)

            // Reload the table view
            loadCustomIntervalsIntoTable()

            // Force the app delegate to rebuild its interval options and update the menu
            appDelegate.scheduleUpdateTimer()
            appDelegate.menuBarManager.rebuildIntervalSubmenuItems()
        }
    }

    @objc func saveBrewCommands() {
        // Get references to the text fields using their tags
        guard let updateField = windowController?.window?.contentView?.viewWithTag(1001) as? NSTextField,
              let upgradeField = windowController?.window?.contentView?.viewWithTag(1002) as? NSTextField
        else {
            return
        }

        // Get the command strings
        let updateCommandString = updateField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let upgradeCommandString = upgradeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Convert to arrays
        let updateCommandArray = updateCommandString.components(separatedBy: " ").filter { !$0.isEmpty }
        let upgradeCommandArray = upgradeCommandString.components(separatedBy: " ").filter { !$0.isEmpty }

        // Save to UserDefaults via the BrewBarManager
        if !updateCommandArray.isEmpty {
            BrewBarManager.shared.updateCommand = updateCommandArray
        }

        if !upgradeCommandArray.isEmpty {
            BrewBarManager.shared.upgradeCommand = upgradeCommandArray
        }

        // Show a success message
        let alert = NSAlert()
        alert.messageText = "Commands Saved"
        alert.informativeText = "Your custom Homebrew commands have been saved."
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc func resetBrewCommands() {
        // Reset to default commands
        BrewBarManager.shared.updateCommand = BrewBarManager.shared.defaultUpdateCommand
        BrewBarManager.shared.upgradeCommand = BrewBarManager.shared.defaultUpgradeCommand

        // Update the text fields
        guard let updateField = windowController?.window?.contentView?.viewWithTag(1001) as? NSTextField,
              let upgradeField = windowController?.window?.contentView?.viewWithTag(1002) as? NSTextField
        else {
            return
        }

        updateField.stringValue = BrewBarManager.shared.defaultUpdateCommand.joined(separator: " ")
        upgradeField.stringValue = BrewBarManager.shared.defaultUpgradeCommand.joined(separator: " ")

        // Show a success message
        let alert = NSAlert()
        alert.messageText = "Commands Reset"
        alert.informativeText = "Homebrew commands have been reset to their default values."
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc func updateIntervalPopup() {
        guard let appDelegate,
              let popup = windowController?.window?.contentView?.viewWithTag(2001) as? NSPopUpButton
        else {
            return
        }

        // Rebuild the popup items first
        popup.removeAllItems()
        for (name, interval) in appDelegate.intervalOptions.sorted(by: { $0.value < $1.value }) {
            popup.addItem(withTitle: name)
            popup.lastItem?.representedObject = interval
        }

        // Find and select the current interval
        let currentInterval = appDelegate.getCurrentInterval()
        for (index, item) in popup.itemArray.enumerated() {
            if let itemInterval = item.representedObject as? TimeInterval, itemInterval == currentInterval {
                popup.selectItem(at: index)
                break
            }
        }
    }
}
