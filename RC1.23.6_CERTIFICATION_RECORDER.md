# RC1.23.6 Build 49 — Certification Recorder

Status: **PHASE A INFRASTRUCTURE CANDIDATE**

Parent:
- RC1.23.5 closed with **NO SAFE WIN FOUND**
- production behavior remains RC1.23.4 Build 46 FROZEN

## User-experience requirement

From RC1.23.6 onward, tests that require multiple iterations must not require the
user to manually copy one diagnostic snapshot after every iteration.

The target workflow is:

```text
prepare model / Vision Tower
        ↓
start certification once
        ↓
app runs the test
        ↓
app records every step automatically
        ↓
one BONSAI-RUN-*.json result
        ↓
share that one file
```

Build 49 implements the persistent recorder layer. The automatic restart runner
will be added only after this storage layer is CI-certified.

## Single-file archive

Completed runs are written to:

```text
Documents/BonsaiCertificationRuns/BONSAI-RUN-<UTC>-Build<build>.json
```

The JSON contains:

- schema version;
- run id;
- stage;
- build;
- start/end timestamps;
- final status;
- environment metadata;
- summary;
- ordered lifecycle/test events;
- ordered diagnostic snapshots.

This intentionally uses one JSON file rather than requiring the user to collect
multiple text files.

## Crash resilience

While a certification run is active, the complete archive is atomically
rewritten after every event or diagnostic snapshot to:

```text
bonsai_certification_active.json
```

inside the app's Application Support directory.

If the app terminates before the run is finished:

1. next launch detects the active file;
2. the run is marked `interrupted`;
3. an `app_recovered_interrupted_run` event is appended;
4. the interrupted run is finalized into the Documents result directory;
5. the active file is removed;
6. the recovered archive becomes shareable from the UI.

This ensures the most valuable evidence is not lost when the app crashes.

## Privacy boundary

The recorder is intended to consume the existing redacted
`buildDiagnosticSnapshot()` output.

Certification archives must not intentionally persist:

- API keys;
- raw image bytes;
- image Base64;
- user prompt text;
- assistant output.

The existing diagnostic snapshot already represents these fields as
redacted/not included.

## Build 49 UI

A new:

```text
RC1.23.6 Certification Recorder
```

section exposes:

- recorder status;
- event/snapshot counts;
- infrastructure-only manual start;
- manual snapshot capture;
- finalize-to-one-file;
- ShareLink for the latest completed/recovered archive.

These manual controls are for validating the recorder infrastructure only.

They are **not** the final user test flow.

## Next implementation

After Build 49 CI:

**Build 50 — One-Click Restart Certification Runner**

The runner should:

1. validate required model/Vision assets;
2. automatically start a recorder run;
3. use only the frozen 512 API context;
4. run repeated stop/start cycles;
5. automatically execute seed + warm test requests;
6. record lifecycle timestamps and all request diagnostics;
7. automatically finalize the archive;
8. expose one Share result action.

The user should not copy intermediate diagnostics.

## Frozen boundaries

Build 49 does not intentionally change:

- Accelerated runtime;
- Safe fallback;
- default API context=512;
- batch=8;
- ubatch=8;
- n_seq_max=1;
- C2-B;
- Vision Prefix KV reuse;
- sampler;
- max-token behavior;
- EOG / finish-reason semantics;
- OpenAI API response behavior.

Build 49 is observability/storage infrastructure only.
