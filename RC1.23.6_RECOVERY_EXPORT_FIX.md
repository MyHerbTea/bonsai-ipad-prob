# RC1.23.6 Build 51 — Recovery Export Fix

Status: **POST-CRASH RECOVERY UX CANDIDATE**

Parent:
- Build 50 one-click restart certification runner
- Build 50 true-device run crashed during automated restart certification

## Problem discovered

After the Build 50 crash, reopening the app did not reliably expose the
"Share Result" action.

The Build 50 UI rendered the share control only when the in-memory
`latestArchiveURL` property was non-nil.

That made post-crash export depend too heavily on one recovery-time memory
transition even though completed/recovered JSON files were persisted on disk.

## Build 51 fix

Build 51 makes the result archive discoverable from disk.

The recorder now provides:

`refreshLatestArchiveFromDisk()`

It scans:

`Documents/BonsaiCertificationRuns`

for the newest:

`BONSAI-RUN-*.json`

using file modification time.

The scan runs:
- during recorder initialization;
- after interrupted-run recovery;
- when no active run is found;
- on ProductionView appearance;
- when the user taps Refresh Test Archive.

## UI behavior

The Restart Certification section is always visible.

If a saved archive exists:

`分享最近测试结果`

is shown.

If none exists:

`暂无可分享的测试存档`

is shown explicitly.

A:

`刷新测试存档`

button is also always available.

This removes ambiguity between:
- "there is no archive";
- "the archive exists but the in-memory URL was lost";
- "the user did not scroll to a transient share control."

## Preserving Build 50 crash evidence

Build 51 is intended to be installed **over** Build 50 without uninstalling the
app.

If the Build 50 crash left either:
- an active interrupted archive in Application Support, or
- a recovered/completed BONSAI-RUN JSON in Documents,

Build 51 should rediscover it on launch and expose it through the share action.

Do not rerun Restart Certification merely to create a new archive before trying
to export the Build 50 crash evidence.

## Frozen runtime

No inference/runtime behavior changes are introduced.

Build 51 retains:
- Accelerated;
- API context 512;
- batch 8;
- ubatch 8;
- n_seq_max 1;
- C2-B;
- Prefix KV reuse;
- Build 50 one-click restart runner.

The rejected 256 context experiment remains removed.
