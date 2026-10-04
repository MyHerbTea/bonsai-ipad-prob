# RC1.24.1 Build 56 — Runtime Profile A/B

Status: **CONTROLLED A/B CANDIDATE**

Parent:
- RC1.24.0 Build 55 frozen diagnostic baseline.

Goal:
Identify which acceleration component changes cold and sustained decode
behavior while preserving the production Full profile as the default.

## Runtime ladder

Build 56 exposes four profiles:

| UI | Internal ID | Flash Attention | KQV Offload | Op Offload |
|---|---|---:|---:|---:|
| Safe | safe | OFF | OFF | OFF |
| Flash | ab_flash_only | ON | OFF | OFF |
| +KQV | ab_flash_kqv | ON | ON | OFF |
| Full | accelerated | ON | ON | ON |

This cumulative ladder measures the incremental effect of:
1. Flash Attention;
2. KQV Offload on top of Flash;
3. Op Offload on top of Flash + KQV.

Full remains the default and the Build 54/55 production behavior is unchanged
unless the user explicitly selects an A/B profile before a fresh runtime load.

## Required device protocol

For each experimental profile:
1. stop the API;
2. select the target profile;
3. force a full runtime release before starting the new profile;
4. start the OpenAI API;
5. verify the diagnostic profile and effective booleans;
6. run the same fixed 10-request text-only test:
   - same 83-token prompt;
   - max_completion_tokens=128;
   - context=512;
   - batch=8;
   - ubatch=8;
   - app foregrounded;
   - no manual gaps between requests;
7. copy the full diagnostic snapshot.

The next two profiles to test are:
- Flash
- +KQV

Safe and Full already have valid Build 55 evidence and need not be repeated
unless a regression appears.

## Interpretation

- If Flash approaches Full, Flash Attention accounts for most of the gain.
- If +KQV materially improves over Flash, KQV Offload contributes additional
  benefit.
- If Full materially improves over +KQV, Op Offload contributes additional
  benefit.
- If one step causes a disproportionately larger sustained drop despite a
  cold-speed gain, that component becomes the target for a future sustained
  policy experiment.

Build 56 is not permitted to silently add cooldowns, reloads, or automatic
profile switching. It is an isolation build only.
