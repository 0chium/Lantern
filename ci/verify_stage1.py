"""Offline input and post-build package gates. No extraction, install or upload."""
from pathlib import Path, PurePosixPath
import hashlib, io, json, os, plistlib, struct, subprocess, sys, tarfile
ROOT=Path(__file__).resolve().parents[1]
BASE='82e4d8e8c4b28af822ade2ab508b821350ddddb0'
BUILD='lantern-b51-diag-s1-20261010-r1'
VERSION='0.1.2-1+diag.s1.20261010.r1'
BRANCH='diagnostics/'+BUILD
def sha(data):return hashlib.sha256(data).hexdigest()
def normalized(data,mode):return data.replace(b'\r\n',b'\n') if mode=='text-lf' else data
def inputs():
    lock=json.loads((ROOT/'ci/source-lock.json').read_text(encoding='utf-8'))
    assert lock['baseline']==BASE and lock['build']==BUILD
    for name,item in lock['files'].items():
        p=ROOT/name;assert p.is_file() and not p.is_symlink(),name
        assert sha(normalized(p.read_bytes(),item['mode']))==item['sha256'],name
    if os.getenv('GITHUB_ACTIONS')=='true':
        assert os.getenv('GITHUB_REPOSITORY')=='0chium/Lantern'
        assert os.getenv('GITHUB_EVENT_NAME')=='workflow_dispatch'
        assert os.getenv('GITHUB_REF')=='refs/heads/'+BRANCH
        subprocess.run(['git','merge-base','--is-ancestor',BASE,'HEAD'],cwd=ROOT,check=True)
    return {'build':BUILD,'baseline':BASE,'locked_files':len(lock['files']),'source_lock_sha256':sha((ROOT/'ci/source-lock.json').read_bytes())}
def ar(data):
    assert data[:8]==b'!<arch>\n';p=8;out={}
    while p<len(data):
        h=data[p:p+60];assert len(h)==60 and h[58:]==b'`\n'
        name=h[:16].decode('ascii').strip().rstrip('/');size=int(h[48:58]);p+=60
        assert name not in out and p+size<=len(data);out[name]=data[p:p+size];p+=size+(size&1)
    assert p==len(data)
    return out
def path(name):
    p=PurePosixPath(name);assert not p.is_absolute() and '..' not in p.parts
    return str(p).removeprefix('./')
def tar(data):
    out={}
    with tarfile.open(fileobj=io.BytesIO(data),mode='r:*') as t:
        for m in t:
            n=path(m.name)
            assert n not in out and not m.issym() and not m.islnk() and (m.isdir() or m.isfile()),n
            assert m.size<=4*1024*1024,n
            b=t.extractfile(m).read() if m.isfile() else None
            if b is not None:assert len(b)==m.size
            out[n]={'data':b,'mode':m.mode,'uid':m.uid,'gid':m.gid}
    return out
def macho(data):
    if data[:4]==b'\xca\xfe\xba\xbe':
        n=struct.unpack_from('>I',data,4)[0];assert n==2
        out=[]
        for i in range(n):
            cpu,sub,off,size,align=struct.unpack_from('>IIIII',data,8+i*20)
            assert off+size<=len(data);out+=macho(data[off:off+size])
        return out
    assert data[:4]==b'\xcf\xfa\xed\xfe'
    _,cpu,sub,ft,nc,sc,flags,res=struct.unpack_from('<8I',data)
    assert cpu==0x100000c and (sub&0xffffff) in (0,2) and 32+sc<=len(data)
    r={'architecture':'arm64e' if sub&0xffffff==2 else 'arm64','filetype':ft,'dylibs':[],'rpaths':[]};p=32
    for _ in range(nc):
        cmd,size=struct.unpack_from('<II',data,p);assert size>=8 and p+size<=32+sc
        if cmd in (0xc,0x80000018,0x8000001f,0x20,0x80000023,0x8000001c):
            off=struct.unpack_from('<I',data,p+8)[0];assert 8<=off<size
            name=data[p+off:p+size].split(b'\0')[0].decode('utf-8')
            r['rpaths' if cmd==0x8000001c else 'dylibs'].append(name)
        if cmd==0x1b:r['uuid']=data[p+8:p+24].hex()
        if cmd==0x32:
            platform,minos,sdk,ntools=struct.unpack_from('<4I',data,p+8)
            r.update(platform=platform,minos=minos,sdk=sdk)
        if cmd==0x1d:
            off,count=struct.unpack_from('<II',data,p+8);assert count>0 and off+count<=len(data)
            r['signature_structure_present']=True
        p+=size
    assert p==32+sc
    return [r]
def inspect(package,diagnostic=True):
    data=package.read_bytes();assert len(data)<4*1024*1024
    a=ar(data);assert a['debian-binary']==b'2.0\n' and len(a)==3
    control=tar(next(v for n,v in a.items() if n.startswith('control.tar')))
    regular={n:v['data'] for n,v in control.items() if v['data'] is not None}
    assert set(regular)=={'control'},'unexpected maintainer script/control member'
    fields=dict(line.split(':',1) for line in regular['control'].decode('utf-8').splitlines() if ':' in line)
    fields={k:v.strip() for k,v in fields.items()}
    assert fields['Package']=='com.ochium.lantern' and fields['Architecture']=='iphoneos-arm64'
    if diagnostic:
        assert fields['Version']==VERSION
        assert fields['Depends']=='mobilesubstrate, com.opa334.ccsupport'
    payload=tar(next(v for n,v in a.items() if n.startswith('data.tar')))
    files={n:v for n,v in payload.items() if v['data'] is not None}
    bundle='var/jb/Library/ControlCenter/Bundles/LanternModule.bundle/'
    tweak='var/jb/Library/MobileSubstrate/DynamicLibraries/'
    binaries={tweak+'Lantern.dylib',bundle+'LanternModule','var/jb/usr/bin/lanternctl'}
    resources={bundle+p.name for p in (ROOT/'Resources').iterdir() if p.suffix=='.png'}
    expected=binaries|resources|{tweak+'Lantern.plist',bundle+'Info.plist'}
    assert set(files)==expected,'unexpected or missing regular-file payload'
    # Theos compiles the OpenStep source filter to a binary plist.
    filter=plistlib.loads(files[tweak+'Lantern.plist']['data'])
    assert filter=={'Filter':{'Executables':['cameracaptured']}}
    info=plistlib.loads(files[bundle+'Info.plist']['data'])
    source_info=plistlib.loads((ROOT/'Resources/Info.plist').read_bytes());assert info==source_info
    assert info['CFBundleExecutable']=='LanternModule'
    for name in resources:assert files[name]['data']==(ROOT/'Resources'/PurePosixPath(name).name).read_bytes()
    expected_linkage=json.loads((ROOT/'ci/baseline-linkage.json').read_text(encoding='utf-8'))
    images={}
    for name in binaries:
        b=files[name]['data'];slices=macho(b)
        assert {s['architecture'] for s in slices}=={'arm64','arm64e'}
        if diagnostic:assert BUILD.encode() in b,'missing embedded diagnostic identity'
        for s in slices:
            assert s['platform']==2 and s['minos']==0x000f0000 and s['signature_structure_present']
            expected=expected_linkage[name][s['architecture']]
            assert sorted(s['dylibs'])==sorted(expected['dylibs']),name
            assert sorted(s['rpaths'])==sorted(expected['rpaths']),name
            assert s['filetype']==expected['filetype']
        images[name]=slices
    return {'package':package.name,'sha256':sha(data),'bytes':len(data),'fields':fields,'regular_payload_files':len(files),'payload':{n:{k:v for k,v in item.items() if k!='data'}|{'sha256':sha(item['data'])} for n,item in files.items()},'images':images,'physical_color':'unverified','signature_note':'Structure/bounds only; not device trust or runtime compatibility'}
def main():
    mode=sys.argv[1]
    if mode=='inputs':result=inputs()
    elif mode=='package':
        inputs();ps=list((ROOT/'packages').glob('*.deb'));assert len(ps)==1
        result=inspect(ps[0])
        result['github']={k:os.getenv(k) for k in ['GITHUB_REPOSITORY','GITHUB_SHA','GITHUB_RUN_ID','GITHUB_RUN_ATTEMPT','GITHUB_REF']}
    else:raise ValueError('mode')
    out=ROOT/'ci-output';out.mkdir(exist_ok=True)
    (out/(mode+'-inspection.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
    if mode=='package':(out/'SHA256SUMS').write_text(result['sha256']+'  '+result['package']+'\n',encoding='ascii')
    print(json.dumps(result if mode=='inputs' else {k:result[k] for k in ['package','sha256','fields','regular_payload_files']},indent=2))
if __name__=='__main__':main()
