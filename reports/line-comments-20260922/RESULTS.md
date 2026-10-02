# 逐行注释验收

已为 `診斷操作系統` 内全部 24 个维护脚本添加 4,318 行中文注释：18 个 PowerShell、3 个 Python、3 个 R。原有注释保留。

一般代码行使用紧邻上方的注释；多行字符串、here-string 与显式续行保持原文，在代码块前按相对行号逐行说明，避免把注释变成输出文本或破坏内嵌代码。历史生成报告、下载的厂商脚本及 Quarto 文档未作为维护脚本重写。

验证结果：
- 24 个文件的原有源码逐行保持顺序与内容，差异仅为插入注释（PowerShell 文件补齐 UTF-8 BOM 以兼容 Windows PowerShell 5.1）。
- 18 个 PowerShell 文件：PowerShell 7 与 Windows PowerShell 5.1 解析均通过；有效标记及 AST 节点类型序列与原文件一致。
- 3 个 Python 文件：AST 完全一致。
- 3 个 R 文件：解析表达式完全一致。R 启动仍有既有 locale 警告，不影响此次解析比较。
- Git 空白检查通过，按现有 Windows CRLF 行尾处理。

本次没有运行脚本中的安装、驱动更新、进程终止、注册表或系统设置操作，也没有提交或推送本轮注释修改。

验证文件：comment-only-validation.json、powershell-validation.json、powershell51-validation.json、r-validation.txt；源码快照在 before/；代码行与注释对应关系在 coverage.json。
