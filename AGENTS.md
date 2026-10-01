# SCRT Godot 项目模型分流规则（2026-09-03 实测确认）

## 模型分工

| 任务 | 模型 | 说明 |
|---|---|---|
| 复杂任务（架构、多文件调试、深度推理） | 主模型 opencode-go/deepseek-v4-pro | 自己处理 |
| 高质量编程（主模型不够用时） | chatst/glm-5.3 | 比 Terra 便宜 40-56%，100 万上下文 |
| 快速编程 | chatst/glm-5.3-flash | 中等复杂度，速度优先 |
| 常规编码（小重构、注释、单文件修复、样板代码） | @junior = opencode/nemotron-3-ultra-free | 实测免费模型里质量最佳 |
| 快杂活（短文本、总结、格式转换、标题） | @quick = opencode/big-pickle | 实测最快（约 2-5 秒）、省 token |
| 识图/OCR/截图/图表 | @vision = opencode/mimo-v2.5-free | 全模态 |
| 爬虫/资料检索/文档通读 | @scraper = opencode/ling-3.0-flash-fin-free | 快但网关不稳，见下 |
| 代码库探索定位 | @explore（已配免费模型） | 大 token 消耗，白嫖 |

## 分流规则

- 委派条件：任务边界明确、不涉及全仓库联动、不涉及机密数据；委派前在描述里给出明确的输入与验收标准
- @junior / @quick 失败或结果质量不合格时，主模型自己接手，不要让免费模型反复重试
- @scraper 遇 503/429 时等 60 秒重试 1 次，仍失败则主模型用 webfetch 自己处理
- 机密数据（密钥、未发布代码、敏感信息）一律主模型处理，禁止发给免费模型
- 免费模型限流严重（实测约 15 次请求/短时触发 429），禁止对免费模型批量或并行调用；单个任务串行委派

## 已排除模型（实测确认不可用）

- muse-spark-1.3-contributor-free / muse-spark-1.2-contributor-free：不挂 VPN 报 RegionError（地区限制）；挂 VPN（德国）后仍出现连接中断/HTTP 500/空输出，实测不可用，勿再尝试
- nemotron-3.5-lightning-free：实测泄露思维链、跑题、慢（24 秒），不用于任何正事

## 本项目的代码约定提醒（分流时传递给子代理）

- Godot 4 GDScript；插件代码在 addons/agent/ 下；@tool 脚本注意工具模式运行
- 修改涉及 API 请求/信号连接的代码时，提醒子代理检查信号重复连接、URL 拼接、错误码处理三处历史 bug 点

## ChatST GPT 每日免费额度（重要）

- 复杂文学创作（小说、诗歌、剧本、长文润色、文风要求高的内容）：不要用主模型或免费模型直接写；先提醒用户："建议用 @writer（ChatST 的 GPT，有每日免费额度）或去 ChatST 使用 GPT 完成"，用户同意时委派给 @writer
- 追踪文件：`C:\Users\29065\.config\opencode\chatst_quota.md`
- 每天第一次会话开始时读取追踪文件；若没有今天的记录或状态为"未使用"，提醒用户一次："今天 ChatST 的 GPT 免费额度还没用，建议把写作类任务交给 @writer 或用掉额度"
- 用户通过 @writer 完成任务或明确表示额度已用后，把当天状态更新为"已使用"并补一句用途；追踪文件只保留最近 3 天记录
- 每天只提醒一次，不要反复唠叨
