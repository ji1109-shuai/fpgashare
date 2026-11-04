"""Gate the (4) whole-machine NG buzzer release; never implies a board test."""
import argparse
import json
import re
import shutil
from collections import Counter
from datetime import datetime
from pathlib import Path
from verify_visual import digest, read, save, source_list

ROOT=Path(__file__).resolve().parents[2]
EVIDENCE=ROOT/'sim/batch_buzzer_20261103_validation'
RELEASE=ROOT/'release_archive/batch_buzzer_20261103'
TOPS=['tb_batch_buzzer','tb_motor_resume','tb_industrial_counter',
      'tb_industrial_menu','tb_industrial_tracker','tb_frame_rate',
      'tb_fps_display','tb_ae_boot_keys']
ROMS=['industrial_font16.hex','logo_idx.hex','logo_pal.hex']

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--build-record',required=True,type=Path)
    ap.add_argument('--release',action='store_true')
    ap.add_argument('--check-default',action='store_true')
    args=ap.parse_args();r=json.loads(read(args.build_record))
    issues=[];pending=[];passes=[]
    def check(ok,message):
        if not ok:issues.append(message)
    out={'created':datetime.now().astimezone().isoformat(),'project':str(ROOT),
         'boardProgrammed':False,'issues':issues,'pending':pending,'passes':passes,
         'alarm':{'source':'S_batch_overrun only','pin':'C12','idleLevel':1,
                  'toneHz':2000,'onMs':200,'periodMs':1000,
                  'recoveryClearsSound':True,'soundAcknowledgesFault':False},
         'limitations':['No board test; physical sound and loudness unverified.',
                        'Existing SDC exceptions and incomplete STA coverage remain.',
                        'Full CSI/video regressions were not rerun for this isolated alarm observer.']}
    baseline=json.loads(read(EVIDENCE/'before_manifest.json'))
    changed=[i['path'] for i in baseline if digest(ROOT/i['path'])!=i['sha256']]
    check(set(changed)=={'user_source/constraints_source/pin.adc',
                         'user_source/hdl_source/design_top_wrapper.v'},'Unexpected production edits')
    out['productionChanges']=changed;out['baselineInputCount']=len(baseline)
    s=read(ROOT/'user_source/hdl_source/design_top_wrapper.v')
    x=s.replace('    output wire       O_buzzer,\n','')
    x=re.sub(r'\n  // Use the same latched NG.*?\n  \);\n','',x,count=1,flags=re.S)
    x=re.sub(r'// Board C12 drives.*?\nendmodule\n\n','',x,count=1,flags=re.S)
    check(x==read(EVIDENCE/'before/design_top_wrapper.v'),'Existing top/control logic changed')
    check('.alarm(S_batch_overrun),.buzzer_n(O_buzzer)' in s,'Wrong physical alarm connection')
    pin=read(ROOT/'user_source/constraints_source/pin.adc')
    check(len(re.findall(r'LOCATION\s*=\s*C12\s*;',pin))==1 and
          re.search(r'\{ O_buzzer \} \{ LOCATION = C12;.*PULLTYPE = PULLUP;',pin),
          'Buzzer pin or idle pull incorrect')
    removed=re.sub(r'# On-board buzzer:.*?\nset_pin_assignment \{ O_buzzer \}.*?\n\n','',pin,flags=re.S)
    check(removed==read(EVIDENCE/'before/pin.adc'),'Existing pin assignments changed')
    guard=json.loads(read(EVIDENCE/'root_guard.json'))
    check(all(digest(i['path'])==i['sha256'] for i in guard),'Protected root changed')
    snapshot=json.loads(read(EVIDENCE/'test_inputs.json'))
    check(all(digest(ROOT/i['path'])==i['sha256'] for i in snapshot),'Frozen test inputs changed')
    for top in TOPS:
        p=ROOT/'sim/batch_buzzer_core_r1_20261103_validation'/(top+'.log')
        text=read(p) if p.exists() else ''
        summary=re.findall(r'^.*ALL PASS.*$',text,re.M)
        if re.search(r'Fatal:|Error:|\bFAIL\b',text):issues.append('Failed simulation '+top)
        elif not summary or 'Exiting xsim' not in text:pending.append(top)
        else:passes.append({'top':top,'log':str(p.relative_to(ROOT)),
                            'sha256':digest(p),'result':summary[-1]})
    out['passedCount']=len(passes);out['requiredCount']=len(TOPS)
    previous=json.loads(read(EVIDENCE/'previous_delivery.json'))
    prev_ver=ROOT/'sim/motor_resume_20261102_validation/verification.json'
    check(digest(prev_ver)==previous['verificationSha256'],'Previous delivery evidence changed')
    prev=json.loads(read(prev_ver));old=json.loads(read(previous['buildRecord']))
    check(prev['status']=='verified_no_board_test','Previous release was not verified')
    check(all(Path(i['Path']).resolve() in {Path(j['Path']).resolve() for j in r['inputHashes']}
              for i in old['inputHashes']),'Previous project input missing')
    unexpected=[i['Path'] for i in old['inputHashes'] if digest(i['Path'])!=i['Hash'] and
                Path(i['Path']).relative_to(ROOT).as_posix() not in changed]
    check(not unexpected,'Existing project inputs changed outside alarm scope')
    out['preservedPreviousDelivery']={'record':previous['buildRecord'],
        'bitHash':previous['bitHash'],'unchangedExistingTopModules':True,
        'scope':'Prior AE/AWB/ISP/video/UI evidence retained; current control/FPS tests rerun.'}
    check(Path(r['project']).resolve()==ROOT/'td_project/camera_to_dsi_display.al','Wrong project')
    check(all(digest(i['Path'])==i['Hash'] for i in r['inputHashes']),'Build source hash drift')
    syn,phy=Path(r['synthesis']),Path(r['implementation'])
    check(all(source_list(d/'camera_to_dsi_display.prj')==source_list(r['project'])
              for d in [syn,phy]),'Executed project sources differ')
    check(all(digest(d/n)==digest(ROOT/'user_source/hdl_source'/n)
              for d in [syn,phy] for n in ROMS),'Executed ROM copies differ')
    out['build']={'record':str(args.build_record.resolve()),'status':r['status'],
                  'inputCount':len(r['inputHashes'])}
    if r['status']!='complete':pending.append('Final TD implementation and timing')
    else:
        route=read(phy/'route_flow.status');timing=read(phy/'final_timing.rpt')
        physical={'setupWnsNs':r['setupWnsNs'],'holdWnsNs':r['holdWnsNs'],
                  'staCoveragePct':float(re.search(r'STA coverage\s*:\s*([\d.]+)%',timing)[1])}
        for label in ['Setup','Hold']:
            m=re.search(label+r'\s*:\s*WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)',route)
            check(bool(m and int(m[1])>=0 and int(m[2])==0 and int(m[3])==0),label+' timing violations')
        constraint=re.search(r'^Constraint File\s*:\s*(.*?);\s*$',timing,re.M)
        check(bool(constraint and Path(constraint[1]).resolve()==ROOT/'td_project/camera_to_dsi_display.sdc'),
              'Wrong final SDC')
        area=read(phy/'camera_to_dsi_display_phy.area')
        for n in ['slice','lut6','eram','dsp']:
            m=re.search(r'^#'+n+r'\s+(\d+)\s+out of\s+(\d+)',area,re.M)
            physical[n]={'used':int(m[1]),'available':int(m[2])}
            check(int(m[1])<=int(m[2]),n+' resource overflow')
        logs=[read(max(d.glob('td_*.log'),key=lambda p:p.stat().st_mtime)) for d in [syn,phy]]
        errors=re.findall(r'^.*\b[A-Z]+-\d+\s+(?:ERROR|FATAL)\b.*$','\n'.join(logs),re.M)
        drc=re.search(r'Stage \d+ \| Routing DRC.*?End Stage \d+ \| Routing DRC',logs[1],re.S)
        check(not errors and bool(drc and all(t in drc[0] for t in
              ['No multi-drive.','No abnormal timing path.','Check Pass.'])),'Implementation errors or DRC failure')
        physical['errors']=errors;physical['routingDrcCompleted']=bool(drc)
        pinlog=EVIDENCE/'buzzer_physical_connection.log'
        if not pinlog.exists():
            pending.append('Read-only routed buzzer pin inspection')
        else:
            raw=pinlog.read_bytes()
            pintext=raw.decode('utf-16') if raw.startswith(b'\xff\xfe') else read(pinlog)
            connected=bool('BATCH_BUZZER_PHYSICAL_CONNECTION_END' in pintext and
                re.search(r'LOCATION\s*\|\s*:C12',pintext) and
                re.search(r'MODE\s*\|\s*:OUT',pintext) and
                re.search(r'PULLMODE\s*\|\s*:PULLUP',pintext) and
                re.search(r'IsPlaced\s*\|\s*True',pintext) and
                re.search(r'doq\[0\].*O_buzzer_dup_',pintext) and
                'O_buzzer_syn_4.opad' in pintext and
                str(phy/'camera_to_dsi_display_pr.db').replace('\\','/') in pintext and
                not re.search(r'\b[A-Z]+-\d+\s+(?:ERROR|FATAL)\b',pintext))
            check(connected,'Routed buzzer pad is not proven connected at C12')
            physical['buzzerPin']={'verified':connected,'pin':'C12',
                'log':str(pinlog.relative_to(ROOT)),'sha256':digest(pinlog)}
        oldlogs=[read(max(Path(old[k]).glob('td_*.log'),key=lambda p:p.stat().st_mtime))
                 for k in ['synthesis','implementation']]
        warnings=lambda ll:sorted(set(re.findall(r'^.*\b[A-Z]+-\d+ (?:CRITICAL-)?WARNING:.*$','\n'.join(ll),re.M)))
        newlines=sorted(set(warnings(logs))-set(warnings(oldlogs)))
        reviews=json.loads(read(EVIDENCE/'warning_reviews.json')) if (EVIDENCE/'warning_reviews.json').exists() else []
        check(set(newlines)=={i['warning'] for i in reviews} and all(i['reason'] for i in reviews),
              'New warning lines need explicit review')
        out['warningComparison']={'previous':warnings(oldlogs),'current':warnings(logs),
                                  'newLines':newlines,'reviews':reviews}
        save(EVIDENCE/'warning_comparison.json',out['warningComparison'])
        physical['warningCounts']=dict(Counter(re.findall(r'^([A-Z]+-\d+\s+(?:CRITICAL-)?WARNING):','\n'.join(logs),re.M)))
        out['physical']=physical;out['bit']=r['bit'];out['bitHash']=digest(r['bit'])
        check(out['bitHash']==r['bitHash'],'Bit hash differs from build record')
    if args.check_default:
        ds=ROOT/'td_project/camera_to_dsi_display_Runs/syn_1';dp=ds.parent/'phy_1'
        same=digest(dp/'camera_to_dsi_display.bit')==r.get('bitHash')
        for src,dst,names in [(syn,ds,['camera_to_dsi_display_gate.db']),
            (phy,dp,['final_timing.rpt','camera_to_dsi_display_phy.ts','camera_to_dsi_display_phy.area','route_flow.status'])]:
            same=same and all(digest(src/n)==digest(dst/n) for n in names)
        same=same and 'set parent ../syn_1' in read(dp/'settings.cfg')
        same=same and all(source_list(d/'camera_to_dsi_display.prj')==source_list(r['project']) for d in [ds,dp])
        same=same and all(digest(d/n)==digest(ROOT/'user_source/hdl_source'/n) for d in [ds,dp] for n in ROMS)
        check(same,'Default run does not match verified build')
        out['defaultRun']={'verified':bool(same),'bit':str(dp/'camera_to_dsi_display.bit')}
    out['status']='verified_no_board_test' if not issues and not pending else 'incomplete'
    save(EVIDENCE/'verification.json',out)
    print(json.dumps({k:out[k] for k in ['status','passedCount','requiredCount','issues','pending']},indent=2))
    if args.release:
        if out['status']!='verified_no_board_test':raise SystemExit('Release blocked by evidence')
        RELEASE.mkdir(parents=True,exist_ok=True)
        shutil.copy2(r['bit'],RELEASE/'camera_to_dsi_display_batch_buzzer.bit')
        shutil.copy2(args.build_record,RELEASE/'build_record.json')
        for p in EVIDENCE.iterdir():
            if p.is_file() and p.suffix in ['.json','.patch','.log','.tcl']:shutil.copy2(p,RELEASE/p.name)
        for n in ['final_timing.rpt','camera_to_dsi_display_phy.ts','camera_to_dsi_display_phy.area','route_flow.status','camera_to_dsi_display_exception.timing']:
            if (phy/n).exists():shutil.copy2(phy/n,RELEASE/n)
        for i in r['inputHashes']:
            p=Path(i['Path']);dst=RELEASE/'sources'/p.relative_to(ROOT)
            dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dst)
        for i in passes:
            dst=RELEASE/'test_logs'/Path(i['log']).name;dst.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(ROOT/i['log'],dst)
        for p in ['sim/tb_batch_buzzer.sv','sim/tb_motor_resume.sv','sim/run_industrial_regression.ps1',
                  'tools/verification/verify_batch_buzzer.py','tools/promote_batch_buzzer.ps1',
                  'docs/BATCH_BUZZER_20261103.md']:
            src=ROOT/p
            if src.exists():
                dst=RELEASE/'validation_sources'/p;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
    if out['status']!='verified_no_board_test':raise SystemExit(1)

if __name__=='__main__':main()
