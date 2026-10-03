# Bonsai iPad Lab v1 RC1

目标：把已经在 M5 iPad Pro 12GB 上验证通过的 Bonsai 2 27B PTQ1_0 真机基线，升级成一次部署后可在界面调参的长期测试 App，并加入可选 Vision Beta。

## 已冻结的安全基线

此前真机已经验证：

- Prism runtime / Metal GPU offload：PASS
- Ternary-Bonsai-2-27B-PTQ1_0.gguf：PASS
- n_ctx=256, n_batch=16, n_ubatch=16, swa_full=false
- GGML_METAL_TENSOR_DISABLE=1
- 真实 decode / token generation：PASS

Lab v1 保留 Safe 预设，不覆盖这个成功基线。

## Text Lab

界面可配置：

- Context
- Batch
- uBatch
- GPU Layers
- Flash Attention
- SWA Full
- KQV / op offload
- M5 Metal Tensor API workaround
- Max Tokens
- Temperature
- Top P
- Top K
- Min P
- Repeat Penalty
- Seed
- System Prompt / User Prompt

修改运行参数后，点“应用配置并重载模型”。不需要重新构建 App。

## Vision Beta

使用固定 Prism XCFramework 内置的 libmtmd：

- 选择独立 mmproj GGUF
- 可选 mmproj GPU offload
- 可配置 Image Max Tokens
- 选择单张图片
- 输入问题
- 执行单图问答

12GB iPad 首次建议：

- 主模型：PTQ1_0
- Runtime preset：Vision Safe
- mmproj：优先 Q8_0
- Image Max Tokens：128
- Max New Tokens：64 或 128

## 诊断

所有关键阶段写入 BonsaiLabLastStage。若 iPadOS Jetsam / native crash 导致 App 直接退出，重新打开即可查看最后阶段。

## 交付门禁

GitHub Actions 会依次执行：

1. 固定 Prism XCFramework 下载 + SHA256 校验
2. Swift parser preflight
3. XcodeGen
4. Xcode 16.4 真机 Release build
5. 检查 llama.framework 中 mtmd_init_from_file / mtmd_helper_eval_chunks 符号
6. 仅 BUILD SUCCEEDED 后打包 unsigned IPA
7. 上传 Artifact

主分支不修改；RC 在独立 lab-v1-rc1 分支验证。


Build gate trigger: RC1.
