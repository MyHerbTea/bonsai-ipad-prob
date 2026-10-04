import Foundation
import Combine

final class CertificationRunRecorder: ObservableObject {
    struct EventRecord: Codable {
        let sequence: Int
        let timestamp: String
        let name: String
        let fields: [String: String]
    }

    struct SnapshotRecord: Codable {
        let sequence: Int
        let timestamp: String
        let label: String
        let diagnostic: String
    }

    struct Archive: Codable {
        let schemaVersion: Int
        let runID: String
        let stage: String
        let build: String
        let startedAt: String
        var finishedAt: String?
        var status: String
        let environment: [String: String]
        var summary: String?
        var events: [EventRecord]
        var snapshots: [SnapshotRecord]
    }

    @Published private(set) var isRecording = false
    @Published private(set) var statusText = "Idle"
    @Published private(set) var latestArchiveURL: URL?
    @Published private(set) var eventCount = 0
    @Published private(set) var snapshotCount = 0

    private let lock = NSLock()
    private var archive: Archive?
    private var nextSequence = 1

    private let activeFilename =
        "bonsai_certification_active.json"

    init() {
        recoverInterruptedRunIfNeeded()
        refreshLatestArchiveFromDisk()
    }

    func refreshLatestArchiveFromDisk() {
        lock.lock()
        defer { lock.unlock() }
        refreshLatestArchiveFromDiskLocked()
    }

    @discardableResult
    func startRun(
        stage: String,
        build: String,
        environment: [String: String]
    ) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if archive != nil {
            return nil
        }

        let timestamp = Self.isoTimestamp()
        let runID =
            "BONSAI-RUN-"
            + Self.filenameTimestamp()
            + "-Build"
            + build

        archive = Archive(
            schemaVersion: 1,
            runID: runID,
            stage: stage,
            build: build,
            startedAt: timestamp,
            finishedAt: nil,
            status: "recording",
            environment: environment,
            summary: nil,
            events: [],
            snapshots: []
        )
        nextSequence = 1

        appendEventLocked(
            name: "recorder_started",
            fields: [
                "stage": stage,
                "build": build,
            ]
        )

        do {
            try persistActiveLocked()
            publishState(
                recording: true,
                status: "Recording · \(runID)",
                archiveURL: nil
            )
            return runID
        } catch {
            archive = nil
            nextSequence = 1
            publishState(
                recording: false,
                status: "Recorder start failed: \(error.localizedDescription)",
                archiveURL: nil
            )
            return nil
        }
    }

    func recordEvent(
        _ name: String,
        fields: [String: String] = [:]
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard archive != nil else { return }

        appendEventLocked(
            name: name,
            fields: fields
        )

        do {
            try persistActiveLocked()
            publishCountsLocked()
        } catch {
            publishState(
                recording: true,
                status: "Recorder write failed: \(error.localizedDescription)",
                archiveURL: latestArchiveURL
            )
        }
    }

    func recordSnapshot(
        label: String,
        diagnostic: String
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard var current = archive else { return }

        current.snapshots.append(
            SnapshotRecord(
                sequence: nextSequence,
                timestamp: Self.isoTimestamp(),
                label: label,
                diagnostic: diagnostic
            )
        )
        nextSequence += 1
        archive = current

        do {
            try persistActiveLocked()
            publishCountsLocked()
        } catch {
            publishState(
                recording: true,
                status: "Snapshot write failed: \(error.localizedDescription)",
                archiveURL: latestArchiveURL
            )
        }
    }

    @discardableResult
    func finishRun(
        summary: String
    ) -> URL? {
        lock.lock()
        defer { lock.unlock() }

        guard var current = archive else {
            return latestArchiveURL
        }

        appendEventLocked(
            name: "recorder_finished",
            fields: [
                "summary": summary,
            ]
        )

        guard var finalized = archive else {
            return nil
        }

        finalized.status = "completed"
        finalized.finishedAt = Self.isoTimestamp()
        finalized.summary = summary
        archive = finalized

        do {
            let url = try writeCompletedLocked(finalized)
            try? FileManager.default.removeItem(
                at: activeArchiveURL()
            )
            archive = nil
            nextSequence = 1
            publishState(
                recording: false,
                status: "Completed · \(finalized.runID)",
                archiveURL: url
            )
            return url
        } catch {
            publishState(
                recording: true,
                status: "Archive finalize failed: \(error.localizedDescription)",
                archiveURL: latestArchiveURL
            )
            return nil
        }
    }

    func recoverInterruptedRunIfNeeded() {
        lock.lock()
        defer { lock.unlock() }

        guard archive == nil else { return }

        let url = activeArchiveURL()
        guard
            let data = try? Data(contentsOf: url),
            var recovered = try? JSONDecoder().decode(
                Archive.self,
                from: data
            )
        else {
            refreshLatestArchiveFromDiskLocked()
            return
        }

        guard recovered.status == "recording" else {
            try? FileManager.default.removeItem(at: url)
            refreshLatestArchiveFromDiskLocked()
            return
        }

        archive = recovered
        nextSequence =
            max(
                recovered.events.map(\.sequence).max() ?? 0,
                recovered.snapshots.map(\.sequence).max() ?? 0
            ) + 1

        appendEventLocked(
            name: "app_recovered_interrupted_run",
            fields: [
                "recovered_at": Self.isoTimestamp(),
                "last_stage":
                    UserDefaults.standard.string(
                        forKey: "BonsaiLabLastStage"
                    ) ?? "无",
                "engine_stage":
                    persistedDiagnosticFile(
                        "bonsai_engine_stage.txt"
                    ),
                "staged_vision_stage":
                    persistedDiagnosticFile(
                        "bonsai_staged_vision_stage.txt"
                    ),
                "two_phase_vision_stage":
                    persistedDiagnosticFile(
                        "bonsai_two_phase_vision_stage.txt"
                    ),
                "mlx_vision_stage":
                    persistedDiagnosticFile(
                        "bonsai_mlx_vision_stage.txt"
                    ),
                "mlx_injection_stage":
                    persistedDiagnosticFile(
                        "bonsai_mlx_injection_stage.txt"
                    ),
                "api_preflight":
                    persistedDiagnosticFile(
                        "bonsai_api_preflight.txt"
                    ),
            ]
        )

        guard var interrupted = archive else { return }
        interrupted.status = "interrupted"
        interrupted.finishedAt = Self.isoTimestamp()
        interrupted.summary =
            "Previous certification run did not finish before app restart."
        archive = interrupted

        do {
            let completedURL =
                try writeCompletedLocked(interrupted)
            try? FileManager.default.removeItem(at: url)
            archive = nil
            nextSequence = 1
            publishState(
                recording: false,
                status: "Recovered interrupted run · \(interrupted.runID)",
                archiveURL: completedURL
            )
            refreshLatestArchiveFromDiskLocked()
        } catch {
            archive = interrupted
            let latest =
                latestCompletedArchiveURLLocked()
            publishState(
                recording: false,
                status: "Interrupted-run recovery failed: \(error.localizedDescription)",
                archiveURL: latest
            )
            refreshLatestArchiveFromDiskLocked()
        }
    }

    private func persistedDiagnosticFile(
        _ name: String
    ) -> String {
        let url =
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            .appendingPathComponent(name)

        return (
            try? String(
                contentsOf: url,
                encoding: .utf8
            )
        )?
        .trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? "无"
    }

    private func appendEventLocked(
        name: String,
        fields: [String: String]
    ) {
        guard var current = archive else { return }

        current.events.append(
            EventRecord(
                sequence: nextSequence,
                timestamp: Self.isoTimestamp(),
                name: name,
                fields: fields
            )
        )
        nextSequence += 1
        archive = current
    }

    private func persistActiveLocked() throws {
        guard let archive else { return }
        try ensureDirectory(
            activeArchiveURL()
                .deletingLastPathComponent()
        )
        let data = try Self.encoder().encode(archive)
        try data.write(
            to: activeArchiveURL(),
            options: .atomic
        )
    }

    private func writeCompletedLocked(
        _ archive: Archive
    ) throws -> URL {
        let directory =
            completedArchiveDirectory()
        try ensureDirectory(directory)

        let url = directory
            .appendingPathComponent(
                archive.runID + ".json"
            )

        let data = try Self.encoder().encode(archive)
        try data.write(
            to: url,
            options: .atomic
        )
        return url
    }

    private func completedArchiveDirectory() -> URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent(
            "BonsaiCertificationRuns",
            isDirectory: true
        )
    }

    private func latestCompletedArchiveURLLocked() -> URL? {
        let directory =
            completedArchiveDirectory()
        guard
            let urls =
                try? FileManager.default
                    .contentsOfDirectory(
                        at: directory,
                        includingPropertiesForKeys: [
                            .contentModificationDateKey,
                            .isRegularFileKey,
                        ],
                        options: [
                            .skipsHiddenFiles,
                        ]
                    )
        else {
            return nil
        }

        let candidates =
            urls.filter {
                $0.pathExtension.lowercased() == "json"
                && $0.lastPathComponent.hasPrefix(
                    "BONSAI-RUN-"
                )
            }

        return candidates.max { lhs, rhs in
            let leftValues =
                try? lhs.resourceValues(
                    forKeys: [
                        .contentModificationDateKey,
                    ]
                )
            let rightValues =
                try? rhs.resourceValues(
                    forKeys: [
                        .contentModificationDateKey,
                    ]
                )
            let leftDate =
                leftValues?.contentModificationDate
                ?? .distantPast
            let rightDate =
                rightValues?.contentModificationDate
                ?? .distantPast

            if leftDate == rightDate {
                return lhs.lastPathComponent
                    < rhs.lastPathComponent
            }
            return leftDate < rightDate
        }
    }

    private func refreshLatestArchiveFromDiskLocked() {
        let latest =
            latestCompletedArchiveURLLocked()
        let currentStatus =
            latest == nil
                ? "Idle · no saved certification archive"
                : "Archive ready · "
                    + latest!.lastPathComponent

        DispatchQueue.main.async {
            self.latestArchiveURL = latest
            if !self.isRecording {
                self.statusText = currentStatus
            }
        }
    }

    private func activeArchiveURL() -> URL {
        let directory =
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
        return directory
            .appendingPathComponent(activeFilename)
    }

    private func ensureDirectory(
        _ url: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    private func publishCountsLocked() {
        let events = archive?.events.count ?? 0
        let snapshots = archive?.snapshots.count ?? 0

        DispatchQueue.main.async {
            self.eventCount = events
            self.snapshotCount = snapshots
        }
    }

    private func publishState(
        recording: Bool,
        status: String,
        archiveURL: URL?
    ) {
        let events = archive?.events.count ?? 0
        let snapshots = archive?.snapshots.count ?? 0

        DispatchQueue.main.async {
            self.isRecording = recording
            self.statusText = status
            self.latestArchiveURL = archiveURL
            self.eventCount = events
            self.snapshotCount = snapshots
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
        ]
        return encoder
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter()
            .string(from: Date())
    }

    private static func filenameTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale =
            Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(secondsFromGMT: 0)
        formatter.dateFormat =
            "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: Date())
    }
}
