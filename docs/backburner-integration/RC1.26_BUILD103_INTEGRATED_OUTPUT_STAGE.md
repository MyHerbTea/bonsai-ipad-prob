# Bonsai RC1.26 Build103 — 集成输出预算与全阶段回归

## 本版定位
从 Build102 B16/B24/B16 真实 ABA 实验继续；不是重新做零碎 Batch 参数测试，也不是未经认证便把 B32 提升为默认。Build102 的 B24 Prefill 改善约 32%，保留它作为候选性能基线，继续保留 SAFE4 的粘性恢复机制。

Build103 的正式变更：
1. 用户在 iPad “输出长度 · OpenAI API”设置的最大输出 Tokens 现作为**没有携带 `max_tokens` 等字段的 API 请求的默认值**；显式请求仍经过服务端配置上限校验。
2. 去掉 `ProductionView` 在调用引擎前强制 `min(payload.maxTokens,256)` 的真实推理限制。
3. 文本路径在分词后以真实 prompt token 数计算最大剩余生成预算；视觉路径在原生 Prefill 阶段仅预留一个 token，通过后依据图像的 position 和 KV 双维度裁剪，从而避免高默认预算虚假拒绝。
4. Diagnostics 显示真实 iPad UI output token 上限；模型发现 metadata 同步。
5. 综合回归由单一工具一次完成：文本、SSE、默认输出、显式 384 输出、多轮、长输入、1–3 图、图后文本，自动汇总并导出 ZIP。

## 一次运行
在 iPad 上启动本版 OpenAI LAN API（端口 8080，保持网络畅通）。Windows 中解压 `Bonsai-Build103-FullStage-Runner.zip`，双击 `RUN_BUILD103_FULL_STAGE.cmd`。如果尚未设置环境变量，会询问一次 API Key，不写入结果或源代码。默认自动尝试常用的局域网 IP；必要时只需设置 `BONSAI_BASE_URL` 和 `BONSAI_API_KEY` 环境变量。图片可选：默认尝试 `D:\apple\vision_test_01_people_landscape.png`，也支持 `BONSAI_VISION_IMAGE` 指定文件。报告写入 `RESULTS/Build103-FULL-*/FINAL_REPORT.md`，并生成对应 ZIP。

## 验收门槛
- 源码契约测试及 iOS Release 编译通过；
- API/文本/SSE/多轮不应失败；视觉必须在有实际图片、视觉权重并启用 Vision 时验收，否则明确 SKIP；
- 不带输出字段应继承 iPad UI 配置的限制，不得默认为 256；
- 指定 `max_tokens:384` 不能被隐藏的 256 限制截断；如果模型主动结束，此项记为 INCONCLUSIVE 而不是虚假 PASS；
- 长文本请求不应因过大**默认**输出预留而被不必要拒绝；必要时动态裁剪到剩余 Context；
- KV reuse failure `post_generation_tail_trim_failed` 必须持续记录，不冒称已修复。
- 峰值 Metal 内存、App 真机崩溃/重启恢复与长时间稳定性仍必须真机审核，不能只看来源于 HTTP 的静态与采样数据。

## 实验限制
Build103 不代表 B24 已取得全部长上下文与视觉生产认证，B32 没有在 Build102 ABA 中验证。自动化脚本**不会**更改下一次启动的 Batch 分支，不会要求用户进行 B8/B16/B24/B32 各自重新配置。请避免把 Build102 的 939-token 性能测量外推为 32K 满载真实性能。
