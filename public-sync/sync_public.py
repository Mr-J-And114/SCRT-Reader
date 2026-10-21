#!/usr/bin/env python3
"""Deterministic allowlist export. Never writes to the source repository."""
import argparse,hashlib,json,os,sys,tempfile,tomllib
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).parent/'checks'))
from audit import audit,digest,no_links,safe_path,walk
from engine import validate_tree

def encode(obj):return (json.dumps(obj,ensure_ascii=False,indent=2,sort_keys=True)+'\n').encode()
def put(path,data):
    no_links(path)
    if path.exists() and path.read_bytes()==data:return
    path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_name(path.name+'.new')
    no_links(temp)
    if temp.exists():raise ValueError('unexpected transaction file: '+temp.name)
    created=False
    try:
        with temp.open('xb') as f:
            created=True;f.write(data);f.flush();os.fsync(f.fileno())
        os.replace(temp,path)
    except BaseException:
        if created:
            no_links(temp)
            temp.unlink(missing_ok=True)
        raise

def snapshot(config,source,target):
    spec=tomllib.loads((config/'allowlist.toml').read_text(encoding='utf-8'))
    rules=tomllib.loads((config/'exclusions.toml').read_text(encoding='utf-8'))
    payload={}; inputs={}; cfg={}
    for p in spec['maintained']:
        data=safe_path(config.parent,p).read_bytes();payload[p]=data;cfg[p]=digest(data)
    seen=set()
    for entry in spec['files']:
        p=entry['path']; safe_path(target,p)
        if p.casefold() in seen:raise ValueError('duplicate/case collision: '+p)
        seen.add(p.casefold())
        if 'source' in entry:
            if source is None:raise ValueError('--source is required for source synchronization')
            if any(part.casefold() in set(rules['forbidden_components'])|{'.git','.godot','accounts','credentials'} for part in entry['source'].split('/')) or Path(entry['source']).suffix.casefold() in rules['forbidden_suffixes']:
                raise ValueError('source path is forbidden before reading: '+entry['source'])
            src=safe_path(source,entry['source']);data=src.read_bytes();sha=digest(data);inputs[entry['source']]=sha
            if entry.get('source_sha256') and sha!=entry['source_sha256']:
                raise ValueError(f"adaptation conflict: {p}; expected SHA {entry['source_sha256']}; current SHA {sha}; locations {entry.get('locations','file')}")
        else:data=b''
        if 'override' in entry:
            data=safe_path(config,entry['override']).read_bytes();cfg[entry['override']]=digest(data)
        payload[p]=data
    # Detect any source changes while gathering the snapshot.
    for p,h in inputs.items():
        if digest(safe_path(source,p).read_bytes())!=h:raise ValueError('source drift while freezing: '+p)
    return spec,payload,inputs,cfg

def recover(target):
    journal=safe_path(target,'.sync-local/transaction.json')
    if not journal.exists():return
    tx=json.loads(journal.read_bytes())
    for entry in reversed(tx['entries']):
        path=safe_path(target,entry['path']);current=digest(path.read_bytes()) if path.exists() else None
        if current not in (entry['old'],entry['new']):raise ValueError('recovery conflict: '+entry['path'])
        if entry['old'] is None:
            if path.exists():path.unlink()
        else:
            backup=safe_path(target/'.sync-local',entry['backup'])
            data=backup.read_bytes()
            if digest(data)!=entry['old']:raise ValueError('damaged recovery backup')
            put(path,data)
    if tx.get('old_state') is not None:put(target/'.sync-local/state.json',encode(tx['old_state']))
    elif (target/'.sync-local/state.json').exists():(target/'.sync-local/state.json').unlink()
    journal.unlink()

def adopt_verified_core(config,source,target,reference):
    """One-time ownership reconstruction after exact reference/source/output comparisons."""
    reference=no_links(reference)
    if reference==target or reference in target.parents or target in reference.parents:
        raise ValueError('reference and target must be disjoint')
    state_path=safe_path(target,'.sync-local/state.json')
    if state_path.exists():raise ValueError('migration refuses an existing target state')
    for root in (reference,target):
        errors=audit(root)
        if errors:raise ValueError('migration audit: '+'\n'.join(errors))
    ref_state_path=safe_path(reference,'.sync-local/state.json')
    if not ref_state_path.is_file():raise ValueError('verified reference ownership record required')
    reference_bytes=ref_state_path.read_bytes();ref_state=json.loads(reference_bytes)
    spec,payload,inputs,cfg=snapshot(config,source,target)
    owned={e['path']:digest(payload[e['path']]) for e in spec['files']}
    if ref_state.get('owned')!=owned or ref_state.get('source_hashes')!=inputs:
        raise ValueError('reference ownership or source fingerprints do not match migration')
    for p,h in owned.items():
        if digest(safe_path(reference,p).read_bytes())!=h:
            raise ValueError('reference generated content differs: '+p)
    for p,data in payload.items():
        if safe_path(target,p).read_bytes()!=data:raise ValueError('target migration bytes differ: '+p)
    state={'owned':owned,'source_hashes':inputs,'source_snapshot':digest(encode(inputs)),
           'migration':{'method':'verified-reference-exact-bytes','reference_owned_sha256':digest(encode(owned))}}
    local=target/'.sync-local';local.mkdir(parents=True,exist_ok=True)
    lock=safe_path(target,'.sync-local/apply.lock')
    with lock.open('xb') as f:f.write(str(os.getpid()).encode())
    try:
        if state_path.exists():raise ValueError('migration target state appeared concurrently')
        _,again,again_inputs,again_cfg=snapshot(config,source,target)
        if again!=payload or again_inputs!=inputs or again_cfg!=cfg:raise ValueError('migration source/config drift')
        if ref_state_path.read_bytes()!=reference_bytes:raise ValueError('migration reference state drift')
        for p,h in owned.items():
            if digest(safe_path(reference,p).read_bytes())!=h:raise ValueError('migration reference drift: '+p)
        for p,data in payload.items():
            if safe_path(target,p).read_bytes()!=data:raise ValueError('migration target drift: '+p)
        errors=audit(target)
        if errors:raise ValueError('migration audit: '+'\n'.join(errors))
        put(state_path,encode(state))
    finally:lock.unlink(missing_ok=True)
    print('PASS: migrated ownership from verified reference; generated files unchanged')

def run(args):
    config=no_links(Path(__file__).parent)
    target=no_links(args.target or config.parent)
    source=no_links(args.source) if args.source else None
    if source and (source==target or source in target.parents or target in source.parents):raise ValueError('source and target roots must be disjoint')
    for name in ('state.json','plan.json','transaction.json','apply.lock'):
        safe_path(target,'.sync-local/'+name)
    if getattr(args,'adopt_verified_core',None):
        adopt_verified_core(config,source,target,args.adopt_verified_core);return
    # Recovery must be explicitly requested; never run it against a live transaction.
    if args.recover:recover(target);print('Recovery completed. Run dry-run again.');return
    if (target/'.sync-local/transaction.json').exists():raise ValueError('unfinished transaction; close other sync process, inspect backups, then use --recover')
    if args.verify:
        errors=audit(target,config)
        spec=tomllib.loads((config/'allowlist.toml').read_text(encoding='utf-8'))
        for e in spec['files']:
            f=safe_path(target,e['path'])
            if 'override' in e and f.is_file() and f.read_bytes()!=safe_path(config,e['override']).read_bytes():errors.append('override not synchronized: '+e['path'])
        state_path=target/'.sync-local/state.json'
        if state_path.exists():
            state=json.loads(state_path.read_bytes())
            for p,h in state['owned'].items():
                f=safe_path(target,p)
                if not f.is_file() or digest(f.read_bytes())!=h:errors.append('generated file differs from recorded export: '+p)
        if errors:raise ValueError('\n'.join(errors))
        print('PASS: publication allowlist, content, resources, Git and recorded hashes');return
    spec,payload,inputs,cfg=snapshot(config,source,target)
    old_path=target/'.sync-local/state.json'
    old=json.loads(old_path.read_bytes()) if old_path.exists() else {'owned':{}}
    generated={e['path'] for e in spec['files']}
    known=set(spec['maintained'])|generated|set(old['owned'])
    unknown=set(walk(target))-known if target.exists() else set()
    if unknown:raise ValueError('unknown target files: '+', '.join(sorted(unknown)))
    change=[]
    for p in sorted(generated|set(old['owned'])):
        path=safe_path(target,p);current=digest(path.read_bytes()) if path.is_file() else None
        desired=digest(payload[p]) if p in generated else None
        previous=old['owned'].get(p)
        if current is not None and previous is None:
            raise ValueError('unowned target file cannot be adopted or overwritten: '+p)
        if previous is not None and current!=previous:raise ValueError('manual edit or deletion conflict: '+p)
        if current!=desired:change.append({'path':p,'old':current,'new':desired,'kind':'add' if current is None else 'remove' if desired is None else 'update'})
    for p in spec['maintained']:
        existing=safe_path(target,p)
        if existing.exists() and existing.read_bytes()!=payload[p]:raise ValueError('maintained file differs in target: '+p)
        if not existing.exists():change.append({'path':p,'old':None,'new':digest(payload[p]),'kind':'add'})
    plan={'source_snapshot':digest(encode(inputs)),'inputs':inputs,'configuration':cfg,'target_baseline':old,'changes':change}
    plan_path=target/'.sync-local/plan.json'
    if args.dry_run:
        # Validate the complete candidate without touching generated target files.
        validate(target,payload,config)
        put(plan_path,encode(plan))
        print(json.dumps({'snapshot':plan['source_snapshot'],'changed':len(change),'files':[{'path':x['path'],'action':x['kind']} for x in change]},ensure_ascii=False,indent=2));return
    if not plan_path.exists() or plan_path.read_bytes()!=encode(plan):raise ValueError('missing/stale dry-run plan; run --dry-run first')
    if not change:
        errors=audit(target,config)
        if errors:raise ValueError('\n'.join(errors))
        print('PASS: 0 changed files, 0 writes');return
    if not args.godot:raise ValueError('--godot (or SCRT_PUBLIC_GODOT) is required for changed synchronization')
    engine_result=validate(target,payload,config,args.godot)
    for p,h in inputs.items():
        if digest(safe_path(source,p).read_bytes())!=h:raise ValueError('source drift before application: '+p)
    _,payload_after,inputs_after,cfg_after=snapshot(config,source,target)
    if payload_after!=payload or inputs_after!=inputs or cfg_after!=cfg:raise ValueError('configuration or override drift before application')
    if old_path.exists() and json.loads(old_path.read_bytes())!=old:raise ValueError('target state drift before application')
    for x in change:
        f=safe_path(target,x['path']);now=digest(f.read_bytes()) if f.exists() else None
        if now!=x['old']:raise ValueError('target file drift before application: '+x['path'])
    local=target/'.sync-local';local.mkdir(parents=True,exist_ok=True)
    lock=local/'apply.lock'
    # Exclusive create protects the application window. A stale lock requires manual review.
    with lock.open('xb') as f:f.write(str(os.getpid()).encode())
    try:
        # Another synchronization may have finished while this process validated.
        now_state=json.loads(old_path.read_bytes()) if old_path.exists() else {'owned':{}}
        if now_state!=old:raise ValueError('target state drift after lock acquisition')
        if set(walk(target))-known:raise ValueError('unknown target files after lock acquisition')
        _,locked_payload,locked_inputs,locked_cfg=snapshot(config,source,target)
        if locked_payload!=payload or locked_inputs!=inputs or locked_cfg!=cfg:raise ValueError('source/configuration drift after lock acquisition')
        for x in change:
            f=safe_path(target,x['path']);now=digest(f.read_bytes()) if f.exists() else None
            if now!=x['old']:raise ValueError('target file drift after lock acquisition: '+x['path'])
        entries=[]
        for i,x in enumerate(change):
            x=dict(x);x['backup']=f'backup/{i}.bin'
            if x['old'] is not None:put(local/x['backup'],safe_path(target,x['path']).read_bytes())
            entries.append(x)
        put(local/'transaction.json',encode({'entries':entries,'old_state':old if old_path.exists() else None}))
        try:
            for i,x in enumerate(entries):
                p=safe_path(target,x['path'])
                if x['new'] is None:p.unlink()
                else:put(p,payload[x['path']])
                if os.environ.get('SCRT_SYNC_FAULT_AFTER')==str(i+1):raise RuntimeError('injected application failure')
            errors=audit(target,config)
            if errors:raise ValueError('\n'.join(errors))
            state={'owned':{p:digest(payload[p]) for p in sorted(generated)},'source_hashes':inputs,'source_snapshot':plan['source_snapshot'],'godot':engine_result}
            put(old_path,encode(state));(local/'transaction.json').unlink()
        except BaseException:
            recover(target);raise
    finally:lock.unlink(missing_ok=True)
    print(json.dumps({'snapshot':plan['source_snapshot'],'changed':len(change),'hashes':'PASS','sensitive_scan':'PASS','adaptation_conflicts':0,'godot':engine_result['status'],'commit_ready':True},ensure_ascii=False))

def validate(target,payload,config,godot=None):
    target.parent.mkdir(parents=True,exist_ok=True)
    directory=Path(tempfile.mkdtemp(prefix='.scrt-candidate-',dir=target.parent));owned=[]
    try:
        for p,data in payload.items():f=safe_path(directory,p);f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes(data);owned.append(f)
        errors=audit(directory,config,git=False)
        if errors:raise ValueError('\n'.join(errors))
        return validate_tree(directory,godot) if godot else None
    finally:
        for f in owned:f.unlink()
        for d in sorted({p for f in owned for p in f.parents if p==directory or directory in p.parents},key=lambda x:len(x.parts),reverse=True):
            d.rmdir()  # Refuse to remove anything unknown.

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    modes=parser.add_mutually_exclusive_group(required=True)
    for mode in ('dry-run','sync','verify','recover'):modes.add_argument('--'+mode,action='store_true')
    modes.add_argument('--adopt-verified-core',type=Path,metavar='REFERENCE')
    parser.add_argument('--source',type=Path);parser.add_argument('--target',type=Path)
    parser.add_argument('--godot',type=Path,default=os.environ.get('SCRT_PUBLIC_GODOT'))
    try:run(parser.parse_args())
    except (ValueError,OSError,RuntimeError) as e:print('STOP: '+str(e),file=sys.stderr);sys.exit(1)
