#!/usr/bin/env python3
"""Generate a deterministic skills-only plugin from one canonical portable tree.

Requires Python 3.9+ and PyYAML. No network, installation or MF runtime calls.
The schema checker supports exactly the assertions used by the pinned manifest
schema and fails on unsupported assertions; this is not a general JSON Schema engine.
"""
import argparse, hashlib, io, json, re, tempfile, zipfile
from pathlib import Path, PurePosixPath
import yaml

ROOT=Path(__file__).resolve().parents[1]
CANON=ROOT
VERSION='1.1.1'
SCHEMA_ASSERTIONS={'type','properties','required','additionalProperties','const','minLength','maxLength','pattern','items'}
SCHEMA_ANNOTATIONS={'$schema','$id','title','description'}

def digest(data): return hashlib.sha256(data).hexdigest()
def encoded(obj): return (json.dumps(obj,indent=2,sort_keys=True,ensure_ascii=False)+'\n').encode()
def ensure(condition,message):
 if not condition: raise ValueError(message)

def validate_schema(value,schema,where='$'):
 ensure(not (set(schema)-SCHEMA_ASSERTIONS-SCHEMA_ANNOTATIONS),f'{where}: unsupported schema assertion')
 typ=schema.get('type')
 types={'object':dict,'array':list,'string':str}
 if typ: ensure(typ in types and isinstance(value,types[typ]),f'{where}: type {typ}')
 if 'const' in schema: ensure(value==schema['const'],f'{where}: const differs')
 if isinstance(value,str):
  ensure(len(value)>=schema.get('minLength',0),f'{where}: too short')
  ensure(len(value)<=schema.get('maxLength',float('inf')),f'{where}: too long')
  if 'pattern' in schema: ensure(re.search(schema['pattern'],value) is not None,f'{where}: pattern differs')
 if isinstance(value,dict):
  ensure(set(schema.get('required',[]))<=set(value),f'{where}: required field absent')
  props=schema.get('properties',{});additional=schema.get('additionalProperties',True)
  for k,v in value.items():
   if k in props: validate_schema(v,props[k],f'{where}.{k}')
   else:
    ensure(additional is not False,f'{where}: unexpected field {k}')
    if isinstance(additional,dict): validate_schema(v,additional,f'{where}.{k}')
 if isinstance(value,list) and 'items' in schema:
  for i,v in enumerate(value): validate_schema(v,schema['items'],f'{where}[{i}]')

def validate_plugin(plugin,schema):
 validate_schema(plugin,schema)
 ensure(re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*',plugin['name']) and len(plugin['name'])<=64,'plugin name must be lower kebab <=64')
 # Strict SemVer incl no leading zero in numeric prerelease identifiers.
 version=plugin.get('version','')
 ensure(re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?',version),'strict SemVer required')
 prerelease=version.split('+')[0].split('-',1)[1] if '-' in version.split('+')[0] else ''
 ensure(all(not x.isdigit() or x=='0' or not x.startswith('0') for x in prerelease.split('.')),'numeric prerelease leading zero')
 interface=plugin.get('extensions',{}).get('com.openai.interface',{})
 if 'shortDescription' in interface: ensure(isinstance(interface['shortDescription'],str) and len(interface['shortDescription'])<=30,'shortDescription <=30')

def validate_files(files,expected_skills):
 license_bytes=files['LICENSE']
 skills={PurePosixPath(k).parts[1] for k in files if re.fullmatch(r'skills/[^/]+/SKILL.md',k)}
 ensure(skills==set(expected_skills),'module inventory differs')
 for rel,b in files.items():
  path=PurePosixPath(rel)
  ensure(not path.is_absolute() and '..' not in path.parts,'unsafe member path')
  ensure(not re.search(rb'(?:/Users/|/home/|[A-Za-z]:\\Users\\)',b),'personal path in package '+rel)
  if rel.endswith('SKILL.md'):
   text=b.decode();m=re.match(r'\A---\n(.*?)\n---\n',text,re.S);ensure(m is not None,'missing frontmatter '+rel)
   data=yaml.safe_load(m.group(1));name=path.parent.name
   ensure(isinstance(data,dict) and data.get('name')==name and re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*',name) and len(name)<64,'skill name invalid '+rel)
   ensure(isinstance(data.get('description'),str) and data['description'].strip(),'description absent '+rel)
   ensure(data.get('license')=='MIT' and files[str(path.parent/'LICENSE')]==license_bytes,'MIT notice differs '+rel)
  if rel.endswith('.md'):
   for target in re.findall(r'\]\(([^)]+)\)',b.decode()):
    if re.match(r'https?://',target): continue
    resolved=[]
    for part in (path.parent/PurePosixPath(target.split('#')[0])).parts:
     if part=='..': ensure(bool(resolved),'link escapes '+rel);resolved.pop()
     elif part not in ['.','']: resolved.append(part)
    ensure('/'.join(resolved) in files,'broken link '+rel+': '+target)

def canonical_identity():
 source=json.loads((CANON/'SOURCE.json').read_text());actual={}
 for p in sorted(CANON.rglob('*')):
  ensure(not p.is_symlink(),'canonical symlink '+str(p.relative_to(CANON)))
  rel=str(p.relative_to(CANON))
  if p.is_file() and (rel in ['LICENSE','README.md','coverage.json'] or rel.startswith('skills/')): actual[rel]=digest(p.read_bytes())
 ensure(source['files_sha256']==actual,'canonical member hashes stale or inventory changed')
 for name in source['unchanged_existing_modules']:
  for k,h in source['predecessor_files_sha256'].items():
   if k.startswith('skills/'+name+'/'): ensure(actual.get(k)==h,'retained module drift '+k)
 ensure(source['generator']['sha256']==digest(Path(__file__).read_bytes()),'generator hash drift')
 validate_coverage(source)
 return source

def validate_coverage(source):
 coverage=json.loads((CANON/'coverage.json').read_text());groups={}
 ensure(coverage['bundle_version']==source['bundle_version'],'coverage version differs')
 for row in coverage['rows']:
  ensure(row['disposition'] in ['preserved','adapted','excluded'],'unknown coverage disposition')
  ensure(bool(row.get('reason')),'coverage reason absent')
  ensure(row['source'] in source['source_files'],'coverage source absent')
  ensure(row['source_sha256']==source['source_files'][row['source']]['sha256'],'coverage source hash differs')
  groups.setdefault(row['source'],[]).append(row['line'])
  if row['disposition']!='excluded':
   ensure(row.get('port') in source['files_sha256'],'coverage port missing')
   lines=(CANON/row['port']).read_text().splitlines();line=row.get('port_line')
   ensure(isinstance(line,int) and 1<=line<=len(lines) and bool(lines[line-1].strip()),'coverage port line invalid')
   if row['disposition']=='preserved':ensure(row['text']==lines[line-1],'preserved criterion differs')
 ensure(groups==source['persona_nonblank_lines'],'coverage line inventory differs')
 ensure(len(groups)==31,'native persona inventory differs')

def members():
 source=canonical_identity();plugin=json.loads((ROOT/'integrations/codex/plugin.json').read_text());schema=json.loads((ROOT/'integrations/codex/plugin.schema.json').read_text())
 validate_plugin(plugin,schema);ensure(plugin['version']==source['bundle_version'],'bundle/wrapper version mismatch')
 files={k:(CANON/k).read_bytes() for k in ['LICENSE','README.md','coverage.json']}
 for p in sorted((CANON/'skills').rglob('*')):
  ensure(not p.is_symlink(),'symlink prohibited')
  if p.is_file():
   ensure(p.suffix=='.md' or p.name=='LICENSE','unexpected canonical skill member')
   files[str(p.relative_to(CANON))]=p.read_bytes()
 files['plugin.json']=encoded(plugin)
 # No reports, evaluator cases, dependencies, copied source code or host schema.
 export_source={k:source[k] for k in ['bundle_version','source_repository','source_commit','source_version','source_files','additional_prior_provenance','fidelity_corrections','host_policy_additions']}
 export_source.update(canonical_source_commit=None,canonical_source_manifest_sha256=digest((CANON/'SOURCE.json').read_bytes()),generator={'version':VERSION,'sha256':digest(Path(__file__).read_bytes())},schema={'url':schema['$id'],'snapshot_sha256':digest((ROOT/'integrations/codex/plugin.schema.json').read_bytes())},files_sha256={k:digest(v) for k,v in sorted(files.items())},status='generated portable package; installation and behavior verified separately')
 files['SOURCE.json']=encoded(export_source)
 validate_files(files,source['module_sources'])
 return plugin['name'],files

def archive(name,files):
 stream=io.BytesIO()
 with zipfile.ZipFile(stream,'w',compression=zipfile.ZIP_STORED) as z:
  for rel,data in sorted(files.items()):
   info=zipfile.ZipInfo(name+'/'+rel,date_time=(1980,1,1,0,0,0));info.create_system=3;info.external_attr=0o100644<<16;info.compress_type=zipfile.ZIP_STORED
   z.writestr(info,data)
 return stream.getvalue()

def roundtrip(blob,name,files):
 with tempfile.TemporaryDirectory(prefix='mf-plugin-roundtrip-') as tmp:
  with zipfile.ZipFile(io.BytesIO(blob)) as z:
   ensure(z.testzip() is None,'ZIP CRC failed')
   ensure(z.namelist()==[name+'/'+k for k in sorted(files)],'archive inventory/order differs')
   for info in z.infolist(): ensure((info.external_attr>>16)&0o170000==0o100000,'nonregular member')
   z.extractall(tmp)
  actual={str(p.relative_to(Path(tmp)/name)):p.read_bytes() for p in (Path(tmp)/name).rglob('*') if p.is_file()}
  ensure(actual==files,'archive extraction byte mismatch')

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,default=ROOT/'dist');a=ap.parse_args()
 name,files=members();blob=archive(name,files);ensure(blob==archive(name,files),'rebuild differs');roundtrip(blob,name,files)
 a.output.mkdir(parents=True,exist_ok=True)
 zipname=f"{name}-{json.loads(files['plugin.json'])['version']}.zip";(a.output/zipname).write_bytes(blob)
 report={'status':'PASS','scope':'structural identity, pinned-schema assertion/profile checks, deterministic archive and extraction; not behavioral efficacy or host install','generator_version':VERSION,'archive':zipname,'archive_sha256':digest(blob),'archive_bytes':len(blob),'skills':len([k for k in files if k.endswith('/SKILL.md')]),'members_sha256':{name+'/'+k:digest(v) for k,v in sorted(files.items())},'rebuild_byte_identical':True,'roundtrip_byte_identical':True,'schema_url':'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json','schema_snapshot_sha256':digest((ROOT/'integrations/codex/plugin.schema.json').read_bytes())}
 (a.output/'build-validation.json').write_bytes(encoded(report));(a.output/'SHA256SUMS').write_text(digest(blob)+'  '+zipname+'\n')
 print(json.dumps({k:v for k,v in report.items() if k!='members_sha256'},indent=2))
if __name__=='__main__': main()
