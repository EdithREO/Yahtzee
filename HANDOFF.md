# YachtDuel 本地版技术交接
更新日期 2026-11-03。本文件用于从本地双人版继续开发联机对战。先读项目根目录 AGENTS.md、PROGRESS.md 和本文件，再核对实际代码。本文记录不代替现场检查。

## 1. 当前项目与版本
- 编辑源码 F:\GA\YachtDuel。主场景 main.tscn，入口脚本 game.gd，计分规则 rules.gd。
- Windows 运行副本 F:\GA\YachtDuel\Windows\YachtDuel.exe。运行副本含俯视镜头、骰面深度遮挡、顶部排序点数图标，但尚未包含最新空闲渲染优化。
- 较早工程、测试副本和发布 ZIP 在 C:\Users\25778\Documents\Codex\2026-11-01\godot-4-gdscript-windows-godot-codex 下。不得以这些旧工程覆盖 F 盘源码。
- 本次现场 Git 检查返回非仓库，未初始化 Git，无提交哈希。是否启用 Git 由用户决定。
- 本次核对 game.gd SHA256 为 F0EE93373FED2172A5D768ABC57732E9E86DA36194432CDB8F8EC5986BB68AC9，运行 exe 为 49AA6824310C8FE5E8EDFF649F2D1C65E76A030B2CA6AD83EEED372482D5E10F。后续修改后这些指纹自然失效。
- 引擎已使用 Godot 4.7.2 Steam 版，GDScript，GL Compatibility 渲染。project.godot 内设计尺寸 1440×900，窗口默认 1200×750，canvas_items 缩放。
- 本机引擎 F:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe。export_presets.cfg 有 Windows 导出预设，资源嵌入 exe。再次运行或构建需符合本次用户授权。
- 当前 game.gd、rules.gd 未发现 RPC、ENet、WebSocket、身份验证、房间或存档代码。当前对战是同机轮流操作。

## 2. 已实现玩法与计分
每人 12 个计分项目，共 24 个玩家回合。玩家交替操作，每回合最多投三次，可以提前选一项记分，每项每人只能填写一次。条件不满足可填零，全部填写后总分高者获胜，可平局。

rules.gd 中 YachtRules 的实际规则：
|索引|项目|得分|
|---|---|---|
|0–5|一至六点|相应点数之和|
|6|全选|五颗点数之和|
|7|四条|至少四颗相同，五颗点数之和|
|8|葫芦|恰好三颗相同加一对，25|
|9|小顺|存在四个连续点数，30|
|10|大顺|存在五个连续点数，40|
|11|快艇|五颗相同，50|

上栏小计至少 63，加 35 分。无额外快艇奖励或 Joker 实现。规则与界面说明一致，联机接续不得擅自改变计分版本。

## 3. 代码入口和真实状态
game.gd 在运行时构建界面和 3D 世界。main.tscn 只有挂载脚本的根 Control。
- _setup_ui 创建计分板、顶部 2D 骰子图标、3D SubViewport、底部骰子按钮、投掷/规则/重新开始。
- _setup_world 建立相机、木纹桌面、绿绒骰盘、空气墙、灯光和五颗骰子。
- _new_game、_begin_turn 初始化对局和回合。
- _roll 发起未保留骰子的物理投掷，_on_all_settled 读取实际朝上面，写入 values。
- _toggle_hold 是实体骰子、顶部图标和底部按钮共用的保留/取消入口。有动画，保留骰子冻结并移至右侧浮空位置，取消时回到 parked 记录的位置。
- _commit_score 校验当前玩家、busy、次数和项目占用，写 scores 并切换回合或结算。
- _cancel_roll 清除物理状态；generation 用于取消被新对局替代的异步操作。
- _refresh_icons、_refresh_stage、_update_ui 刷新展示，_on_stage_input 做鼠标射线选取，射线排除透明空气墙。

关键状态：
|字段|意义|
|---|---|
|dice[0..4]|固定槽位的五颗实体骰子|
|values[0..4]|相同槽位的实际点数；0 表示尚无有效结果|
|held[0..4]|相同槽位的保留状态|
|parked[0..4]|保留前实体变换|
|icon_order|仅展示排序，按点数再按槽位排序|
|scores[2][12]|null 为未填写，整数 0 为已填写零分|
|player|当前玩家，0 或 1|
|rolls|本回合已投次数|
|busy、over|动作进行中、对局结束|
|generation|异步动作取消代次|
|entering|从盘外入场且尚未恢复左墙碰撞的骰子|

顶部排序不得改写 values、held 或 dice 的顺序。重复点数的图标仍绑定不同骰子槽位。联机事件应引用稳定骰子 ID，不能引用“排序后的第几颗”。

## 4. 物理与防卡
复用 addons/dice_3d，核心 DiceRollBox3D、DiceDie3D、DiceDieDefinition3D。上游 https://github.com/dl-devworks/dice-3d，插件 LICENSE.md 为 CC0。当前插件含本项目局部修改，不能直接覆盖为上游版本。

现场参数：
- 骰子边长 0.8；骰盘空气墙内尺寸 5.5×6×5.5，底面 y=0。
- 重力 20，骰子/地面摩擦 0.38、弹性 0.28；侧墙摩擦 0.25、弹性 0.65。
- linear_damp 0.55，angular_damp 0.9，连续碰撞检测开启。
- 左侧盘外上二下三入场位置在 START。水平冲量 14–17，向下冲量 −2 至 −0.8，初始各轴角速度 −13 至 13。
- 初始朝向 _random_basis 为六个朝上面×四种水平转角中的随机一种。
- 单向入口通过每颗骰子对左墙的碰撞例外实现，进入后 local x > −2.05 即恢复碰撞。
- 线速度≤0.1、角速度≤0.15 持续 0.35 秒后检查落稳，平面阈值 0.985。
- 低速倾斜时施加小转矩，附近骰子或墙边增加水平分离小冲量。6 秒未结束时，仅恢复一颗问题骰子，其余冻结；超过三次恢复进入 _roll_failed。
- 插件 dice_die_3d.gd 已增加 not freeze 重力判断，防止待投时累积重力造成第一次投掷高速下坠。
- 该脚本 wait_for_flat_result 让倾斜骰子继续等待。点数通过六个面法线与向上方向的点积确定。
- 骰点材质改为 alpha scissor，修复透明圆点片的前后遮挡。

联机必须明确物理结果权威来源。同一随机种子不能保证不同设备得出相同刚体碰撞结果。网络同步方式尚未选定。

## 5. 画面、声音与性能
- 相机近俯视正交，位置 (0.55,10,2.5)，look_at (0.55,0,0)，size=6.9。
- 明亮木色桌面、绿色程序噪声绒面、深色盘壁。字体用系统 Microsoft YaHei / Noto Sans CJK SC / Arial 回退。
- 声音在 audio 本地目录。上游 README 将其骰子声音归于 Kenney，CC0；来源说明见原上游 README。碰撞随机四段 die-throw，音量 −17dB，至少间隔 170ms，低速接触不播放。抓取音为 dice-grab-1，胜利音为程序生成和弦。
- 最新源码 _refresh_stage 在空闲时 UPDATE_ONCE，动作进行时 UPDATE_ALWAYS；尺寸和程序纹理变化也触发刷新。新增联机接收处理若直接改变 3D 展示，须在适当时机调用此刷新，避免状态已同步但画面未重绘。
- RX 7700 XT、1200×750 窗口的短时有画面源码测试，优化前空闲约144 FPS、投掷约143 FPS；优化后约144 FPS。空闲绘制调用约131降至90，投掷约131。没有 GPU 占用百分比，不能称用户卡顿已解决。
- 导出运行版未成功加载外部诊断脚本，以上帧率来自源码场景。此前进程抽样不能替代完整分阶段 CPU/GPU 测量。

## 6. 已有测试证据与限制
以下均为历史证据，本次交接没有重新启动或测试游戏。
- 本地初始版曾验证完整24个玩家回合、计分、保留和取消，以及导出启动；见对话历史，不能直接等同当前联机验证。
- 俯视及排序图标修改后，测试副本2,000次首投全部有效。1–6点合计1677、1640、1655、1619、1687、1722。逐颗等频卡方值5.110、4.582、4.072、5.524、5.788，df=5，未发现显著偏差。
- 更早50,000次概率测试来自旧物理测试项目，不属于当前双人版，不能作为当前版本公平性认证。
- 快速退出测试曾报告 Ogg playback 和资源引用未释放。20次诊断复现，先 queue_free 场景再实际等待350ms并处理帧后警告消失。该处理在测试脚本，不能宣称游戏所有退出场景都已修复。
- 空闲渲染优化验证过投掷、选择、重新开始的刷新模式。用户感到的卡顿仍待进一步定位。

证据目录：
C:\Users\25778\Documents\Codex\2026-11-01\godot-4-gdscript-windows-godot-codex\work\duel_view_test
本次确认 stats.log、diag.log、drain.log、source-base.log、opt.log、perf_verify.log 存在。该目录是测试副本，不能覆盖正式源码。

## 7. 备份与恢复
本次确认以下局部备份目录存在，位于 F:\GA\YachtDuel-backups：
- 20261103-164828-tray-view：俯视、排序图标任务相关脚本和原进度。
- 20261103-165155-audio-exit-release：旧 exe、旧交付 ZIP、原进度。
- 20261103-171244-idle-render：空闲优化前 game.gd、原进度。

这些是局部任务备份，不是完整版本备份。回退前先备份当前成果，逐项比较，仅恢复必要改动；不能整份覆盖后续任务成果。历史交付 ZIP 可能落后于源码。

## 8. 联机开发接续
当前没有通信协议或部署方式。开始架构修改前，应确认用户希望的联机范围（局域网/互联网）、房主或服务器的运行位置、加入房间方式。登录、断线重连、版本校验等需求也需要明确范围。

可讨论的方案是由单一权威端执行合法操作和结果结算，客户端提交投掷、保留、计分请求，接收状态与表现数据。此处仅为设计建议，尚未获选定、实现或验证。
需要保护的状态包括玩家身份与座位、回合、投掷次数、五颗骰子的ID/点数/保留状态、已占用项目、分数、比赛结束状态和状态版本。
接收方须验证轮到谁、请求身份、操作阶段、剩余次数、项目是否已填写，以及重复或过期请求。玩法状态和展示排序应区分。
实际物理变换同步或结果动画回放的取舍须先确认。不要假定两端独立投掷会一致。
本次仅整理交接，没有初始化仓库、引入联网依赖、改计分或同步运行包。下一会话先核对本文件和实际源码，再进行已授权的局部开发。

## 9. 手动入口
在 Godot 中导入 F:\GA\YachtDuel\project.godot，主场景 main.tscn，按 F5。运行副本可打开 Windows\YachtDuel.exe，但缺少最新空闲渲染优化。运行、测试、构建及部署均遵循本次用户授权。

## 2026-11-03 更新：权威轨迹播放
已完成本地房间、局域网入口及服务器权威物理轨迹与Godot Web插值播放。早期章节“无联网”等描述为历史记录，当前入口为 start_room_test.bat，房主开始后点击投骰。详见 PROGRESS.md 最新条目与 room/PLAYBACK.md；跨设备Wi-Fi验证仍待完成，Windows EXE与单机Web目录未同步联网功能。

## 2026-11-03 更新：双人回合
现已由服务器随机选择先手，验证三投上限、保留、计分与回合切换；网页显示共享计分表，非当前玩家只能观看。状态和协议测试及双网页验证通过，详见room/TURNS.md及最新进度。原Windows EXE/单机Web未同步本阶段联网功能。

## 2026-11-03 更新：概率验证
双人回合功能完成，追加5000次检查暴露的全组停稳复核/冻结恢复问题已修复；最终完整5000次0失败0异常，逐骰卡方无显著偏离。详细数据及限制见最新PROGRESS.md和同级YachtDuel-backups/20261103-probability-5000/PROBABILITY_5000.md。全部阶段日志保留，未初始化Git。

## 2026-11-05 当前目录与正式入口（取代旧路径说明）
- 根目录只有单机、Web联机、共享资源库。具体入口与共用源码维护方法见根README.md。
- 唯一共用源：共享资源库/源文件；Web专用源：Web联机/源码/room。两个“工程”目录为自动生成副本，不作为独立维护源；共享资源库/工具/build.ps1自动同步/构建。
- Windows运行版：单机/Windows/YachtDuel.exe；网页发布：Web联机/发布/viewer。运行脚本：单机/start_game.bat、Web联机/start_server.bat、stop_server.bat、start_game.bat。
- 新增权威last_scored与score_revision仅表示成功计分展示/音效；nullable scores的0与null仍严格区分。Web确认声以成功revision变化触发，连接恢复只建立基线。完整最新证据/未验证内容见PROGRESS.md最后条目。
- 旧布局完整保存在F:/GA/YachtDuel-backups/20261105-001929-three-folders/迁移前工程。不要恢复旧包覆盖当前源码。账号令牌仍在用户目录，不在共享源。

## 2026-11-05 当前英文目录（替代此前中文路径）
- SinglePlayer/start_game.bat → SinglePlayer/Windows/YachtDuel.exe。
- WebMultiplayer/start_server.bat、stop_server.bat、start_game.bat；实际Godot工程WebMultiplayer/project，专用源WebMultiplayer/source/room，网页发布WebMultiplayer/public。
- 唯一共享源Shared/source，构建脚本Shared/tools/build.ps1；两个project目录自动生成。当前计分确认声为score-confirm.wav（Christopherderp，CC0），不是先前提出的bubaproducer文件。
- 完整迁移前布局与日志：F:/GA/YachtDuel-backups/20261105-004433-english-confirm-audio。历史备份和文档中的旧路径仅用于追溯，以根README为当前使用说明。
