"""Exercise the generated updater against disposable Git and failed evidence."""
import argparse
import json
import os
from pathlib import Path
import subprocess

parser=argparse.ArgumentParser()
parser.add_argument('--updater',required=True)
parser.add_argument('--root',type=Path,required=True)
args=parser.parse_args()
root=args.root
root.mkdir(mode=0o700)
environment={key:value for key,value in os.environ.items() if not key.startswith(('GIT_','T3CODE_','TRACKER_'))}
environment.update(GIT_CONFIG_GLOBAL='/dev/null',GIT_CONFIG_NOSYSTEM='1',
    HOME=str(root/'home'),XDG_RUNTIME_DIR=str(root/'runtime'),
    DBUS_SESSION_BUS_ADDRESS='unix:path='+str(root/'no-bus'))
for name in ['home','runtime']:(root/name).mkdir(mode=0o700)
def run(argv):
    return subprocess.run(argv,env=environment,capture_output=True,text=True,check=True,timeout=30).stdout.strip()
def git(path,*argv):
    return run(['git','-C',str(path),'-c','core.hooksPath=/dev/null',
                '-c','user.name=fixture','-c','user.email=fixture@example.invalid',*argv])
remote=root/'remote.git';seed=root/'seed';primary=root/'primary'
run(['git','init','--bare','--initial-branch=main',str(remote)])
run(['git','clone',str(remote),str(seed)])
(seed/'README.md').write_text('original source\n')
git(seed,'add','README.md');git(seed,'commit','-m','baseline');git(seed,'push','origin','main')
run(['git','clone',str(remote),str(primary)])
report=root/'workspace/projects/owner/scratch';report.mkdir(parents=True)
candidate=report.parent/'candidate'
git(primary,'worktree','add','-b','candidate',str(candidate))
before=git(primary,'rev-parse','HEAD')
(seed/'README.md').write_text('UNVERIFIED upstream protocol change\n')
git(seed,'add','README.md');git(seed,'commit','-m','unverified upstream');git(seed,'push','origin','main')
run(['git','clone',str(remote),str(root/'nixos')])
calls=root/'calls';stub=root/'stub.sh'
stub.write_text('npx() { printf "npx\\n" >> "$T3_PROBE_CALLS"; return 73; }\n'
                'systemctl() { printf "systemctl\\n" >> "$T3_PROBE_CALLS"; return 73; }\n')
environment.update(BASH_ENV=str(stub),T3_PROBE_CALLS=str(calls))
for payload,expected in [({'schemaVersion':1,'passed':False},'release-native-not-retired'),
                         ({'schemaVersion':2,'passed':True},'release-receipt-schema')]:
    failed=root/'failed.json';failed.write_text(json.dumps(payload));failed.chmod(0o600)
    result=subprocess.run([args.updater,'promote',str(candidate),str(failed),str(failed),str(report)],
                          env=environment,capture_output=True,text=True,timeout=30)
    assert result.returncode==1,(result.returncode,result.stdout,result.stderr)
    response=json.loads(result.stdout)
    assert response.get('code')==expected,response
    assert git(primary,'rev-parse','HEAD')==before,'updater pulled unverified upstream'
    assert not git(primary,'status','--porcelain'),'updater changed serving source'
    assert not list(report.iterdir()),'updater reserved effects before checking evidence'
    assert not calls.exists(),'updater built or restarted before evidence gate'
    print('rendered updater refused '+expected+' before source/build/restart effects')
