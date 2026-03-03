================================================================
  OB-7K 观测站 — 主线剧情数据目录
================================================================

本目录存放 SCRT-Reader 环境监测站主线剧情的所有数据文件。
作者可以通过 .scp 故事包覆盖或扩展此处的内容。

目录结构:
  data/main/
  ├── manifest.json         主线剧情清单（角色、对话、每日事件配置）
  ├── README.txt            本说明文件
  ├── dialogues/            额外对话脚本（按天数或事件组织）
  │   └── day_XX.json       第 XX 天的对话数据
  ├── mail/                 系统邮件模板
  │   └── mail_id.txt       邮件内容（支持 Header 格式）
  └── assets/               美术素材（角色头像、背景等）
      └── *.png             图片资源

================================================================
  manifest.json 格式说明
================================================================

manifest.json 包含以下顶级段落:

1. daily_dialogues — 每日对话触发配置
   键为天数编号（字符串），值为触发配置:
   {
     "1": {
       "on_start": ["dialogue_id1"],        // 每天加载时触发
       "on_scan_complete": ["dialogue_id2"], // env scan 完成后触发
       "on_anomaly": ["dialogue_id3"]        // 检测到异常时触发
     },
     "default": { ... }  // 没有特定配置的天数使用此默认
   }

2. comm_characters — 角色定义
   与 .scp 故事包格式相同:
   {
     "character_id": {
       "name": "显示名称",
       "title": "头衔",
       "voice": { "tone": "sine", "base_pitch": 0.85, ... }
     }
   }

3. comm_dialogues — 对话内容
   与 .scp 故事包格式相同:
   {
     "dialogue_id": {
       "title": "对话标题",
       "callable": false,
       "repeatable": false,
       "lines": [
         {
           "character": "character_id",
           "text": "对话文本（支持 BBCode）",
           "speed": 30,
           "action": "glitch",        // 可选：触发屏幕效果
           "auto_next": 0.5           // 可选：自动推进延迟
         }
       ]
     }
   }

================================================================
  如何制作剧情模组
================================================================

1. 创建 .scp 故事包（ZIP 格式）
2. 在 manifest.json 中添加 daily_dialogues 段
3. 添加 comm_characters 和 comm_dialogues 段
4. 故事包中的定义会覆盖/追加主线剧情
5. 每天的对话可以引用故事包中定义的任何对话 ID

示例: 在 .scp 的 manifest.json 中追加第 5 天的特殊剧情:
{
  "daily_dialogues": {
    "5": {
      "on_start": ["custom_day5_intro"],
      "on_scan_complete": ["custom_day5_result"],
      "on_anomaly": ["custom_day5_panic"]
    }
  },
  "comm_dialogues": {
    "custom_day5_intro": {
      "title": "自定义第5天",
      "lines": [ ... ]
    }
  }
}

================================================================
  游戏流程说明
================================================================

每天的流程:
  1. 启动终端 → 自动显示当日天气和事件信息
  2. 触发当日 on_start 对话（如有）
  3. 玩家输入 env scan → 自动执行所有检测任务
  4. 扫描完成后触发 on_scan_complete 对话
  5. 如检测到异常，触发 on_anomaly 对话
  6. 玩家自由探索（查看文件、邮件、仪表盘等）
  7. 关闭终端
  8. 下次启动自动进入下一天

理论上可以无限延伸天数，只需在 daily_dialogues 中
添加更多天数的配置即可。未定义的天数使用 default 配置。
