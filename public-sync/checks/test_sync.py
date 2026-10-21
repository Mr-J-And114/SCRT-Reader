"""Synthetic integration fixtures for exporter safety. No private project is read."""
import contextlib,hashlib,importlib.util,io,json,os,tempfile,unittest,subprocess,shutil
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import sys
sys.dont_write_bytecode=True
TOOL=Path(__file__).parents[1]
sys.path.insert(0,str(TOOL/'checks'))
spec=importlib.util.spec_from_file_location('exporter',TOOL/'sync_public.py')
exporter=importlib.util.module_from_spec(spec);spec.loader.exec_module(exporter)
from engine import validate_tree as actual_engine_validation

class SyncTests(unittest.TestCase):
    def setUp(self):
        self.root=Path(tempfile.mkdtemp(prefix='reader-core-fixture-'))
        self.source=self.root/'source';self.target=self.root/'public';self.config=self.target/'public-sync'
        self.config.mkdir(parents=True)
        self.source.mkdir()
        self.maintained=['public-sync/sync_public.py','public-sync/checks/audit.py','public-sync/checks/engine.py','public-sync/allowlist.toml','public-sync/exclusions.toml','public-sync/overrides/SCRT/scripts/adapted.gd']
        for p in self.maintained[:3]+[self.maintained[4]]:
            f=self.target/p;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes((TOOL.parent/p).read_bytes())
        self.write(self.source/'SCRT/scripts/plain.gd','extends RefCounted\nconst VALUE = 1\n')
        self.write(self.source/'SCRT/scripts/second.gd','extends RefCounted\nconst VALUE = 1\n')
        self.write(self.source/'SCRT/scripts/adapted.gd','extends RefCounted\nconst VALUE = 1\n')
        self.write(self.target/self.maintained[-1],'extends RefCounted\nconst VALUE = 2\n')
        sha=hashlib.sha256((self.source/'SCRT/scripts/adapted.gd').read_bytes()).hexdigest()
        text='version = 1\nmaintained = '+json.dumps(self.maintained)+'\noptional_reference = []\n'
        for name in ('plain','second','adapted'):
            p='SCRT/scripts/'+name+'.gd'
            text+='\n[[files]]\npath = '+json.dumps(p)+'\nsource = '+json.dumps(p)+'\n'
            if name=='adapted':text+='source_sha256 = '+json.dumps(sha)+'\noverride = '+json.dumps('overrides/'+p)+'\nlocations = "L2-L2"\n'
        self.write(self.config/'allowlist.toml',text)
        self.location=patch.object(exporter,'__file__',str(self.config/'sync_public.py'));self.location.start();self.addCleanup(self.location.stop)
        self.engine=patch.object(exporter,'validate_tree',return_value={'status':'PASS','fixture_engine':True});self.mock_engine=self.engine.start();self.addCleanup(self.engine.stop)
    def write(self,p,text):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding='utf-8')
    def run_mode(self,mode):
        a=SimpleNamespace(source=self.source,target=self.target,godot=Path('godot'),dry_run=mode=='dry_run',sync=mode=='sync',verify=mode=='verify',recover=False)
        with contextlib.redirect_stdout(io.StringIO()):exporter.run(a)
    def initialize(self):self.run_mode('dry_run');self.run_mode('sync')
    def generated(self):return {p:(self.target/p).read_bytes() for p in ['SCRT/scripts/plain.gd','SCRT/scripts/second.gd','SCRT/scripts/adapted.gd','.sync-local/state.json']}
    def test_initial_and_second_sync_zero_writes(self):
        self.initialize();self.run_mode('verify');self.run_mode('dry_run')
        before={str(p):(p.read_bytes(),p.stat().st_mtime_ns) for p in self.target.rglob('*') if p.is_file()}
        self.run_mode('sync');self.run_mode('sync')
        after={str(p):(p.read_bytes(),p.stat().st_mtime_ns) for p in self.target.rglob('*') if p.is_file()}
        self.assertEqual(before,after)
    def test_single_generic_update_only_one_file(self):
        self.initialize();a=self.target/'SCRT/scripts/second.gd';before=(a.read_bytes(),a.stat().st_mtime_ns)
        self.write(self.source/'SCRT/scripts/plain.gd','extends RefCounted\nconst VALUE = 3\n')
        self.run_mode('dry_run');plan=json.loads((self.target/'.sync-local/plan.json').read_bytes());self.assertEqual(len(plan['changes']),1)
        self.run_mode('sync');self.assertEqual(before,(a.read_bytes(),a.stat().st_mtime_ns))
    def test_adaptation_source_conflict_stops(self):
        self.initialize();before=self.generated();self.write(self.source/'SCRT/scripts/adapted.gd','extends RefCounted\nconst VALUE = 9\n')
        with self.assertRaisesRegex(ValueError,'adaptation conflict.*current SHA.*L2-L2'):self.run_mode('dry_run')
        self.assertEqual(before,self.generated())
    def test_unknown_target_is_preserved_and_blocks(self):
        self.initialize();unknown=self.target/'unknown.txt';self.write(unknown,'Synthetic unknown file')
        with self.assertRaisesRegex(ValueError,'unknown target'):self.run_mode('dry_run')
        self.assertEqual(unknown.read_text(),'Synthetic unknown file')
    def test_unknown_source_is_never_copied(self):
        self.initialize();self.write(self.source/'new_unclassified.gd','Synthetic new source')
        self.run_mode('dry_run');self.run_mode('sync');self.assertFalse((self.target/'new_unclassified.gd').exists())
    def test_failure_rolls_back_all_generated_bytes(self):
        self.initialize();before=self.generated()
        for name in ('plain','second'):self.write(self.source/('SCRT/scripts/'+name+'.gd'),'extends RefCounted\nconst VALUE = 4\n')
        self.run_mode('dry_run')
        with patch.dict(os.environ,{'SCRT_SYNC_FAULT_AFTER':'1'}):
            with self.assertRaisesRegex(RuntimeError,'injected'):self.run_mode('sync')
        self.assertEqual(before,self.generated());self.assertFalse((self.target/'.sync-local/transaction.json').exists())
    def test_manual_generated_edit_is_not_overwritten(self):
        self.initialize();self.write(self.target/'SCRT/scripts/plain.gd','extends RefCounted\n# Manual change\n')
        with self.assertRaisesRegex(ValueError,'manual edit'):self.run_mode('dry_run')
    def test_stale_plan_stops(self):
        self.initialize();self.run_mode('dry_run');self.write(self.source/'SCRT/scripts/plain.gd','extends RefCounted\nconst VALUE = 7\n')
        with self.assertRaisesRegex(ValueError,'stale dry-run'):self.run_mode('sync')
    def test_engine_failure_does_not_apply(self):
        self.initialize();before=self.generated();self.write(self.source/'SCRT/scripts/plain.gd','extends RefCounted\nconst VALUE = 8\n');self.run_mode('dry_run')
        self.mock_engine.side_effect=ValueError('synthetic engine rejection')
        with self.assertRaisesRegex(ValueError,'engine rejection'):self.run_mode('sync')
        self.assertEqual(before,self.generated())
    def test_source_race_does_not_apply(self):
        self.initialize();before=self.generated();self.write(self.source/'SCRT/scripts/plain.gd','extends RefCounted\nconst VALUE = 8\n');self.run_mode('dry_run')
        def drift(*a,**k):
            self.write(self.source/'SCRT/scripts/plain.gd','extends RefCounted\nconst VALUE = 10\n');return {'status':'PASS'}
        self.mock_engine.side_effect=drift
        with self.assertRaisesRegex(ValueError,'source drift'):self.run_mode('sync')
        self.assertEqual(before,self.generated())
    def test_restricted_content_is_rejected(self):
        self.initialize();self.write(self.source/'SCRT/scripts/plain.gd','extends RefCounted\n# '+'sk-'+'a'*25+'\n')
        with self.assertRaisesRegex(ValueError,'restricted content'):self.run_mode('dry_run')
    def test_private_git_path_rejected_before_read(self):
        p=self.config/'allowlist.toml';self.write(p,p.read_text().replace('source = "SCRT/scripts/plain.gd"','source = ".git/config"'))
        with self.assertRaisesRegex(ValueError,'source path is forbidden before reading'):self.run_mode('dry_run')
    def test_real_link_is_rejected(self):
        self.initialize();destination=self.root/'linked';destination.mkdir()
        self.make_link(self.target/'link',destination)
        with self.assertRaisesRegex(ValueError,'link/reparse'):self.run_mode('dry_run')
    def make_link(self,link,destination):
        try:link.symlink_to(destination,target_is_directory=True)
        except OSError:
            if os.name!='nt':raise
            env=os.environ.copy();env['READER_TEST_LINK']=str(link);env['READER_TEST_DEST']=str(destination)
            subprocess.run(['pwsh','-NoProfile','-NonInteractive','-Command',"$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path $env:READER_TEST_LINK -Value $env:READER_TEST_DEST | Out-Null"],env=env,check=True,capture_output=True)
    def test_parent_traversal_is_rejected(self):
        p=self.config/'allowlist.toml';self.write(p,p.read_text().replace('source = "SCRT/scripts/plain.gd"','source = "../outside.gd"'))
        with self.assertRaisesRegex(ValueError,'unsafe relative path'):self.run_mode('dry_run')
    def test_linked_local_state_rejected_before_read(self):
        destination=self.root/'metadata';destination.mkdir();self.write(destination/'state.json','{}')
        self.make_link(self.target/'.sync-local',destination)
        with self.assertRaisesRegex(ValueError,'link/reparse'):self.run_mode('dry_run')
        self.assertEqual((destination/'state.json').read_text(),'{}')
    def test_target_race_after_lock_is_rejected(self):
        self.initialize();before=self.generated();self.write(self.source/'SCRT/scripts/plain.gd','extends RefCounted\nconst VALUE = 8\n');self.run_mode('dry_run')
        original=Path.open
        def open_with_race(path,*args,**kwargs):
            f=original(path,*args,**kwargs)
            if path.name=='apply.lock' and args and args[0]=='xb':
                with original(self.target/'unknown.txt','w') as new:new.write('Synthetic concurrent user file')
            return f
        with patch.object(Path,'open',open_with_race):
            with self.assertRaisesRegex(ValueError,'unknown target files after lock'):self.run_mode('sync')
        self.assertEqual(before,self.generated());self.assertTrue((self.target/'unknown.txt').is_file())
    def test_atomic_replace_failure_leaves_no_partial_file(self):
        self.initialize();before=self.generated();self.write(self.source/'SCRT/scripts/plain.gd','extends RefCounted\nconst VALUE = 8\n');self.run_mode('dry_run')
        original=os.replace
        def reject_once(a,b):
            if Path(b)==self.target/'SCRT/scripts/plain.gd':raise OSError('synthetic replace failure')
            return original(a,b)
        with patch.object(exporter.os,'replace',reject_once):
            with self.assertRaisesRegex(OSError,'replace failure'):self.run_mode('sync')
        self.assertEqual(before,self.generated());self.assertFalse((self.target/'SCRT/scripts/plain.gd.new').exists())
    @unittest.skipUnless(os.environ.get('SCRT_PUBLIC_GODOT'),'real engine executable not supplied')
    def test_first_sync_real_engine_on_synthetic_project(self):
        project='config_version=5\n[application]\nconfig/name="Reader Sync Fixture"\nconfig/features=PackedStringArray("4.7", "GL Compatibility")\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        script='extends SceneTree\nfunc _initialize() -> void:\n\tvar expected: String = OS.get_environment("SCRT_PUBLIC_TEST_ROOT").replace("\\\\", "/")\n\tvar ok: bool = ProjectSettings.globalize_path("user://").replace("\\\\", "/").begins_with(expected)\n\tprint("PUBLIC_CORE_RESULT: " + JSON.stringify({"checks": 1, "failures": [] if ok else ["isolation"], "status": "PASS" if ok else "FAIL"}))\n\tquit(0 if ok else 1)\n'
        p=self.config/'allowlist.toml';text=p.read_text()
        for path,content in [('SCRT/project.godot',project),('SCRT/tests/public_core_regression.gd',script)]:
            self.write(self.source/path,content);text+='\n[[files]]\npath = '+json.dumps(path)+'\nsource = '+json.dumps(path)+'\n'
        self.write(p,text);self.mock_engine.side_effect=lambda root,unused:actual_engine_validation(root,Path(os.environ['SCRT_PUBLIC_GODOT']))
        self.initialize();self.run_mode('verify')
        state=json.loads((self.target/'.sync-local/state.json').read_bytes());self.assertEqual(state['godot']['status'],'PASS')
    def migration_target(self):
        self.initialize()
        target=self.root/'migration'
        shutil.copytree(self.target,target,ignore=shutil.ignore_patterns('.sync-local'))
        return target
    def test_verified_migration_and_zero_writes(self):
        target=self.migration_target()
        exporter.adopt_verified_core(target/'public-sync',self.source,target,self.target)
        with patch.object(exporter,'__file__',str(target/'public-sync/sync_public.py')):
            args=SimpleNamespace(source=self.source,target=target,godot=Path('godot'),dry_run=True,sync=False,verify=False,recover=False)
            exporter.run(args)
            before={p.relative_to(target).as_posix():(p.read_bytes(),p.stat().st_mtime_ns) for p in target.rglob('*') if p.is_file()}
            args.dry_run=False;args.sync=True;exporter.run(args);exporter.run(args)
            self.assertEqual(before,{p.relative_to(target).as_posix():(p.read_bytes(),p.stat().st_mtime_ns) for p in target.rglob('*') if p.is_file()})
    def test_migration_rejects_changed_reference(self):
        target=self.migration_target();self.write(self.target/'SCRT/scripts/plain.gd','extends RefCounted\nconst VALUE=77\n')
        with self.assertRaisesRegex(ValueError,'reference generated content differs'):
            exporter.adopt_verified_core(target/'public-sync',self.source,target,self.target)
        self.assertFalse((target/'.sync-local/state.json').exists())
    def test_migration_rejects_changed_target(self):
        target=self.migration_target();self.write(target/'SCRT/scripts/plain.gd','extends RefCounted\nconst VALUE=77\n')
        with self.assertRaisesRegex(ValueError,'target migration bytes differ'):
            exporter.adopt_verified_core(target/'public-sync',self.source,target,self.target)
        self.assertFalse((target/'.sync-local/state.json').exists())
    def test_migration_rejects_existing_state(self):
        target=self.migration_target();self.write(target/'.sync-local/state.json','{}')
        with self.assertRaisesRegex(ValueError,'existing target state'):
            exporter.adopt_verified_core(target/'public-sync',self.source,target,self.target)

    def test_git_increment_preserves_manual_maintained_file(self):
        self.initialize()
        template=self.root/'git-template';template.mkdir()
        env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
        env.update(GIT_CONFIG_NOSYSTEM='1',GIT_CONFIG_GLOBAL=os.devnull)
        def git(*args):
            return subprocess.run(['git','-C',str(self.target),'-c','user.name=Synthetic Fixture','-c','user.email=fixture@example.invalid',*args],env=env,capture_output=True,check=True).stdout
        git('init','--initial-branch=main','--template='+str(template))
        generated=list(json.loads((self.target/'.sync-local/state.json').read_bytes())['owned'])
        git('add','--',*self.maintained,*generated);git('commit','-m','Synthetic Core baseline')
        maintained=self.target/'public-sync/checks/engine.py'
        maintained.write_bytes(maintained.read_bytes()+b'\n# Synthetic maintained edit\n')
        before=(maintained.read_bytes(),maintained.stat().st_mtime_ns)
        self.write(self.source/'SCRT/scripts/plain.gd','extends RefCounted\nconst VALUE = 11\n')
        self.run_mode('dry_run');self.run_mode('sync');self.run_mode('verify')
        self.assertEqual(before,(maintained.read_bytes(),maintained.stat().st_mtime_ns))
        self.assertEqual((self.target/'SCRT/scripts/plain.gd').read_bytes(),(self.source/'SCRT/scripts/plain.gd').read_bytes())
        changes=git('diff','--name-only').decode().splitlines()
        self.assertEqual(set(changes),{'SCRT/scripts/plain.gd','public-sync/checks/engine.py'})

    def test_unknown_target_same_bytes_cannot_be_adopted(self):
        self.write(self.target/'SCRT/scripts/plain.gd',(self.source/'SCRT/scripts/plain.gd').read_text())
        with self.assertRaisesRegex(ValueError,'unowned target'):self.run_mode('dry_run')

if __name__=='__main__':
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(SyncTests)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    print('SYNC_FIXTURE_RESULT: '+json.dumps({'tests':result.testsRun,'failures':len(result.failures)+len(result.errors),'skips':len(result.skipped),'status':'PASS' if result.wasSuccessful() else 'FAIL'}))
    sys.exit(0 if result.wasSuccessful() else 1)
