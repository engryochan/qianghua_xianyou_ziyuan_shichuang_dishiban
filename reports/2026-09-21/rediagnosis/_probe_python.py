import sys, sysconfig, os, json, site
from importlib import metadata
exe_dir=os.path.dirname(sys.executable)
venv_root=os.path.dirname(exe_dir) if os.path.basename(exe_dir).lower()=="scripts" else exe_dir
is_venv=os.path.isfile(os.path.join(venv_root,"pyvenv.cfg"))
paths=[os.path.join(venv_root,"Lib","site-packages")]
include_system=not is_venv
if is_venv:
    with open(os.path.join(venv_root,"pyvenv.cfg"),encoding="utf-8") as f:
        include_system="include-system-site-packages = true" in f.read().lower()
if include_system:
    paths.extend([sysconfig.get_paths().get("purelib",""),sysconfig.get_paths().get("platlib","")])
    user=site.getusersitepackages()
    paths.extend(user if isinstance(user,list) else [user])
paths=list(dict.fromkeys(p for p in paths if p and os.path.isdir(p)))
rows=[]
for path in paths:
    for dist in metadata.distributions(path=[path]):
        rows.append({"Name":dist.metadata.get("Name","?"),"Version":dist.version,"Library":path})
print(json.dumps({"Executable":sys.executable,"Version":sys.version.split()[0],"Libraries":paths,"IsVirtualEnvironment":is_venv,"Packages":sorted(rows,key=lambda p:p["Name"].lower()),"Scope":"Static distribution metadata; .pth/editable paths and runtime import behavior not executed"},ensure_ascii=True))