# 内容包

内容包是 ZIP 文件，可使用 .scp 扩展名。建议采用 UTF-8 文件名和 UTF-8 JSON/正文。包根目录的 manifest.json 可包含 story 对象（id、title、version）、虚拟 files 对应的实际文本文件，以及通用 comm_characters、comm_dialogues、camera_system、vdisc_tasks 等扩展数据。具体可用字段由 StoryLoader、CommManager 和各管理器的 load_from_manifest 实现定义；缺省数据使用空字典或空列表，不会提供内置剧情。

最小示例：包中包含 manifest.json 和 welcome.txt。

```json
{"story":{"id":"example","title":"Example","version":"1.0"}}
```

welcome.txt 可写普通文本，或使用 CRTML 标题与颜色标记。注册、登录后输入 scan，按 load 的帮助加载，再使用 ls、open 等命令浏览。

不要在包中放入账号数据、个人配置或无再分发权限的资源。脚本模组不是安全沙箱；只有信任作者时才运行。
