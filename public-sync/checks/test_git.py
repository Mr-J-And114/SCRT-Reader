"""Synthetic Git history fixtures. No network, production repository or story data."""
from pathlib import Path
import json,os,subprocess,tempfile,unittest,sys
from unittest.mock import patch
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).parent))
import audit

class GitTests(unittest.TestCase):
    def setUp(self):
        self.root=Path(tempfile.mkdtemp(prefix='reader-git-fixture-'))
        self.env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
        self.env.update(GIT_CONFIG_NOSYSTEM='1',GIT_CONFIG_GLOBAL=os.devnull,GIT_AUTHOR_NAME='Synthetic Fixture',GIT_AUTHOR_EMAIL='fixture@example.invalid',GIT_COMMITTER_NAME='Synthetic Fixture',GIT_COMMITTER_EMAIL='fixture@example.invalid')
        template=self.root/'template';template.mkdir();self.repo=self.root/'repo';self.repo.mkdir()
        self.git('init','--initial-branch=main','--template='+str(template))
        # Both the path and credential-like bytes are synthetic rejected fixtures.
        self.bad='synthetic-old.txt';self.secret='# '+'sk-'+'x'*25+'\n'
        (self.repo/self.bad).write_text(self.secret)
        self.git('add','--',self.bad);self.git('commit','-m','Synthetic legacy')
        self.base=self.git('rev-parse','HEAD').decode().strip()
        self.git('remote','add','origin',audit.LEGACY_ORIGIN)
        self.rules={'reviewed_font_sha256':[],'patterns':['sk-'+'[a-z]{25}'],'cjk_lengths':[],'restricted_token_sha256':[],'forbidden_components':[],'forbidden_suffixes':[]}
        self.pin=patch.object(audit,'LEGACY_BASELINE',self.base);self.pin.start();self.addCleanup(self.pin.stop)
        (self.repo/self.bad).unlink();(self.repo/'core.txt').write_text('Synthetic public core\n')
        self.git('add','-A');self.expected={'core.txt'}
    def git(self,*args):return subprocess.run(['git','-C',str(self.repo),*args],env=self.env,check=True,capture_output=True).stdout
    def check(self):return audit.audit_git(self.repo,self.expected,self.rules)
    def test_accepted_legacy_and_complete_new_index(self):self.assertEqual(self.check(),[])
    def test_safe_future_commit(self):
        self.git('commit','-m','Synthetic public tree');self.assertEqual(self.check(),[])
    def test_legacy_blob_reused_in_allowed_path_is_rejected(self):
        (self.repo/'core.txt').write_text(self.secret);self.git('add','-A');self.git('commit','-m','Synthetic rejected blob reuse')
        (self.repo/'core.txt').write_text('Synthetic public core\n');self.git('add','-A');self.git('commit','-m','Synthetic removal')
        self.assertTrue(any('restricted content' in e and 'commit ' in e for e in self.check()))
    def test_unapproved_old_path_reintroduced_is_rejected(self):
        self.git('commit','-m','Synthetic public tree');(self.repo/self.bad).write_text('Synthetic old path')
        self.git('add','-A');self.git('commit','-m','Synthetic rejected path');(self.repo/self.bad).unlink();self.git('add','-A')
        self.assertTrue(any('unapproved Git path' in e and 'commit ' in e for e in self.check()))
    def test_sensitive_index_is_rejected(self):
        (self.repo/'core.txt').write_text(self.secret);self.git('add','-A')
        self.assertTrue(any('index:' in e and 'restricted content' in e for e in self.check()))
    def test_safe_unstaged_edit_can_coexist_with_safe_index(self):
        (self.repo/'core.txt').write_text('Synthetic manual edit\n')
        self.assertEqual(self.check(),[])
    def test_wrong_origin_cannot_use_legacy_exception(self):
        self.git('remote','set-url','origin','https://example.invalid/another.git')
        self.assertTrue(any('approved repository origin' in e for e in self.check()))
    def test_no_approved_baseline_means_no_history_exception(self):
        with patch.object(audit,'LEGACY_BASELINE','0'*40):
            self.assertTrue(any('unapproved Git path' in e for e in self.check()))
    def test_empty_index_is_not_accepted(self):
        self.git('read-tree','--empty')
        self.assertTrue(any('incomplete Public Core tree' in e for e in self.check()))
    def test_unborn_repository_empty_index_is_allowed(self):
        self.repo=self.root/'unborn';self.repo.mkdir()
        self.git('init','--initial-branch=main');self.git('read-tree','--empty')
        self.assertEqual(self.check(),[])
    def font_index(self):
        (self.repo/'core.txt').unlink();data=b'Synthetic reviewed font fixture'
        (self.repo/'core.ttf').write_bytes(data);self.expected={'core.ttf'}
        self.rules['reviewed_font_sha256']=[audit.digest(data)];self.git('add','-A')
    def test_reviewed_font_index_is_accepted(self):
        self.font_index();self.assertEqual(self.check(),[])
    def test_unreviewed_font_index_is_rejected(self):
        self.font_index();(self.repo/'core.ttf').write_bytes(b'Synthetic unreviewed font');self.git('add','-A')
        self.assertTrue(any('unreviewed font' in e for e in self.check()))
    def test_old_public_tree_does_not_require_future_new_files(self):
        self.git('commit','-m','Synthetic public tree')
        self.expected.add('next.txt');(self.repo/'next.txt').write_text('Synthetic newly approved file')
        self.assertEqual(self.check(),[])  # A safe previous index is normal before staging a new file.
        self.git('add','-A');self.assertEqual(self.check(),[])
    def test_unrelated_commit_is_not_accepted(self):
        tree=self.git('write-tree').decode().strip()
        commit=self.git('commit-tree',tree,'-m','Synthetic unrelated').decode().strip()
        self.git('update-ref','refs/heads/unrelated',commit)
        self.assertTrue(any('does not descend' in e for e in self.check()))

if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(GitTests))
    print('SYNC_FIXTURE_RESULT: '+json.dumps({'tests':result.testsRun,'failures':len(result.failures)+len(result.errors),'skips':len(result.skipped),'status':'PASS' if result.wasSuccessful() else 'FAIL'}))
    sys.exit(0 if result.wasSuccessful() else 1)
