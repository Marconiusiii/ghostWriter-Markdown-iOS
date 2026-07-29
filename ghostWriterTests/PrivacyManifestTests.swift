//
//  PrivacyManifestTests.swift
//  ghostWriterTests
//
//  Keeps the App Store privacy declarations aligned with the required-reason
//  APIs used by the app.
//

import Foundation
import Testing

struct PrivacyManifestTests {

    @Test func bundledManifestDeclaresRequiredReasonAPIs() throws {
        let manifestURL = try #require(
            Bundle.main.url(
                forResource: "PrivacyInfo",
                withExtension: "xcprivacy"
            )
        )
        let data = try Data(contentsOf: manifestURL)
        let object = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        let manifest = try #require(object as? [String: Any])
        let entries = try #require(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )

        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect(
            (manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true
        )
        #expect(
            reasons(
                for: "NSPrivacyAccessedAPICategoryUserDefaults",
                in: entries
            ) == ["CA92.1"]
        )
        #expect(
            reasons(
                for: "NSPrivacyAccessedAPICategoryFileTimestamp",
                in: entries
            ) == ["DDA9.1", "C617.1"]
        )
    }

    private func reasons(
        for category: String,
        in entries: [[String: Any]]
    ) -> Set<String> {
        let entry = entries.first {
            $0["NSPrivacyAccessedAPIType"] as? String == category
        }
        return Set(
            entry?["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
        )
    }
}
