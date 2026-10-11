"""CI-only validation. Does not install, execute built code, or create packages."""
from pathlib import Path
import hashlib, json, plistlib, struct, subprocess, sys

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

mode = sys.argv[1]
evidence = Path('compile-evidence')
if mode == 'source':
    manifest = json.loads(Path(sys.argv[2]).read_text())
    for item in manifest['files']:
        p = Path(item['path'])
        assert p.is_file() and sha(p) == item['sha256'], str(p)
    (evidence/'accepted-source-validation.json').write_text(json.dumps(manifest, indent=2))
elif mode == 'sdk':
    root = Path(sys.argv[2])
    settings = root/'SDKSettings.plist'
    value = plistlib.loads(settings.read_bytes())
    assert value['Version'] == '16.4', value.get('Version')
    result = {'selected_directory':'iPhoneOS16.5.sdk','internal_version':value['Version'],
              'settings_sha256':sha(settings)}
    # Header/stub presence is not proof of a runtime-readable log store.
    assert (root/'usr/include/os/log.h').is_file()
    (evidence/'sdk-validation.json').write_text(json.dumps(result, indent=2))
    (evidence/'sdk-file-sha256.json').write_text(json.dumps([
        {'path':str(p.relative_to(root)), 'sha256':sha(p)}
        for p in sorted(root.rglob('*')) if p.is_file()], indent=2))
elif mode == 'binaries':
    result=[]
    for name in ('Lantern.dylib','LanternModule','lanternctl'):
        candidates = [p for p in Path('.theos/obj').rglob(name)
                      if p.is_file() and p.read_bytes()[:4] == b'\xca\xfe\xba\xbe']
        assert len(candidates)==1, (name, candidates)
        p=candidates[0]; d=p.read_bytes(); slices=[]
        for i in range(struct.unpack_from('>I', d, 4)[0]):
            cpu, sub, offset, size, align = struct.unpack_from('>IIIII',d,8+20*i)
            assert cpu == 0x100000c
            slices.append(sub & 0xffffff)
        assert sorted(slices)==[0,2], (name,slices)
        result.append({'path':str(p),'size':len(d),'sha256':sha(p),'cpu_subtypes':slices})
        for flag in ('-L','-l'):
            data=subprocess.check_output(['xcrun','otool',flag,str(p)], text=True)
            (evidence/(name+flag.replace('-','-otool-')+'.txt')).write_text(data)
        nm=subprocess.check_output(['xcrun','nm','-u',str(p)], text=True)
        (evidence/(name+'-imports.txt')).write_text(nm)
    (evidence/'compile-binary-manifest.json').write_text(json.dumps(result,indent=2))
elif mode == 'finish':
    assert not list(Path('.').rglob('*.deb')), 'Unexpected package output'
    assert not Path('packages').exists(), 'Unexpected package directory'
    result={'result':'COMPILE_AND_LINK_ONLY','device_runtime':'NOT_TESTED','package':'NOT_PRODUCED',
            'evidence':[{'path':p.name,'sha256':sha(p)} for p in sorted(evidence.iterdir())
                        if p.is_file() and p.name!='complete.log']}
    (evidence/'validation.json').write_text(json.dumps(result,indent=2))
elif mode == 'final-evidence':
    assert evidence.is_dir(), 'No compile evidence directory; inspect CI step failure'
    (evidence/'completed-evidence-sha256.json').write_text(json.dumps([
        {'path':p.name,'size':p.stat().st_size,'sha256':sha(p)} for p in sorted(evidence.iterdir())
        if p.is_file() and p.name!='completed-evidence-sha256.json'],indent=2))
else:
    raise SystemExit('Unknown validation mode')
