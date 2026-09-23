# 键盘诊断模板

五个脚本均为本地诊断工具，不更改驱动、注册表、防护服务或启动设置。默认自动结束，不默认保存字母、数字键码。Windows PowerShell 5.1 和 PowerShell 7 已完成启动及退出实测。

| 入口 | 功能 | 默认时长 |
|---|---|---|
| Diag-KeyboardSource.ps1 | 独立预检设备、辅助功能、输入法和候选进程；读取低级钩子注入标志 | 120 秒 |
| Diag-RawInputDevice.ps1 | 将 Raw Input 事件关联到系统提供的设备句柄 | 120 秒 |
| Full-Keyboard-State.ps1 | 显示修饰键、锁定键状态；`-AllKeys` 可显示其他键位 | 30 秒 |
| Log-AllKeys-Async.ps1 | 轮询修饰键变化；`-RecordKeyCodes` 显式开启全部键位记录 | 30 秒 |
| RawInputKeyLogger.ps1 | 兼容旧入口，复用 Diag-RawInputDevice 的采集实现 | 30 秒 |

所有入口接受 `-DurationSeconds 1..600`。三个原生采集入口支持 `-CompileOnly`，仅编译、不开始采集；日志工具接受 `-OutDir`。含键码的记录可暴露输入内容，只应在专门的无敏感信息测试中显式开启。状态轮询可能漏掉短按。

```powershell
& '.\诊断电脑模板\Diag-KeyboardSource.ps1' -DurationSeconds 30 -OutDir "$env:TEMP\KbdDiag" # 采集来源标志，不保存普通键码。
& '.\诊断电脑模板\Diag-RawInputDevice.ps1' -DurationSeconds 30 -OutDir "$env:TEMP\KbdDiag" # 在独立进程中核对设备关联。
```

每个工具建议单独运行，避免多个 Raw Input 注册相互影响。出现异常输入时，用实体键盘和屏幕键盘分别输入约定的非敏感测试字符，记下时间后比对。普通运行不要求管理员；受限的设备或进程查询将分别写入错误及 `preflight-status.json`，其他预检仍继续。

判读边界：

- `INJECTED` 只表示系统标记了软件注入，屏幕键盘或自动化也可能产生；不能识别操作者或证明入侵。
- `NOT_FLAGGED_INJECTED` 只表示未设置该标志，不能证明输入一定来自实体硬件。
- `DEVICE_ASSOCIATED` 表示系统提供设备句柄；`NO_DEVICE_HANDLE` 表示未提供。两者均不能单独判断恶意行为。
- 空日志不能证明不存在异常，也不能证明设备采集已通过真实按键对照验证。

微软参考：[KBDLLHOOKSTRUCT](https://learn.microsoft.com/windows/win32/api/winuser/ns-winuser-kbdllhookstruct)、[Raw Input](https://learn.microsoft.com/en-us/windows/win32/inputdev/about-raw-input)。

本次验证细节及原稿备份保存在本机 `reports/template-tests-20260923/`，不随代码发布。
