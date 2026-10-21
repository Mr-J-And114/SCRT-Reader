# 现有仓库接入与日常同步

正式同步目标为连接现有 GitHub 仓库的 `SCRT-Reader-remote` 工作目录。原始独立 Core 工作区保留作迁移恢复点，不再作为日常同步目标。不要新建 GitHub 仓库，不需要强制推送，也不要合并不相关历史。

## 日常同步

在正式工作目录根执行。来源参数指含 SCRT 子目录的私有仓库根目录，路径仅通过本机命令传入，不保存到公开配置。

```powershell
python public-sync/sync_public.py --dry-run --source "<来源仓库>"
python public-sync/sync_public.py --sync --source "<来源仓库>" --godot "<Godot-4.7.1可执行文件>"
python public-sync/sync_public.py --verify
git diff
git status --short
```

无变化 sync 零写入；有变化时只更新登记生成文件并执行隔离引擎门禁。人工维护的工具、文档、规则与覆盖层不由同步器覆盖。适配来源变化时只报告对应文件、SHA 和行号，需局部审阅。普通通用代码更新无需 AI。

同步后在 GitHub Desktop 检查 Changes，选择完整的本次变更。在暂存后再次执行 --verify；索引和工作树必须一致。不要强制添加本地同步状态、缓存、存档或故事盘。

## 本次替换提交

origin 已指向 https://github.com/Mr-J-And114/SCRT-Reader.git，分支为 main。现有历史保留，本次新树完整替换旧文件。所有变化统一暂存，尚未提交或推送。

1. GitHub Desktop 选择 File → Add local repository，打开 `SCRT-Reader-remote`。
2. 检查 Changes 中的旧文件删除及 Core 新增/修改。旧版的大量删除是预期结果。
3. 提交说明填写 `Replace legacy project with SCRT-Reader Core`，点击 Commit to main。
4. 点击 Push origin。若显示远端有新提交，先停止并处理同步，不要强制推送。

提交前可执行 `git diff --cached --stat` 与 `python public-sync/sync_public.py --verify`。工具不会自动 commit 或 push。

## 历史审核范围

作者接受的 Legacy History 基线固定为 `b2ab2af987339d73fa39849608bfbe5e5c5b3828`，仅限该提交及其祖先，并绑定上述 origin。基线之后所有可达新提交逐个检查完整文件树；即使重新引用旧 blob 也不豁免。当前工作树、索引、规则、覆盖文件和本地同步摘要保持严格检查。没有关闭历史扫描的通用开关。

本次只保证新的 main 文件树符合 Core 无剧情规则，旧历史未清除，旧内容仍可通过历史访问。不要把保留的旧历史当作合法公开资源来源。此说明不代表旧历史已获得新的内容或素材授权。

## 一次性状态迁移

迁移已经完成，日常操作不需要重做。迁移入口 `--adopt-verified-core "<已验收原Core目录>" --source "<来源仓库>"` 仅允许没有本地状态的新目标，先审核两个工程，再验证原 Core 所有权记录、私有来源指纹及双方生成文件字节，重新计算状态。它拒绝目标差异、原 Core 漂移、未知文件和已有状态，不复制旧状态中的路径或引擎记录。

运行验证及尚未覆盖的范围见 [验证记录](VALIDATION.md)。
