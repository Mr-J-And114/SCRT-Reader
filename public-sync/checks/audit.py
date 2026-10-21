"""Offline, fail-closed public content and resource checks (standard library only)."""
from pathlib import Path
import hashlib,json,os,re,stat,subprocess,tomllib

def digest(data): return hashlib.sha256(data).hexdigest()

def safe_path(root,relative):
    if not relative or '\\' in relative or ':' in relative or relative.startswith('/'):
        raise ValueError('invalid relative path: '+relative)
    parts=relative.split('/')
    if any(p in ('','.','..') or p.rstrip(' .')!=p for p in parts):
        raise ValueError('unsafe relative path: '+relative)
    p=root.joinpath(*parts); no_links(p)
    return p

def no_links(path):
    path=Path(os.path.abspath(path))
    for p in [path,*path.parents]:
        try:s=p.lstat()
        except FileNotFoundError:continue
        if stat.S_ISLNK(s.st_mode) or getattr(s,'st_file_attributes',0)&0x400:
            raise ValueError('link/reparse point rejected: '+p.name)
    return path

def walk(root):
    no_links(root)
    for base,dirs,files in os.walk(root,followlinks=False):
        for name in dirs+files: no_links(Path(base)/name)
        rel=Path(base).relative_to(root)
        # Local runtime/editor artifacts never enter the publication set.
        dirs[:]=[d for d in dirs if (rel/d).as_posix() not in ('.git','.sync-local','SCRT/.godot')]
        for name in files: yield (rel/name).as_posix()

def text_findings(path,data,rules):
    errors=[]
    if Path(path).suffix=='.ttf':
        if digest(data) not in rules['reviewed_font_sha256']: errors.append(path+': unreviewed font binary')
        return errors
    try: text=data.decode('utf-8-sig')
    except UnicodeError:return [path+': unreviewed binary content']
    for i,line in enumerate(text.splitlines(),1):
        for pattern in rules['patterns']:
            if re.search(pattern,line,re.I): errors.append(f'{path}:{i}: restricted content pattern')
        # Hashed word/Chinese n-gram rules avoid publishing restricted names in the scanner itself.
        tokens=re.findall(r'[A-Za-z][A-Za-z0-9_-]*',line.casefold())
        tokens += [part for token in list(tokens) for part in re.split('[_-]',token)]
        for word in re.findall(r'[\u3400-\u9fff]+',line):
            tokens += [word[j:j+n] for n in rules['cjk_lengths'] for j in range(len(word)-n+1)]
        if any(digest(t.encode()) in rules['restricted_token_sha256'] for t in tokens):
            errors.append(f'{path}:{i}: restricted token')
    return errors

def audit(root,config=None,git=True):
    root=no_links(root)
    config=config or root/'public-sync'
    spec=tomllib.loads((config/'allowlist.toml').read_text(encoding='utf-8'))
    rules=tomllib.loads((config/'exclusions.toml').read_text(encoding='utf-8'))
    expected=set(spec['maintained'])|{e['path'] for e in spec['files']}
    errors=[]; actual=set(walk(root))
    for p in sorted(actual-expected): errors.append(p+': unknown publication file')
    for p in sorted(expected-actual): errors.append(p+': missing publication file')
    for p in sorted(actual):
        parts=p.casefold().split('/')
        if any(part in rules['forbidden_components'] for part in parts) or Path(p).suffix.casefold() in rules['forbidden_suffixes']:
            errors.append(p+': forbidden path')
        errors.extend(text_findings(p,safe_path(root,p).read_bytes(),rules))
        if not p.endswith('.ttf'):errors.extend(text_findings(p,p.encode(),rules))
    for name in ('plan.json','state.json','transaction.json'):
        local=safe_path(root,'.sync-local/'+name)
        if local.is_file():errors.extend(text_findings('.sync-local/'+name,local.read_bytes(),rules))
    # Literal required resources, including preloads, direct loads and scene ext_resources.
    for p in sorted(actual):
        if Path(p).suffix not in ('.gd','.tscn','.godot','.json'):continue
        text=(root/p).read_text(encoding='utf-8-sig')
        for i,line in enumerate(text.splitlines(),1):
            if line.lstrip().startswith('#'):continue
            for ref in re.findall(r'res://([^"\s\)]+)',line):
                if not ref or ref.endswith('/') or ref=='SCRT/':continue
                target='SCRT/'+ref
                if target in actual:continue
                origin=p.removeprefix('public-sync/overrides/')
                key=origin+':'+digest(line.strip().encode())
                if key not in spec.get('optional_reference',[]):errors.append(f'{p}:{i}: missing resource {ref}')
    manifest=root/'SCRT/data/main/manifest.json'
    if manifest.is_file():
        m=json.loads(manifest.read_text(encoding='utf-8'))
        for key in ['daily_dialogues','initial_flags','comm_dialogues','comm_characters','vdisc_tasks']:
            if m.get(key)!= {}:errors.append('neutral manifest contract: '+key)
        if m.get('camera_system',{}).get('cameras')!={}:errors.append('neutral camera contract')
    if git and (root/'.git').exists():
        errors.extend(audit_git(root,expected,rules))
    return sorted(set(errors))

# This is the one author-approved existing repository baseline, not a user-selectable waiver.
LEGACY_BASELINE = 'b2ab2af987339d73fa39849608bfbe5e5c5b3828'
LEGACY_ORIGIN = 'https://github.com/Mr-J-And114/SCRT-Reader.git'

def audit_git(root,expected,rules):
    errors=[]
    if not (root/'.git').is_dir():return ['external Git directory is forbidden']
    env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
    env.update(GIT_CONFIG_NOSYSTEM='1',GIT_CONFIG_GLOBAL=os.devnull,GIT_NO_REPLACE_OBJECTS='1')
    def command(*args,check=True):
        cp=subprocess.run(['git','--no-optional-locks','-C',str(root),*args],capture_output=True,env=env)
        if check and cp.returncode:raise ValueError('Git audit command failed: '+args[0])
        return cp
    def out(*args):return command(*args).stdout
    if out('rev-parse','--git-dir').strip()!=b'.git' or out('rev-parse','--git-common-dir').strip()!=b'.git':
        return ['shared Git metadata is forbidden']
    for name in ('objects/info/alternates','info/grafts','shallow'):
        if (root/'.git'/name).exists():errors.append('unsupported Git history metadata: '+name)
    if out('for-each-ref','--format=%(refname)','refs/replace').strip():errors.append('Git replacement refs are forbidden')
    if errors:return errors
    def inspect(label,rows,index=False):
        paths=set()
        for row in rows.split(b'\0'):
            if not row:continue
            meta,raw=row.split(b'\t',1);p=raw.decode('utf-8');parts=meta.decode().split()
            mode=parts[0];obj=parts[1] if index else parts[2]
            paths.add(p)
            if mode not in ('100644','100755') or (index and parts[2]!='0'):
                errors.append(label+': unexpected Git entry: '+p);continue
            if p not in expected:errors.append(label+': unapproved Git path: '+p)
            if any(x in rules['forbidden_components'] for x in p.casefold().split('/')) or Path(p).suffix.casefold() in rules['forbidden_suffixes']:
                errors.append(label+': forbidden Git path: '+p)
            data=out('cat-file','blob',obj)
            errors.extend(text_findings(label+':'+p,data,rules))
            if not p.endswith('.ttf'):errors.extend(text_findings(label+':'+p,p.encode(),rules))
            if p=='SCRT/data/main/manifest.json':
                m=json.loads(data)
                for key in ('daily_dialogues','initial_flags','comm_dialogues','comm_characters','vdisc_tasks'):
                    if m.get(key)!={}:errors.append(label+': non-neutral manifest '+key)
                if m.get('camera_system',{}).get('cameras')!={}:errors.append(label+': non-neutral camera manifest')
        if index and not paths and expected:errors.append(label+': incomplete Public Core tree')
    index=out('ls-files','--stage','-z')
    has_head=command('rev-parse','--verify','HEAD',check=False).returncode==0
    if index or ((root/'.git/index').exists() and has_head):inspect('index',index,index=True)
    all_commits=out('rev-list','--all').decode().splitlines()
    baseline=command('cat-file','-e',LEGACY_BASELINE+'^{commit}',check=False).returncode==0
    if baseline:
        origin=command('remote','get-url','origin',check=False)
        if origin.returncode or origin.stdout.decode().strip()!=LEGACY_ORIGIN:
            return errors+['legacy baseline requires the approved repository origin']
        commits=out('rev-list','--all','--not',LEGACY_BASELINE).decode().splitlines()
        # Full trees are inspected, so reusing a forbidden legacy blob is still rejected.
        for commit in commits:
            if command('merge-base','--is-ancestor',LEGACY_BASELINE,commit,check=False).returncode:
                errors.append('new history does not descend from approved legacy baseline: '+commit)
    else:commits=all_commits
    for commit in commits:inspect('commit '+commit,out('ls-tree','-rz','--full-tree',commit))
    return errors
