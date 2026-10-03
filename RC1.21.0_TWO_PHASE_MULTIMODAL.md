# RC1.21.0 — Two-Phase Multimodal Runtime

## Frozen parent

RC1.20.7 is preserved on frozen-v1-rc1-20-7-text-api after real-device PASS:
- OpenAI chat completions
- stream=false
- true incremental SSE
- include_usage
- native reasoning_effort=none
- stable prewarmed 27B text runtime

## Problem isolated by RC1.20.x

The iPad M5 terminates the process when mtmd_init_from_file(mmproj, full_27B_model, ...) is attempted while the full model is resident.

Therefore RC1.21.0 makes that coexistence architecturally impossible.

## Phase A — projected image cache

On a new image:
1. release the 27B model/context;
2. load the GGUF vocab only;
3. load Q8 mmproj with CPU projector;
4. decode/encode the image;
5. persist projected float embeddings + relative M-RoPE positions as the existing BVCACHE1 format;
6. release bitmap, mtmd, vocab-only model;
7. reset llama backend completely.

The cache key is already content-addressed:
SHA256(image bytes + model identity + mmproj identity + image token tier).

## Phase B — stable resident language runtime

After Phase A:
1. recreate the RC1.20.7 27B text runtime;
2. load BVCACHE1 only — mmproj is never opened;
3. clear the llama context;
4. prefill text prefix;
5. inject cached image embeddings and M-RoPE positions directly through llama_decode;
6. prefill the user question + native non-thinking assistant prefix;
7. generate with the existing Swift sampler / true SSE path.

## Fast path

For the same image + model + mmproj + quality:
- BVCACHE hit;
- keep 27B resident;
- do not load vocab-only model;
- do not load mmproj;
- do not reload 27B;
- directly prefill cached image embeddings and generate.

This is the primary performance path for repeated questions about the same image.

## Initial device gate

RC1.21.0 intentionally fixes LAN multimodal to the already-proven 512 visual tier (128 image tokens) for the first lifecycle test. 768/1024 and projector GPU acceleration are performance follow-ups only after this exact architecture passes on the M5.
