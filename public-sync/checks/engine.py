"""Run the public regression in a disposable, isolated snapshot."""
import json,os,re,subprocess,tempfile,uuid
from pathlib import Path
from audit import walk,no_links,digest

def validate_tree(root,godot,gpu=False):
    godot=no_links(godot)
    if not godot.is_file():raise ValueError('Godot executable missing')
    version=subprocess.run([str(godot),'--version'],capture_output=True,timeout=15)
    if version.returncode or not version.stdout.decode().startswith('4.7.1.'):
        raise ValueError('validation requires Godot 4.7.1')
    out=Path(tempfile.gettempdir())/('reader-core-check-'+uuid.uuid4().hex);out.mkdir()
    snapshot=out/'snapshot';snapshot.mkdir()
    hashes={}
    for p in walk(root):
        data=(root/p).read_bytes();hashes[p]=digest(data)
        f=snapshot/p;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes(data)
    env=os.environ.copy()
    for key in ('APPDATA','LOCALAPPDATA','USERPROFILE','HOME','TEMP','TMP'):
        d=out/'environment'/key;d.mkdir(parents=True);env[key]=str(d)
    env['SCRT_PUBLIC_TEST_ROOT']=str(out)
    results=[]
    def invoke(name,args):
        log=out/(name+'.log')
        with log.open('wb') as f:
            proc=subprocess.Popen([str(godot),'--path',str(snapshot/'SCRT'),*args],env=env,stdout=f,stderr=subprocess.STDOUT)
            try:code=proc.wait(timeout=120)
            except subprocess.TimeoutExpired:
                proc.kill();proc.wait();raise ValueError('Godot validation timeout: '+name)
        text=log.read_text(encoding='utf-8',errors='replace')
        errors=list(dict.fromkeys(re.findall(r'^(?:SCRIPT ERROR|ERROR:).*',text,re.M)))
        for i,line in enumerate(errors):errors[i]=re.sub(r'[A-Za-z]:[/\\][^ "\n]+','<local>',line)
        matches=re.findall(r'PUBLIC_CORE_RESULT: (\{.*\})',text)
        result=json.loads(matches[-1]) if matches else None
        success=code==0 and not errors and (name=='import' or result is not None and result['status']=='PASS')
        results.append({'test':name,'status':'PASS' if success else 'FAIL','checks':1 if name=='import' else result['checks'] if result else 0,'failures':errors+(result['failures'] if result else [])})
        if not success:raise ValueError('Godot '+name+' failed: '+json.dumps(results[-1],ensure_ascii=False))
    invoke('import',['--headless','--editor','--import'])
    args=['--script','res://tests/public_core_regression.gd']
    if not gpu:args=['--headless',*args]
    invoke('runtime',args);invoke('process_reload',args)
    for p,h in hashes.items():
        if digest((root/p).read_bytes())!=h:raise ValueError('candidate drift during engine validation: '+p)
    # Logs and synthetic accounts remain only in the disposable system-temp evidence directory.
    return {'status':'PASS','mode':'GPU' if gpu else 'headless','results':results,'snapshot_sha256':digest(json.dumps(hashes,sort_keys=True).encode())}
