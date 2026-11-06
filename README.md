# YachtDuel

- 单机：双击 `SinglePlayer\start_game.bat`，运行 `SinglePlayer\Windows\YachtDuel.exe`，无需服务器。
- 公网服务器：双击 `WebMultiplayer\start_server.bat`，等待窗口显示本次 `PUBLIC GAME` HTTPS 地址。
- 网页游玩：双击 `WebMultiplayer\start_game.bat`，自动打开当前可用地址；服务未就绪时明确提示。
- 停止服务：双击 `WebMultiplayer\stop_server.bat`。会结束当前房间；启动窗口按 Enter 或关闭窗口也会清理本项目服务。

## 源码与构建

`Shared\source` 是两版共用游戏代码、骰子、字体和声音的唯一维护来源；`WebMultiplayer\source\room` 是仅联机使用的服务器、客户端适配和代理源码。

`SinglePlayer\project` 和 `WebMultiplayer\project` 是自动同步生成的 Godot 工程，可在编辑器中查看验证，不另行手工维护。构建前自动同步共享资源：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File F:\GA\YachtDuel\Shared\tools\build.ps1 -Target All -Export
```

两边各自也有 `build_game.bat`。导出后得到最新 Windows EXE 与 `WebMultiplayer\public\viewer` 网页包/gzip；代理提供 `WebMultiplayer\public`。启动服务器前自动同步工程，并检查运行进程源码版本；更新服务端后应先结束对局、停止旧服务再启动。

## 扩展技能

每局开始时两位玩家各确认一项技能。双方确认后开始投骰，重新开局时重新选择。

- **四面骰？** 每局可用一次。自己回合中任意一次投掷前，点击「四面骰？」并在骰盘上点选两颗骰子。选中时显示红色描边，点「确定（2/2）」后才换成正四面体。本回合内它们的结果只有 4、4、5、6。已保留的选中骰子会取消保留，替换后须再投一次才能计分。
- **黑幕啊** 每局可用一次。自己回合使用后，对手会看到「你被黑幕了」。对手的下一回合有三颗随机骰子变黑并隐藏点数，即使换成四面骰也保持黑色。计分表照常显示。
- **生化危机** 每局可用一次。在自己的回合投完第二次之前，点选一颗骰子作为母体。母体最多感染直接碰到的 3 颗其他骰子，它们计分时都跟随母体的最新点数。被感染的骰子不会继续传播。发动回合最多投两次，回合结束清除感染。
- **跨时空救援** 每局可用一次。自己回合投掷后点选一颗骰子记录点数。本回合只记录，接下来两个自己的回合各在冻结区获得一颗同点的蓝色玻璃骰。有玻璃骰时，计分前手动排除六颗中的任意一颗，其余五颗照常计分。重新投掷后需要重新选，回合结束时玻璃骰消失。

在 `Shared/source/match_skills.gd` 的 `CATALOG` 中用唯一且稳定的 ID 注册技能名称和描述。两版从同一目录生成选项，`select_skill(seat, skill_id)` 校验并锁定选择。新增效果时，在对应的游戏操作中读取 `skills.skill_for(seat)`。单机操作在 `Shared/source/game.gd`，联机操作由 `WebMultiplayer/source/room/match_state.gd` 和服务器处理。联机客户端只发送所选 ID，服务器按已认证的座位记录，并通过状态快照同步给两端。

## 音效署名

计分确认音使用 Christopherderp 的 “Videogame Menu BUTTON CLICK”，CC0 1.0。来源：https://freesound.org/people/Christopherderp/sounds/342200/ 。用户提供的 WAV 原样保存为 `Shared\source\audio\score-confirm.wav`。完整说明为同目录 `ATTRIBUTION.md`，构建时自动放入两个资源包并复制到 Windows 与网页发布目录；网页可访问 `/ATTRIBUTION.md`。

游戏界面中文、其他音效、规则和联机行为保留。第三方插件内部文件、引擎及依赖名称保持上游原样。

账号令牌仍在用户目录 `.cpolar`；工具、动态地址和运行记录在 `%LOCALAPPDATA%\YachtDuel`，不放入 Shared。公网地址随隧道启动变化，以当前启动输出/地址文件为准。

历史备份仍在工程外 `F:\GA\YachtDuel-backups`。本次英文命名前完整布局保存于 `20261105-004433-english-confirm-audio\pre-migration`，未改名或删除历史备份。
