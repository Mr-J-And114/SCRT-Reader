# Vdisc 解谜展示盘：ECHO 回声档案 — 游玩与验收指南

> 日期：2026-10-02。配套任务 ID `demo_echo`，故事盘 `site514_echo_V1.0_1.scp`。
> 用途：一条完整链路展示 Vdisc 解密系统全部能力（下载/权限/文件密码/四种 decode/radio/蒙混/上交/没收）。
> **剧透警告**：第 4 节包含全部谜题答案，试玩时请跳过。

---

## 1. 覆盖的系统能力

| 能力 | 展示点 |
|---|---|
| 任务发布与投递 | `debug 114514 vdisc mail M-DEMO-ECHO` 投递任务邮件（附件链接 + 备用命令） |
| 三种下载途径 | 邮件附件 / `download demo_echo` / modem `dial 9900-0003` |
| 下载弹窗 | 字符框、进度条、重下载确认（已领取时） |
| 探索进度 | `vdisc` 显示 read/total/百分比；`explore` 面板同口径 |
| 权限系统 | `unlock <口令>` 三级权限（sunrise/deepwater/lighthouse） |
| 文件密码 | `/reports/source.txt` 需口令 sandcastle |
| Decode | 凯撒（偏移 7）、Base64、维吉尼亚（SIREN）、摩斯（AIR 7083） |
| 无线电解码 | `radio_import` 触发器 + HF 7.083 摩斯信标（密码 lighthouse） |
| 文件操作/蒙混 | cp / mv / rm / mkfile（截留、塞垃圾），fake_pass 标记 |
| 上交判定 | 比例 + 必需文件 + 数量 + 体积；未达标提示缺口 |
| 发错角色 | 一般号码退回；`submit 1001-0001`（Ava）没收 + main 绩效 |
| 归档 | submitted / confiscated 移动归档 + 记录 |
| 搭档资源 | 自定义 loading_screen.json、触发器氛围文本、debug 重置 |

---

## 2. 快速开始

前提：已登录（任意账号；建议用测试账号）。

```text
debug 114514 vdisc mail M-DEMO-ECHO     # 投递任务邮件
mail                                    # 打开收件箱 → 点开《任务 ECHO：回收数据盘取证》
                                        # 点击正文中的「下载 Vdisc 附件」链接
                                        # 或输入 mail download M-DEMO-ECHO
scan                                    # 列表出现 [个人任务盘]
load <个人任务盘编号>                     # 加载（播放自定义恢复动画）
readme.txt                              # 从操作说明开始
```

其他领取途径（三者等价）：

```text
download demo_echo        # 桌面直接下载（联调本地源）
dial 9900-0003            # modem 拨号入口
```

### 常用辅助

```text
vdisc                     # 盘内：进度 / 任务要求 / 缺口 / 上交号码
debug 114514 vdisc check  # 原始判定明细
decode caesar 7           # 解码器（进入密文输入后可用 Ctrl+V 粘贴）
debug 114514 vdisc reset demo_echo   # 重置任务（重新体验）
```

---

## 3. 解谜流程（不剧透版）

1. 读 `readme.txt` 与 `docs/case_briefing.txt`，按提示到 `/logs` 找一级口令。
2. `unlock` 提升到一级权限后，侦查 `/comms` 与外发记录，得到凯撒线索。
3. 用 `decode` 破译 `/docs/caesar_note.txt`，其产物是 `/reports/source.txt` 的文件口令。
4. 解锁 `source.txt`，得到下一层的维吉尼亚关键词。
5. 破译 `/docs/vigenere_note.txt` 得到二级口令 → 进入 `/classified`。
6. 破译摩斯残片，得到频率线索；打开该文件时信号档案自动入库。
7. 弹出磁盘（`eject`），桌面输入 `radio`，调谐到指定频率，抄收信标。
8. 用信标口令提升到三级权限，阅读最终档案。
9. 确认关键物证齐全后 `submit <号码>` 上交。

---

## 4. 谜题答案速查（剧透）

| # | 位置 | 内容/操作 | 结果 |
|---|---|---|---|
| 1 | `/logs/maintenance.txt` | 记录 [047] | 一级口令 **sunrise**（`unlock sunrise`） |
| 2 | `/docs/caesar_note.txt` | 密文 `jhlzhy 7: zhukjhzasl`；`decode caesar 7` | 明文 `caesar 7: sandcastle` |
| 3 | `/reports/source.txt` | 文件密码 **sandcastle**；内容 `S0VZOiBTSVJFTg==`；`decode base64` | `KEY: SIREN` |
| 4 | `/docs/vigenere_note.txt` | 密文 `lef: hrwxnegwz`；`decode vigenere SIREN` | `two: deepwater` |
| 5 | — | `unlock deepwater` | 二级权限，开放 `/classified` |
| 6 | `/classified/morse_fragment.txt` | 摩斯 `.- .. .-. / --... ----- ---.. ...--`；`decode morse` | `AIR 7083`（打开该文件触发信号入库） |
| 7 | 桌面 `radio` | HF 7.083 MHz，正东方向，摩斯信标循环发报 | 明文 `ECHO BEACON VAULT PASSWORD LIGHTHOUSE` |
| 8 | — | `unlock lighthouse` | 三级权限，开放最终档案 |
| 9 | `/classified/project_echo.txt` | 读毕 | required_file 之一 |
| 10 | `submit 1001-0002` | 判定 | 成功：side +1、flag `demo_echo_done=1`、磁盘归档 |

**判定要求**（`demo_echo`）：探索 ≥ 60%、必需文件 `/reports/culprit.txt` + `/classified/project_echo.txt`、可见文件 ≥ 12、体积 ≥ 2 KB。
权限 3 时全部可见文件 14 个，全读约 6.3 KB，满足。

---

## 5. 玩法分支与验收清单

### 5.1 正常上交

```text
submit 1001-0002
```
- [ ] 成功后磁盘从列表消失，`saves/<用户>/vdisc/submitted/` 出现文件
- [ ] `perf` side 分 +1；`debug 114514 get_flag demo_echo_done` = 1
- [ ] 再 `download demo_echo` 被拒绝（防重复奖励）

### 5.2 发错角色

```text
submit 0000-0000     # 未知号码 → 不收回
submit 1001-0001     # Ava → 没收
```
- [ ] 未知号码仅提示，磁盘保留
- [ ] Ava 没收：磁盘移入 `confiscated/`，main 绩效 +1
- [ ] 重领 `download demo_echo` 可重置进度重新开始；归档记录保留

### 5.3 蒙混过关（数量+存在性设计）

达标流程中可任意操作：
```text
cp /readme.txt /logs/filler01.txt
cp /readme.txt /logs/filler02.txt     # 塞重复文件凑数量
rm /reports/draft_report.txt          # 截留不想交的文件
mkfile /reports/backup.log draft      # 伪造替代文件
submit 1001-0002
```
- [ ] 有任意修改的成功上交：`debug 114514 get_flag demo_echo_fake_pass` = 1
- [ ] 删除关键文件会导致判定失败（`/classified/project_echo.txt` 被删时列出缺口）
- [ ] 用垃圾文件顶替同名关键文件可通过（记录 fake_pass，供剧情区分）

### 5.4 未达标反馈

```text
submit 1001-0002   # 未达 60% 或未读关键文件时
```
- [ ] 输出缺口明细（探索进度不足 / 缺少必需文件 / 文件数量不足 / 数据包体积不足）
- [ ] 磁盘保留、进度保留，可继续探索后重试

### 5.5 重置与重玩

```text
debug 114514 vdisc reset demo_echo
download demo_echo
```
- [ ] 任务回到未领取；归档记录与 fake_pass 标记清除
- [ ] 邮件附件重复领取会触发"重新下载确认"（Y 确认 / N 保留）

---

## 6. 文件与数据索引

| 项 | 值 |
|---|---|
| 故事盘 | `SCRT/vdisc/site514_echo_V1.0_1.scp`（约 8.4 KB，ZIP） |
| 任务 ID | `demo_echo`（主线 `data/main/manifest.json` → `vdisc_tasks`） |
| 邮件 ID | `M-DEMO-ECHO`（`debug 114514 vdisc mail M-DEMO-ECHO` 投递） |
| modem 号码 | `9900-0003`（任务加载时自动注册） |
| 故事 ID | `echo_case` |
| 领取人 / 上交号码 | 神田玲 `1001-0002`（成功）/ Ava `1001-0001`（没收） |

盘内文件（14 可见 + 1 隐藏）：

```
readme.txt
docs/    case_briefing.txt  caesar_note.txt  vigenere_note.txt
logs/    intercept_log.txt  maintenance.txt  system_log.txt
reports/ draft_report.txt  source.txt(锁)  culprit.txt(权1)
comms/   outbound_log.txt(权1)  cipher_table.txt(权1)
classified/ morse_fragment.txt(权2)  project_echo.txt(权3)
radio/   beacon_echo.txt(隐藏，信号资源)
```

### 验证记录（2026-10-02，Godot 4.7.1 headless）

- StoryLoader 解析：22 条目（14 文件 + 6 目录 + loading_screen + 隐藏资源），story.id=echo_case ✓
- 判定脚本：全读 100% 通过；删除关键文件失败；mkfile 伪造通过（fake_pass 路径）；仅剩两文件时三项缺口 ✓
- 主场景 headless 启动：无脚本错误 ✓
