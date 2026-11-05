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

## 音效署名

计分确认音使用 Christopherderp 的 “Videogame Menu BUTTON CLICK”，CC0 1.0。来源：https://freesound.org/people/Christopherderp/sounds/342200/ 。用户提供的 WAV 原样保存为 `Shared\source\audio\score-confirm.wav`。完整说明为同目录 `ATTRIBUTION.md`，构建时自动放入两个资源包并复制到 Windows 与网页发布目录；网页可访问 `/ATTRIBUTION.md`。

游戏界面中文、其他音效、规则和联机行为保留。第三方插件内部文件、引擎及依赖名称保持上游原样。

账号令牌仍在用户目录 `.cpolar`；工具、动态地址和运行记录在 `%LOCALAPPDATA%\YachtDuel`，不放入 Shared。公网地址随隧道启动变化，以当前启动输出/地址文件为准。

历史备份仍在工程外 `F:\GA\YachtDuel-backups`。本次英文命名前完整布局保存于 `20261105-004433-english-confirm-audio\pre-migration`，未改名或删除历史备份。