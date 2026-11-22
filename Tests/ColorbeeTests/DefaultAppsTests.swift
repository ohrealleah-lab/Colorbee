import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Colorbee

/// Stage 36 (§23, 2026-11-21): Settings ▸ General ▸ Make Colorbee the default for. A stand-in plays the Mac's
/// defaults, so nothing here changes Leah's.
@MainActor
@Suite(.serialized)
struct DefaultAppsTests {
    private static let colorbee = "com.leah.Colorbee"

    @MainActor
    final class StandIn: DefaultAppSystem {
        var apps: [String: String] = [:]
        var installed: Set<String> = [DefaultApps.preview, DefaultAppsTests.colorbee]
        /// Types where Leah answers macOS's question with "Keep".
        var kept: Set<String> = []
        var asked: [String] = []

        func appBundleID(toOpen type: UTType) -> String? { apps[type.identifier] }
        func isInstalled(_ bundleID: String) -> Bool { installed.contains(bundleID) }
        func setApp(_ bundleID: String, toOpen type: UTType) async throws {
            asked.append(type.identifier)
            if kept.contains(type.identifier) { throw CocoaError(.fileReadUnknown) }
            apps[type.identifier] = bundleID
        }
    }

    private func everything(openIn app: String) -> StandIn {
        let standIn = StandIn()
        for kind in DefaultAppKind.allCases {
            for type in kind.types { standIn.apps[type.identifier] = app }
        }
        return standIn
    }

    @Test func checkingATypeTakesItAndRemembersTheAppBefore() async throws {
        let standIn = everything(openIn: DefaultApps.preview)
        standIn.apps[UTType.heif.identifier] = "com.example.Viewer"
        standIn.installed.insert("com.example.Viewer")
        let defaults = DefaultApps(system: standIn, colorbee: Self.colorbee, before: [:])
        #expect(defaults.checked.isEmpty)

        try await defaults.set(.heic, on: true)
        #expect(defaults.checked == [.heic])
        #expect(standIn.apps[UTType.heic.identifier] == Self.colorbee && standIn.apps[UTType.heif.identifier] == Self.colorbee)
        #expect(defaults.before[UTType.heif.identifier] == "com.example.Viewer")

        try await defaults.set(.heic, on: false)
        #expect(defaults.checked.isEmpty)
        #expect(standIn.apps[UTType.heic.identifier] == DefaultApps.preview)
        #expect(standIn.apps[UTType.heif.identifier] == "com.example.Viewer")
        #expect(defaults.before.isEmpty)
    }

    @Test func uncheckingWithNothingRememberedGivesItToPreview() async throws {
        let standIn = everything(openIn: Self.colorbee)
        let defaults = DefaultApps(system: standIn, colorbee: Self.colorbee, before: [:])
        #expect(defaults.checked == Set(DefaultAppKind.allCases))

        try await defaults.set(.png, on: false)
        #expect(standIn.apps[UTType.png.identifier] == DefaultApps.preview)
        #expect(!defaults.checked.contains(.png))
    }

    @Test func uncheckingWhenTheAppBeforeIsGoneGivesItToPreview() async throws {
        let standIn = everything(openIn: Self.colorbee)
        let defaults = DefaultApps(system: standIn, colorbee: Self.colorbee, before: [UTType.gif.identifier: "com.example.Deleted"])
        try await defaults.set(.gif, on: false)
        #expect(standIn.apps[UTType.gif.identifier] == DefaultApps.preview)
    }

    @Test func aRowIsCheckedOnlyWhenEveryTypeInItOpensInColorbee() {
        let standIn = everything(openIn: Self.colorbee)
        standIn.apps[UTType.heif.identifier] = DefaultApps.preview
        let defaults = DefaultApps(system: standIn, colorbee: Self.colorbee, before: [:])
        #expect(!defaults.checked.contains(.heic))
        #expect(defaults.checked.contains(.jpeg))
    }

    @Test func launchServicesLowercaseIDStillCountsAsColorbee() {
        let standIn = everything(openIn: Self.colorbee.lowercased())
        let defaults = DefaultApps(system: standIn, colorbee: Self.colorbee, before: [:])
        #expect(defaults.checked == Set(DefaultAppKind.allCases))
    }

    @Test func checkAllTakesEveryRow() async throws {
        let standIn = everything(openIn: DefaultApps.preview)
        standIn.apps[UTType.jpeg.identifier] = Self.colorbee
        let defaults = DefaultApps(system: standIn, colorbee: Self.colorbee, before: [:])
        try await defaults.checkAll()
        #expect(defaults.checked == Set(DefaultAppKind.allCases))
        #expect(standIn.apps.values.allSatisfy { $0 == Self.colorbee })
        // JPEG was already Colorbee's, so there's nothing to give back for it.
        #expect(defaults.before[UTType.jpeg.identifier] == nil)
    }

    @Test func keepingTheAppIsNoErrorAndChangesNothing() async throws {
        let standIn = everything(openIn: Self.colorbee)
        standIn.kept = [UTType.pdf.identifier]
        let defaults = DefaultApps(system: standIn, colorbee: Self.colorbee, before: [:])
        let changed = try await defaults.set(.pdf, on: false)
        #expect(!changed)
        #expect(defaults.checked.contains(.pdf))
        #expect(standIn.apps[UTType.pdf.identifier] == Self.colorbee)
    }

    @Test func keepingOneTypeLeavesTheRestOfTheRowAlone() async throws {
        let standIn = everything(openIn: DefaultApps.preview)
        standIn.kept = [UTType.heic.identifier]
        let defaults = DefaultApps(system: standIn, colorbee: Self.colorbee, before: [:])
        try await defaults.set(.heic, on: true)
        #expect(standIn.asked == [UTType.heic.identifier])
        #expect(standIn.apps[UTType.heif.identifier] == DefaultApps.preview)
        #expect(!defaults.checked.contains(.heic) && defaults.before.isEmpty)
    }

    @Test func checkAllStopsAtTheFirstKeep() async throws {
        let standIn = everything(openIn: DefaultApps.preview)
        standIn.kept = [UTType.tiff.identifier]
        let defaults = DefaultApps(system: standIn, colorbee: Self.colorbee, before: [:])
        try await defaults.checkAll()
        #expect(defaults.checked == [.jpeg, .png, .heic])
        #expect(standIn.apps[UTType.gif.identifier] == DefaultApps.preview)
    }

    @Test func aRealFailureIsStillAnError() async {
        @MainActor
        final class Broken: DefaultAppSystem {
            var apps: [String: String] = [:]
            func appBundleID(toOpen type: UTType) -> String? { apps[type.identifier] }
            func isInstalled(_ bundleID: String) -> Bool { true }
            func setApp(_ bundleID: String, toOpen type: UTType) async throws {
                // Half done: the type changed to something else, then it failed.
                apps[type.identifier] = "com.example.Other"
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let defaults = DefaultApps(system: Broken(), colorbee: Self.colorbee, before: [:])
        await #expect(throws: CocoaError.self) { try await defaults.set(.png, on: true) }
    }
}
