//
//  SAM3SetupView.swift
//  cropaway
//
//  First-run setup wizard for SAM3 AI segmentation.
//

import SwiftUI
import Combine

struct SAM3SetupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var setupManager = SAM3SetupManager()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("AI Mask Setup")
                    .font(.title2.bold())

                Text("Set up the AI segmentation feature")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Content based on current step
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch setupManager.currentStep {
                    case .checkingPython:
                        CheckingStepView(title: "Checking Python installation...")

                    case .pythonMissing(let hasHomebrew):
                        PythonMissingView(
                            hasHomebrew: hasHomebrew,
                            onInstallPython: {
                                Task { await setupManager.installPython() }
                            },
                            onInstallHomebrew: {
                                Task { await setupManager.installHomebrew() }
                            }
                        )

                    case .installingHomebrew:
                        InstallingView(
                            title: "Installing Homebrew...",
                            subtitle: "This may take a few minutes",
                            progress: setupManager.installProgress,
                            log: setupManager.installLog
                        )

                    case .installingPython:
                        InstallingView(
                            title: "Installing Python 3.12...",
                            subtitle: "This may take a few minutes",
                            progress: setupManager.installProgress,
                            log: setupManager.installLog
                        )

                    case .checkingDependencies:
                        CheckingStepView(title: "Checking Python packages...")

                    case .installingDependencies:
                        InstallingView(
                            title: "Installing Python packages...",
                            subtitle: "torch, transformers, flask, etc.",
                            progress: setupManager.installProgress,
                            log: setupManager.installLog
                        )

                    case .dependenciesMissing(let packages):
                        DependenciesMissingView(packages: packages, onInstall: {
                            Task { await setupManager.installDependencies() }
                        })

                    case .ready:
                        ReadyView()

                    case .error(let message):
                        ErrorView(message: message, onRetry: {
                            Task { await setupManager.startSetup() }
                        })
                    }
                }
                .padding(24)
            }

            Divider()

            // Footer
            HStack {
                if setupManager.currentStep == .ready {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                } else if case .error = setupManager.currentStep {
                    Button("Close") {
                        dismiss()
                    }
                    Spacer()
                    Button("Try Again") {
                        Task { await setupManager.startSetup() }
                    }
                    .buttonStyle(.borderedProminent)
                } else if case .pythonMissing = setupManager.currentStep {
                    Button("Close") {
                        dismiss()
                    }
                    Spacer()
                } else if case .dependenciesMissing = setupManager.currentStep {
                    Button("Cancel") {
                        dismiss()
                    }
                    Spacer()
                } else if setupManager.isInstalling {
                    Button("Cancel") {
                        setupManager.cancelInstallation()
                    }
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(16)
        }
        .frame(width: 520, height: 450)
        .task {
            await setupManager.startSetup()
        }
    }
}

// MARK: - Step Views

struct CheckingStepView: View {
    let title: String

    var body: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}

struct PythonMissingView: View {
    let hasHomebrew: Bool
    let onInstallPython: () -> Void
    let onInstallHomebrew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Python 3.10+ Required", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("AI Mask requires Python 3.10 or later to run the segmentation model.")
                .foregroundStyle(.secondary)

            if hasHomebrew {
                // Homebrew is available - offer one-click install
                VStack(alignment: .leading, spacing: 12) {
                    Text("Homebrew detected! Click below to install Python automatically:")
                        .font(.callout)

                    Button(action: onInstallPython) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Install Python 3.12")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // No Homebrew - offer to install it first
                VStack(alignment: .leading, spacing: 12) {
                    Text("We'll install Homebrew (a package manager) first, then Python:")
                        .font(.callout)

                    Button(action: onInstallHomebrew) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Install Homebrew & Python")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("Homebrew is a free, open-source package manager for macOS used by millions of developers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            // Manual option
            DisclosureGroup("Manual Installation") {
                VStack(alignment: .leading, spacing: 12) {
                    InstallOptionView(
                        title: "Via Homebrew",
                        command: "brew install python@3.12"
                    )

                    InstallOptionView(
                        title: "Via Python.org",
                        command: "https://python.org/downloads"
                    )
                }
                .padding(.top, 8)
            }
            .font(.subheadline)
        }
    }
}

struct InstallOptionView: View {
    let title: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.bold())

            HStack {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            }
        }
    }
}

struct DependenciesMissingView: View {
    let packages: [String]
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Missing Python Packages", systemImage: "shippingbox")
                .font(.headline)

            Text("The following packages need to be installed:")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(packages, id: \.self) { package in
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                        Text(package)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: onInstall) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Install Packages")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("This may take a few minutes. Model files (~2GB) will be downloaded on first use.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct InstallingView: View {
    let title: String
    let subtitle: String
    let progress: String
    let log: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !progress.isEmpty {
                Text(progress)
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }

            // Log output
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(log.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 140)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: log.count) { _, _ in
                    if let lastIndex = log.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

struct ReadyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Setup Complete", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text("AI Mask is ready to use!")
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 8) {
                Text("How to use:")
                    .font(.subheadline.bold())

                BulletPoint("Press ⌘4 to switch to AI mode")
                BulletPoint("Click 'Start AI' in the toolbar")
                BulletPoint("Click on objects to select them")
                BulletPoint("Option+click to exclude areas")
                BulletPoint("Double-click points to remove them")
            }
            .padding(12)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Note: The AI model (~2GB) will be downloaded automatically on first use.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
        }
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Setup Failed", systemImage: "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Setup Manager

@MainActor
class SAM3SetupManager: ObservableObject {
    enum SetupStep: Equatable {
        case checkingPython
        case pythonMissing(hasHomebrew: Bool)
        case installingHomebrew
        case installingPython
        case checkingDependencies
        case dependenciesMissing([String])
        case installingDependencies
        case ready
        case error(String)
    }

    @Published var currentStep: SetupStep = .checkingPython
    @Published var installProgress: String = ""
    @Published var installLog: [String] = []
    @Published var isInstalling = false

    private var currentProcess: Process?
    private let requiredPackages = ["torch", "transformers", "flask", "flask_cors", "PIL", "numpy"]

    func startSetup() async {
        currentStep = .checkingPython
        installLog = []

        // Check Python
        if let _ = findPythonPath() {
            currentStep = .checkingDependencies
            await checkDependencies()
        } else {
            // Check if Homebrew is available
            let hasHomebrew = checkHomebrew()
            currentStep = .pythonMissing(hasHomebrew: hasHomebrew)
        }
    }

    func installHomebrew() async {
        currentStep = .installingHomebrew
        isInstalling = true
        installLog = []
        installProgress = "Downloading Homebrew installer..."

        // Homebrew install command
        let installScript = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

        do {
            // We need to run this in a way that allows user interaction for password
            // Using AppleScript to open Terminal and run the command
            let script = """
            tell application "Terminal"
                activate
                do script "/bin/bash -c \\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\""
            end tell
            """

            installLog.append("Opening Terminal to install Homebrew...")
            installLog.append("Please follow the prompts in Terminal.")
            installLog.append("")
            installLog.append("After installation completes:")
            installLog.append("1. Close the Terminal window")
            installLog.append("2. Click 'Try Again' below")

            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            appleScript?.executeAndReturnError(&error)

            if let error = error {
                throw NSError(domain: "AppleScript", code: -1, userInfo: [NSLocalizedDescriptionKey: error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"])
            }

            installProgress = "Waiting for Homebrew installation in Terminal..."

            // Wait a bit then prompt user
            try await Task.sleep(nanoseconds: 3_000_000_000)

            currentStep = .error("Please complete the Homebrew installation in Terminal, then click 'Try Again'.")
            isInstalling = false

        } catch {
            currentStep = .error("Failed to start Homebrew installation: \(error.localizedDescription)")
            isInstalling = false
        }
    }

    func installPython() async {
        currentStep = .installingPython
        isInstalling = true
        installLog = []
        installProgress = "Installing Python 3.12 via Homebrew..."

        guard let brewPath = findHomebrewPath() else {
            currentStep = .error("Homebrew not found. Please install Homebrew first.")
            isInstalling = false
            return
        }

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["install", "python@3.12"]
            currentProcess = process

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Read output asynchronously
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    Task { @MainActor in
                        self?.installLog.append(contentsOf: output.components(separatedBy: .newlines).filter { !$0.isEmpty })
                    }
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    Task { @MainActor in
                        self?.installLog.append(contentsOf: output.components(separatedBy: .newlines).filter { !$0.isEmpty })
                    }
                }
            }

            try process.run()

            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
            }

            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            currentProcess = nil

            if process.terminationStatus == 0 {
                installProgress = "Python installed successfully!"
                installLog.append("")
                installLog.append("✓ Python 3.12 installed successfully")

                // Continue to check dependencies
                isInstalling = false
                await startSetup()
            } else {
                currentStep = .error("Python installation failed. Exit code: \(process.terminationStatus)")
                isInstalling = false
            }

        } catch {
            currentStep = .error("Failed to install Python: \(error.localizedDescription)")
            isInstalling = false
        }
    }

    func installDependencies() async {
        currentStep = .installingDependencies
        isInstalling = true
        installLog = []
        installProgress = "Preparing..."

        guard let pythonPath = findPythonPath() else {
            currentStep = .error("Python not found")
            isInstalling = false
            return
        }

        guard let requirementsPath = findRequirementsFile() else {
            currentStep = .error("Requirements file not found in app bundle")
            isInstalling = false
            return
        }

        installProgress = "Installing packages via pip..."
        installLog.append("Using Python: \(pythonPath)")
        installLog.append("Requirements: \(requirementsPath)")
        installLog.append("")

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = ["-m", "pip", "install", "--user", "--upgrade", "-r", requirementsPath]
            currentProcess = process

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    Task { @MainActor in
                        self?.installLog.append(contentsOf: output.components(separatedBy: .newlines).filter { !$0.isEmpty })
                    }
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    Task { @MainActor in
                        self?.installLog.append(contentsOf: output.components(separatedBy: .newlines).filter { !$0.isEmpty })
                    }
                }
            }

            try process.run()

            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
            }

            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            currentProcess = nil

            if process.terminationStatus == 0 {
                installProgress = "Installation complete!"
                currentStep = .ready
                UserDefaults.standard.set(true, forKey: "SAM3SetupComplete")
            } else {
                currentStep = .error("pip install failed with exit code \(process.terminationStatus)")
            }
            isInstalling = false

        } catch {
            currentStep = .error(error.localizedDescription)
            isInstalling = false
        }
    }

    func cancelInstallation() {
        currentProcess?.terminate()
        currentProcess = nil
        isInstalling = false
        Task {
            await startSetup()
        }
    }

    private func checkDependencies() async {
        guard let pythonPath = findPythonPath() else {
            let hasHomebrew = checkHomebrew()
            currentStep = .pythonMissing(hasHomebrew: hasHomebrew)
            return
        }

        var missingPackages: [String] = []
        for package in requiredPackages {
            let importName = package == "PIL" ? "PIL" : package
            if await !isPackageInstalled(pythonPath: pythonPath, package: importName) {
                let displayName = package == "PIL" ? "pillow" : package
                missingPackages.append(displayName)
            }
        }

        if missingPackages.isEmpty {
            currentStep = .ready
            UserDefaults.standard.set(true, forKey: "SAM3SetupComplete")
        } else {
            currentStep = .dependenciesMissing(missingPackages)
        }
    }

    private func checkHomebrew() -> Bool {
        return findHomebrewPath() != nil
    }

    private func findHomebrewPath() -> String? {
        let paths = [
            "/opt/homebrew/bin/brew",  // Apple Silicon
            "/usr/local/bin/brew"       // Intel
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func findPythonPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/opt/homebrew/bin/python3.12",
            "/usr/local/bin/python3",
            "/usr/local/bin/python3.12",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3",
            "/usr/bin/python3"
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                // Verify it's Python 3.10+
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["--version"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let version = String(data: data, encoding: .utf8) {
                        let components = version.trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "Python ", with: "")
                            .components(separatedBy: ".")

                        if components.count >= 2,
                           let major = Int(components[0]),
                           let minor = Int(components[1]) {
                            if major >= 3 && minor >= 10 {
                                return path
                            }
                        }
                    }
                } catch {
                    continue
                }
            }
        }

        return nil
    }

    private func findRequirementsFile() -> String? {
        // Check in bundle Resources (both root and python/ subdirectory)
        if let bundlePath = Bundle.main.resourcePath {
            // Check root of Resources
            let rootPath = (bundlePath as NSString).appendingPathComponent("requirements.txt")
            if FileManager.default.fileExists(atPath: rootPath) {
                return rootPath
            }

            // Check python/ subdirectory
            let subPath = (bundlePath as NSString).appendingPathComponent("python/requirements.txt")
            if FileManager.default.fileExists(atPath: subPath) {
                return subPath
            }
        }

        // Check development location
        if let bundlePath = Bundle.main.bundlePath.components(separatedBy: "/Build/").first {
            let devPath = bundlePath + "/cropaway/Resources/python/requirements.txt"
            if FileManager.default.fileExists(atPath: devPath) {
                return devPath
            }
        }

        return nil
    }

    private func isPackageInstalled(pythonPath: String, package: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", "import \(package)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Preview

#Preview {
    SAM3SetupView()
}
