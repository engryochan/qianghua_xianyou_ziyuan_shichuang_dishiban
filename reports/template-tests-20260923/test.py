import subprocess, json, base64, time # 启动有超时限制的独立测试进程。
from pathlib import Path # 使用完整Unicode路径。
root=Path.cwd(); out=root/'reports/template-tests-20260923'; results=[] # 限定测试输出位置。
for engine in ('powershell.exe','pwsh.exe'): # 分别验证Windows PowerShell与PowerShell 7。
    for script in sorted((root/'诊断电脑模板').glob('*.ps1')): # 覆盖五个公开入口。
        modes=['compile','run'] if script.name in ('Diag-KeyboardSource.ps1','Diag-RawInputDevice.ps1','RawInputKeyLogger.ps1') else ['run'] # 原生采集器单独验证编译和运行。
        for mode in modes: # 将失败与对应测试模式关联。
            dest=out/(engine+'-'+script.stem+'-'+mode); dest.mkdir(exist_ok=True) # 每次运行使用独立输出目录。
            args=' -CompileOnly' if mode=='compile' else ' -DurationSeconds 1' # 实际采集限定一秒，不开启普通键码记录。
            if script.name!='Full-Keyboard-State.ps1': args+=" -OutDir '"+str(dest)+"'" # 将输出重定向到测试报告内。
            command="$ErrorActionPreference='Stop'; & '"+str(script)+"'"+args # 将错误升级为进程失败。
            encoded=base64.b64encode(command.encode('utf-16-le')).decode() # 避免中文路径及引号传参丢失。
            start=time.monotonic() # 测量进程总耗时。
            try: # 捕捉超时而不终止其他用户进程。
                p=subprocess.run([engine,'-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-EncodedCommand',encoded],capture_output=True,timeout=25) # 每项最长25秒，仅等待自身子进程。
                text=(p.stdout+p.stderr).decode('utf-8',errors='replace'); code=p.returncode # 保存退出状态和诊断输出。
            except subprocess.TimeoutExpired as exc: text=str(exc); code='TIMEOUT' # 明确记录无法自动退出。
            (dest/'console.txt').write_text(text,encoding='utf-8') # 保存完整控制台输出。
            row=dict(engine=engine,script=script.name,mode=mode,exit=code,seconds=round(time.monotonic()-start,2)); results.append(row); print(json.dumps(row),flush=True) # 输出简洁的逐项结果。
(out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8') # 保存可复核测试清单。
