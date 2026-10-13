"""Structural package invariants and rejection controls, discovered by unittest."""
import copy, importlib.util, io, json, unittest, zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('build_engineering_plugin',ROOT/'scripts/build_engineering_plugin.py')
build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)

class PackageTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.plugin=json.loads((ROOT/'integrations/codex/plugin.json').read_text())
  cls.schema=json.loads((ROOT/'integrations/codex/plugin.schema.json').read_text())
 def test_canonical_and_export_identity(self):
  source=build.canonical_identity();name,files=build.members()
  self.assertEqual(len(source['module_sources']),14)
  for key,data in files.items():
   if key.startswith('skills/'): self.assertEqual(data,(build.CANON/key).read_bytes())
  self.assertEqual(files['LICENSE'],(build.CANON/'LICENSE').read_bytes())
 def test_repeatable_archive_and_roundtrip(self):
  name,files=build.members();a=build.archive(name,files);self.assertEqual(a,build.archive(name,files));build.roundtrip(a,name,files)
 def test_only_one_contained_regular_plugin_tree(self):
  name,files=build.members()
  with zipfile.ZipFile(io.BytesIO(build.archive(name,files))) as z:
   self.assertTrue(all(p.startswith(name+'/') and '..' not in Path(p).parts for p in z.namelist()))
   self.assertTrue(all(i.date_time==(1980,1,1,0,0,0) for i in z.infolist()))
  self.assertFalse(any(k.startswith(('tests/','results/','scripts/','integrations/')) for k in files))
 def test_forbidden_top_level_fields_rejected(self):
  for key in ['skills','interface','mcpServers']:
   data=copy.deepcopy(self.plugin);data[key]={}
   with self.assertRaises(ValueError): build.validate_plugin(data,self.schema)
 def test_invalid_semver_rejected(self):
  for value in ['0.2','01.2.1','0.2.1-01','latest']:
   data=copy.deepcopy(self.plugin);data['version']=value
   with self.assertRaises(ValueError): build.validate_plugin(data,self.schema)
 def test_invalid_names_rejected(self):
  for value in ['Upper-Name','a--b','a'*65]:
   data=copy.deepcopy(self.plugin);data['name']=value
   with self.assertRaises(ValueError): build.validate_plugin(data,self.schema)
 def test_unknown_schema_assertion_fails_closed(self):
  schema=copy.deepcopy(self.schema);schema['oneOf']=[]
  with self.assertRaises(ValueError): build.validate_schema(self.plugin,schema)
 def test_interface_length_rejected(self):
  data=copy.deepcopy(self.plugin);data['extensions']={'com.openai.interface':{'shortDescription':'x'*31}}
  with self.assertRaises(ValueError): build.validate_plugin(data,self.schema)
 def test_broken_or_escaping_reference_rejected(self):
  name,files=build.members()
  for target in ['missing.md','../../outside.md']:
   bad=dict(files);bad['README.md']=f'[bad]({target})'.encode()
   with self.assertRaises(ValueError): build.validate_files(bad,build.canonical_identity()['module_sources'])
 def test_personal_paths_rejected(self):
  name,files=build.members();bad=dict(files);bad['README.md']=b'Private: /Users/example/config'
  with self.assertRaises(ValueError): build.validate_files(bad,build.canonical_identity()['module_sources'])
 def test_missing_notice_rejected(self):
  name,files=build.members();bad=dict(files);bad['skills/feature-definition/LICENSE']=b'license: MIT'
  with self.assertRaises(ValueError): build.validate_files(bad,build.canonical_identity()['module_sources'])
 def test_canonical_symlink_rejected(self):
  import tempfile, shutil
  original=build.CANON
  with tempfile.TemporaryDirectory(prefix='mf-symlink-control-') as tmp:
   candidate=Path(tmp)/'canonical';shutil.copytree(original,candidate)
   (candidate/'linked-secret.md').symlink_to(candidate/'LICENSE')
   try:
    build.CANON=candidate
    with self.assertRaisesRegex(ValueError,'symlink'): build.canonical_identity()
   finally: build.CANON=original
 def assert_bad_coverage_rejected(self,mutate,pattern):
  import tempfile, shutil
  original=build.CANON;source=build.canonical_identity()
  with tempfile.TemporaryDirectory(prefix='mf-coverage-control-') as tmp:
   candidate=Path(tmp)/'canonical';shutil.copytree(original,candidate)
   path=candidate/'coverage.json';coverage=json.loads(path.read_text());mutate(coverage)
   path.write_text(json.dumps(coverage))
   try:
    build.CANON=candidate
    with self.assertRaisesRegex(ValueError,pattern):build.validate_coverage(source)
   finally:build.CANON=original
 def test_coverage_missing_line_rejected(self):
  self.assert_bad_coverage_rejected(lambda c:c['rows'].pop(),'line inventory')
 def test_coverage_duplicate_line_rejected(self):
  self.assert_bad_coverage_rejected(lambda c:c['rows'].append(copy.deepcopy(c['rows'][0])),'line inventory')
 def test_coverage_wrong_source_hash_rejected(self):
  self.assert_bad_coverage_rejected(lambda c:c['rows'][0].update(source_sha256='0'*64),'source hash')
 def test_coverage_bad_port_line_rejected(self):
  self.assert_bad_coverage_rejected(lambda c:next(r for r in c['rows'] if r['disposition']=='preserved').update(port_line=0),'port line')
 def test_coverage_preserved_text_drift_rejected(self):
  self.assert_bad_coverage_rejected(lambda c:next(r for r in c['rows'] if r['disposition']=='preserved').update(text='changed criterion'),'preserved criterion')
 def test_canonical_member_drift_rejected(self):
  import tempfile,shutil
  original=build.CANON
  with tempfile.TemporaryDirectory(prefix='mf-hash-control-') as tmp:
   candidate=Path(tmp)/'canonical';shutil.copytree(original,candidate)
   (candidate/'README.md').write_text('unreviewed change')
   try:
    build.CANON=candidate
    with self.assertRaisesRegex(ValueError,'member hashes'):build.canonical_identity()
   finally:build.CANON=original
if __name__=='__main__': unittest.main()
