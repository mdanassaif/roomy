import SwiftUI

/// Plain-language explanations for well-known folders and files, so people know what's safe to remove.
struct Advice {
    enum Verdict {
        case safe, rebuilds, review, keep

        var label: String {
            switch self {
            case .safe: "Safe to remove"
            case .rebuilds: "Rebuilds itself"
            case .review: "Check first"
            case .keep: "Keep"
            }
        }
        var color: Color {
            switch self {
            case .safe: Theme.good
            case .rebuilds: Theme.calm
            case .review: Theme.warm
            case .keep: .secondary
            }
        }
        var icon: String {
            switch self {
            case .safe: "checkmark.seal.fill"
            case .rebuilds: "arrow.triangle.2.circlepath"
            case .review: "eye.fill"
            case .keep: "lock.fill"
            }
        }
    }

    let verdict: Verdict
    let text: String
}

enum Advisor {
    static let home = NSHomeDirectory()

    private static let byHomePath: [String: Advice] = [
        "Library": Advice(verdict: .keep, text: "Settings and data for your apps. Look inside instead of removing it."),
        "Library/Caches": Advice(verdict: .rebuilds, text: "App caches. Apps recreate them when needed."),
        "Library/Logs": Advice(verdict: .safe, text: "Diagnostic logs from apps."),
        "Library/Developer": Advice(verdict: .review, text: "Xcode and simulator data. Quick Clean lists the safe parts."),
        "Library/Developer/Xcode/DerivedData": Advice(verdict: .rebuilds, text: "Xcode build files, recreated on the next build."),
        "Library/Developer/Xcode/Archives": Advice(verdict: .review, text: "Old app builds you uploaded. Keep the ones you may need for crash reports."),
        "Library/Developer/Xcode/iOS DeviceSupport": Advice(verdict: .rebuilds, text: "Debug symbols for iOS versions, fetched again when you connect a device."),
        "Library/Developer/CoreSimulator": Advice(verdict: .review, text: "iOS simulators. Remove old ones in Xcode › Settings › Platforms."),
        "Library/Application Support": Advice(verdict: .review, text: "Data your apps saved. Removing a folder here can erase that app's data."),
        "Library/Application Support/MobileSync/Backup": Advice(verdict: .review, text: "iPhone and iPad backups. Delete old ones in Finder › your device › Manage Backups."),
        "Library/Containers": Advice(verdict: .review, text: "Data for App Store apps. Removing one erases that app's data."),
        "Library/Group Containers": Advice(verdict: .review, text: "Data shared between apps from the same developer."),
        "Library/Mobile Documents": Advice(verdict: .keep, text: "Your iCloud Drive."),
        "Library/Mail": Advice(verdict: .keep, text: "Your email, stored by Mail."),
        "Library/Messages": Advice(verdict: .keep, text: "Your Messages history and attachments."),
        "Library/Photos": Advice(verdict: .keep, text: "Photos app data."),
        ".npm": Advice(verdict: .rebuilds, text: "npm's download cache. Packages download again when needed."),
        ".cache": Advice(verdict: .rebuilds, text: "Caches from command-line tools. They may download things again."),
        ".bun": Advice(verdict: .review, text: "The Bun runtime and its package cache. Quick Clean removes only the cache."),
        ".nvm": Advice(verdict: .review, text: "Node.js versions installed with nvm. Remove old ones with `nvm uninstall <version>`."),
        ".gradle": Advice(verdict: .rebuilds, text: "Gradle build cache and downloads."),
        ".cargo": Advice(verdict: .review, text: "Rust packages and tools. The registry cache is safe to clear."),
        ".rustup": Advice(verdict: .review, text: "Rust toolchains. Remove old ones with `rustup toolchain uninstall`."),
        ".docker": Advice(verdict: .review, text: "Docker settings. Clean images with `docker system prune`."),
        ".ollama": Advice(verdict: .review, text: "Downloaded AI models. Remove unused ones with `ollama rm <model>`."),
        ".pnpm-store": Advice(verdict: .rebuilds, text: "pnpm's package store. Packages download again when needed."),
        ".Trash": Advice(verdict: .safe, text: "Your Trash. Empty it to get this space back."),
        "Desktop": Advice(verdict: .review, text: "Your files. Go inside to find big things you don't need."),
        "Documents": Advice(verdict: .review, text: "Your files. Go inside to find big things you don't need."),
        "Downloads": Advice(verdict: .review, text: "Things you downloaded. Old installers and archives are usually safe to remove."),
        "Pictures": Advice(verdict: .keep, text: "Your photos. Remove them from inside the Photos app, not here."),
        "Movies": Advice(verdict: .review, text: "Your videos. Often the biggest files on a Mac."),
        "Music": Advice(verdict: .keep, text: "Your music library."),
        "Applications": Advice(verdict: .review, text: "Apps only you can use. Uninstall them from Applications › All Apps."),
    ]

    private static let byName: [String: Advice] = [
        "node_modules": Advice(verdict: .safe, text: "Project dependencies. Get them back with `npm install`."),
        ".next": Advice(verdict: .rebuilds, text: "Next.js build output, recreated on the next build."),
        ".turbo": Advice(verdict: .rebuilds, text: "Turborepo cache."),
        "DerivedData": Advice(verdict: .rebuilds, text: "Xcode build files."),
        "Pods": Advice(verdict: .rebuilds, text: "CocoaPods dependencies. Get them back with `pod install`."),
        ".git": Advice(verdict: .keep, text: "Your project's version history."),
        "Docker.raw": Advice(verdict: .review, text: "Docker's disk image. Shrink it with `docker system prune`, not by deleting it."),
        "sleepimage": Advice(verdict: .keep, text: "Used by macOS for sleep."),
    ]

    private static let byExtension: [String: Advice] = [
        "dmg": Advice(verdict: .safe, text: "Disk image installer. Not needed once the app is installed."),
        "pkg": Advice(verdict: .safe, text: "Installer package. Not needed once installed."),
        "iso": Advice(verdict: .review, text: "Disk image."),
        "xip": Advice(verdict: .safe, text: "Xcode archive installer. Not needed once extracted."),
        "zip": Advice(verdict: .review, text: "Compressed archive. Check you've extracted what you need."),
        "ipsw": Advice(verdict: .safe, text: "iPhone/iPad firmware. Downloaded again if needed."),
        "mov": Advice(verdict: .review, text: "Video."),
        "mp4": Advice(verdict: .review, text: "Video."),
        "mkv": Advice(verdict: .review, text: "Video."),
    ]

    /// The Claude Code version in use, so older ones can be called safe.
    private static let currentClaude: String? = {
        let link = home + "/.local/bin/claude"
        return (try? FileManager.default.destinationOfSymbolicLink(atPath: link)).map { ($0 as NSString).lastPathComponent }
    }()

    /// Rules for places that a folder's name alone doesn't explain. Checked before anything else.
    private static func special(_ path: String, name: String) -> Advice? {
        let h = home
        if path.hasPrefix(h + "/.local/share/claude/versions/") {
            return name == currentClaude
                ? Advice(verdict: .keep, text: "The Claude Code version you're using.")
                : Advice(verdict: .safe, text: "An older Claude Code version, no longer used.")
        }
        if path.hasPrefix(h + "/.local/share/claude/") { return Advice(verdict: .keep, text: "Part of Claude Code.") }
        if path.hasPrefix(h + "/.claude/projects/") && name.hasSuffix(".jsonl") {
            return Advice(verdict: .review, text: "A past Claude Code chat. Remove it if you won't resume that chat.")
        }
        if path.hasPrefix(h + "/Library/Application Support/Claude/vm_bundles") {
            return Advice(verdict: .rebuilds, text: "The Claude app's Cowork machine. Downloaded again when you use Cowork.")
        }
        if path.hasPrefix(h + "/Library/Application Support/Claude/") { return Advice(verdict: .keep, text: "Part of the Claude app.") }
        if path.hasPrefix(h + "/Library/Application Support/Google/GoogleUpdater/crx_cache") {
            return Advice(verdict: .rebuilds, text: "Chrome's updater downloads. Fetched again when needed.")
        }
        if path.hasPrefix(h + "/Library/Developer/Xcode/CodingAssistant/") {
            return Advice(verdict: .rebuilds, text: "Xcode's coding assistant. Downloaded again if you turn it on.")
        }
        if path.hasPrefix(h + "/.nvm/") || path.hasPrefix(h + "/.npm-global/") {
            if path.hasPrefix(h + "/.nvm/versions/node/") && path.split(separator: "/").count == h.split(separator: "/").count + 4 {
                return Advice(verdict: .review, text: "A Node.js version. Remove old ones with `nvm uninstall <version>`.")
            }
            return Advice(verdict: .keep, text: "Node.js or a command-line tool you installed.")
        }
        if path.hasPrefix(h + "/.vscode/extensions/") { return Advice(verdict: .keep, text: "A VS Code extension you have installed.") }
        if path.hasPrefix(h + "/Library/Application Support/com.raycast.macos/") { return Advice(verdict: .keep, text: "Part of Raycast.") }
        if path.contains("/com.apple.MobileAsset") || path.contains("/AssetData/") { return Advice(verdict: .keep, text: "A download macOS manages itself.") }
        if path.contains(".xctoolchain/") { return Advice(verdict: .keep, text: "Part of Xcode.") }
        if path.contains("/Photos Library.photoslibrary") { return Advice(verdict: .keep, text: "Your Photos library. Remove photos in the Photos app.") }
        return nil
    }

    /// Folders that hold all sorts of things, so their advice doesn't pass down to what's inside.
    private static let broad: Set<String> = ["", "Library", "Library/Application Support", "Desktop", "Documents", "Downloads",
                                             "Movies", "Applications"]

    /// What to do with this item: its own rule, or the nearest folder above it that has one.
    static func explain(_ path: String, name: String) -> Advice? {
        if let a = special(path, name: name) ?? own(path, name: name) { return a }
        var p = (path as NSString).deletingLastPathComponent
        while p.count > 1 && p != home {
            if let a = byName[(p as NSString).lastPathComponent] { return a }
            if p.hasPrefix(home + "/") {
                let rel = String(p.dropFirst(home.count + 1))
                if !broad.contains(rel), let a = byHomePath[rel] { return a }
            }
            p = (p as NSString).deletingLastPathComponent
        }
        return nil
    }

    private static func own(_ path: String, name: String) -> Advice? {
        if path == "/System" || path.hasPrefix("/System/") { return Advice(verdict: .keep, text: "macOS itself.") }
        if path == "/private/var/vm" { return Advice(verdict: .keep, text: "Swap and sleep files managed by macOS.") }
        if path == "/Applications" { return Advice(verdict: .review, text: "Your apps. Uninstall them from Applications › All Apps.") }
        if path.hasPrefix(home + "/") {
            let rel = String(path.dropFirst(home.count + 1))
            if let a = byHomePath[rel] { return a }
            if rel.hasPrefix("Library/Caches/") { return Advice(verdict: .rebuilds, text: "An app's cache, recreated when needed.") }
            if rel.hasPrefix("Library/Logs/") { return Advice(verdict: .safe, text: "Diagnostic logs.") }
        }
        if let a = byName[name] { return a }
        let ext = (name as NSString).pathExtension.lowercased()
        if name.hasSuffix(".app") { return Advice(verdict: .review, text: "An app. Uninstall it from Applications › All Apps to remove its leftovers too.") }
        return byExtension[ext]
    }
}

struct AdviceBadge: View {
    let advice: Advice
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: advice.verdict.icon).font(.system(size: 9, weight: .semibold))
            if !compact { Text(advice.verdict.label).font(.system(size: 11, weight: .medium)) }
        }
        .foregroundStyle(advice.verdict.color)
        .help(advice.text)
    }
}
