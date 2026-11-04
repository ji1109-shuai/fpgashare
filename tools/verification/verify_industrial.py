"""Verify the actual industrial release, including ROM assets and default runs."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import shutil
from collections import Counter
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'sim/industrial_upgrade_20261102_validation'
RELEASE = ROOT / 'release_archive/industrial_20261102'
SUITES = {
    'industrial_core_r9_20261102_validation': [
        'tb_industrial_enhance','tb_industrial_counter','tb_industrial_tracker','tb_industrial_menu',
        'tb_ae_target','tb_ae_once','tb_ae_once_single','tb_ae_boot_keys','tb_industrial_ui','tb_industrial_ui_rd2'],
    'industrial_ae_r3_20261102_validation': [
        'tb_ae_meter','tb_ae_chain','tb_ae_chain_dark','tb_ae_chain_midlight','tb_ae_chain_extreme',
        'tb_ae_chain_gain_low','tb_ae_chain_gain_high','tb_ae_chain_motor','tb_ae_chain_nack',
        'tb_ae_chain_boot_nack','tb_ae_chain_target_low','tb_ae_chain_target_high','tb_ae_chain_retarget'],
    'industrial_video_r8_20261102_validation': [
        'tb_video_modes','tb_video_modes_onebeat','tb_video_modes_720p','tb_isp_video_modes',
        'tb_video_mode_osd','tb_target_overlay','tb_parts_overlay','tb_video_tail_isp','tb_video_tail_isp_sobel','tb_video_tail_isp_enhance'],
    'industrial_colour_r4_20261102_validation': [
        'tb_awb_auto_reference','tb_bayer_neutral','tb_auto_wb_isp','tb_colour_ratios','tb_wb_reference',
        'tb_colour_stream_error','tb_awb','tb_wb_invalid','tb_wb_probe','tb_wb_probe_isp'],
    'industrial_parts_r1_20261102_validation': ['tb_parts_color_hsv','tb_parts_shape_pipeline'],
    'industrial_parts_r7_20261102_validation': [
        'tb_parts_multi_backlit','tb_parts_multi_backlit_latency','tb_parts_solid_rejection',
        'tb_box_tracking','tb_recognition_latency'],
    'industrial_csi_r4_20261102_validation': ['tb_ae_csi_system'],
}

def read(p): return Path(p).read_text(encoding='utf-8-sig',errors='replace')
def digest(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def save(p, d): Path(p).write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
def source_list(p):
    p=Path(p)
    block=re.search(r'<Source_Files>.*?</Source_Files>',read(p),re.S)[0]
    paths=[(p.parent/x).resolve() for x in re.findall(r'<File Path="([^"]+)"',block)]
    if p.suffix=='.prj':
        sdc=re.search(r'^set SDCList \{"([^"]+)"\}',read(p.parent/'settings.cfg'),re.M)
        assert sdc,'Missing executed SDCList'
        actual=(p.parent/sdc[1]).resolve()
        assert actual.is_file(),actual
        paths=[actual if f.suffix=='.sdc' and f.name==actual.name else f for f in paths]
    return sorted(str(f).lower() for f in paths)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--build-record',required=True,type=Path)
    ap.add_argument('--release',action='store_true')
    ap.add_argument('--check-default',action='store_true')
    args=ap.parse_args()
    r=json.loads(read(args.build_record))
    issues=[];pending=[];passed=[]
    out={'created':datetime.now().astimezone().isoformat(),'status':'pending','project':str(ROOT),
         'boardProgrammed':False,'issues':issues,'pendingTests':pending,'passes':passed,
         'ae':{'target':152,'low':144,'high':160,'stableObservations':16,'primaryActuator':'exposure',
               'gainFallback':'exposure bounds or <=8 shutter-code direction reversal, one-code gain trim'},
         'enhancement':{'mode':7,'defaultStrength':2,'defaultNoise':4,'detailLimit':24,'displayOnly':True},
         'counting':{'direction':'left to right','upstreamArmMaxX':624,'downstreamCountMinX':656,
                     'maxTargets':4,'missingPublicationsRetained':2,'automaticRejectRecovery':False},
         'limitations':['No board or physical camera validation.',
             'Existing ordinary-light wide-shadow/shape failures remain; image enhancement affects display only.',
             'Existing interface warnings, SDC exceptions and incomplete STA coverage remain.',
             'Sensor response and some vendor RAMs use functional simulation models.']}
    for folder,tops in SUITES.items():
        for top in tops:
            p=ROOT/'sim'/folder/(top+'.log');s=read(p) if p.exists() else ''
            summaries=re.findall(r'^.*ALL PASS.*$',s,re.M)
            if re.search(r'Fatal:|Error:|\bFAIL\b',s): issues.append('Simulation failure: '+top)
            elif not summaries or 'Exiting xsim' not in s: pending.append(top)
            else: passed.append({'top':top,'log':str(p.relative_to(ROOT)),'sha256':digest(p),'result':summaries[-1]})
    out['requiredCount']=sum(map(len,SUITES.values()));out['passedCount']=len(passed)
    manifest=EVIDENCE/'test_inputs.json'
    if not manifest.exists(): issues.append('Missing test input snapshot')
    else:
        inputs=json.loads(read(manifest));out['testInputCount']=len(inputs)
        for i in inputs:
            if digest(ROOT/i['path'])!=i['sha256']: issues.append('Test input changed: '+i['path'])
    if Path(r['project']).resolve()!=ROOT/'td_project/camera_to_dsi_display.al': issues.append('Wrong project')
    changed=[i['Path'] for i in r['inputHashes'] if digest(i['Path'])!=i['Hash'].upper()]
    if changed: issues.append('Production inputs changed during build')
    syn=Path(r['synthesis']);phy=Path(r['implementation'])
    lists_ok=all(source_list(p/'camera_to_dsi_display.prj')==source_list(r['project']) for p in (syn,phy))
    if not lists_ok: issues.append('Executed source lists differ')
    roms=[]
    for name in ['industrial_font16.hex','logo_idx.hex','logo_pal.hex']:
        p=ROOT/'user_source/hdl_source'/name
        ok=all((q/name).exists() and digest(q/name)==digest(p) for q in (syn,phy))
        if not ok: issues.append('Run ROM mismatch: '+name)
        if str(p).lower() not in {i['Path'].lower() for i in r['inputHashes']}: issues.append('ROM absent from input manifest: '+name)
        roms.append({'file':name,'sha256':digest(p),'runCopiesMatch':ok})
    out['build']={'record':str(args.build_record.resolve()),'status':r['status'],'inputCount':len(r['inputHashes']),
                  'changedInputs':changed,'sourceListsMatch':lists_ok,'romAssets':roms}
    prior_path=sorted((ROOT/'td_project/camera_to_dsi_display_Runs').glob('ae_exp_r1_build_*.json'))[-1]
    prior=json.loads(read(prior_path))
    diff=[str(Path(i['Path']).relative_to(ROOT)).replace('\\','/') for i in prior['inputHashes'] if digest(i['Path'])!=i['Hash']]
    expected={'user_source/hdl_source/'+n for n in ['design_top_wrapper.v','hdmi_mixer.v','isp/isp_top.v','img_proj.v','img_video_modes.v','osd_char_lib.v','uiisp_beta/ae_set.v']}
    out['build']['productionChangesFromAE4']=diff
    if set(diff)!=expected: issues.append('Unexpected production/constraint changes from previous AE4 release')
    top=read(ROOT/'user_source/hdl_source/design_top_wrapper.v')
    isp=read(ROOT/'user_source/hdl_source/isp/isp_top.v')
    ae=read(ROOT/'user_source/hdl_source/uiisp_beta/ae_set.v')
    modes=read(ROOT/'user_source/hdl_source/img_video_modes.v')
    checks={
        'defaultEnhancementAndTarget':'O_preview_mode<=7;O_motor_level<=0;' in top and 'O_ae_target_level<=19' in top,
        'actualI2cExposureConnection':bool(re.search(r'\bu_ae_set\s*\([^;]*\.O_ae\(S_ae\)[^;]*\.O_ag\(S_ag\)',top,re.S) and
            re.search(r'\bu_uicfgcs500\s*\([^;]*\.I_ae_req\(S_ae_req\)[^;]*\.I_ae\(S_ae\)[^;]*\.I_ag\(S_ag\)',top,re.S)),
        'narrowBandAndLock':"target_center-8'd8" in ae and "target_center+8'd8" in ae and 'AE_LOCK_FRAMES=16' in ae,
        'newEnhancementConnected':'.I_enhance_strength(S_menu_enhance_strength)' in top and '.I_enhance(enhance_mode)' in isp,
        'cartoonRemoved':not re.search(r'posterize|I_cartoon|cartoon_data|CART',modes+isp),
        'counterTotalsAndExplicitRecovery':'.O_total_counts_bcd(S_batch_total_counts_bcd)' in top and 'I_menu_ack && O_overrun' in top,
        'faultStopsMotor':'S_batch_done|S_batch_overrun|S_batch_wait_clear' in top,
        'uniformSyncFont':'osd_font_sync' in read(ROOT/'user_source/hdl_source/hdmi_mixer.v'),
    }
    out['chainChecks']=checks
    issues.extend('Static chain check: '+k for k,v in checks.items() if not v)
    out['runtimeExposureEvidence']=[]
    for item in passed:
        if not (item['top'].startswith('tb_ae_chain') or item['top']=='tb_ae_csi_system'): continue
        log=read(ROOT/item['log'])
        writes=[list(map(int,m)) for m in re.findall(r'I2C AE complete seq=(\d+) decoded_EXP=(\d+) previous_EXP=(\d+) GAIN=(\d+) previous_GAIN=(\d+)',log)]
        summary=re.search(r'locked_exp=(\d+) gain=(\d+) exposure_changes=(\d+) gain_changes=(\d+)',log)
        if not summary: issues.append('Missing decoded I2C summary: '+item['top']);continue
        exp,gain,exp_changes,gain_changes=map(int,summary.groups())
        for seq,e,pe,g,pg in writes:
            valid_gain=e==3 if g<pg else e==2244
            valid_gain=valid_gain or (e<=8 and abs(g-pg)==1)
            if (e!=pe and g!=pg) or (g!=pg and not valid_gain): issues.append('I2C actuator priority violation: '+item['top'])
        out['runtimeExposureEvidence'].append({'top':item['top'],'lockedExposure':exp,'lockedGain':gain,'exposureChanges':exp_changes,'gainChanges':gain_changes,'decodedWrites':writes})
    guard=EVIDENCE/'other_projects_guard.json'
    if guard.exists():
        changes=[name for name,h in json.loads(read(guard)).items() if digest(name).lower()!=h.lower()]
        out['otherProjectsProductionChanges']=changes
        if changes: issues.append('Protected sibling project source changed')
    baseline=ROOT/'sim/industrial_prior_parts_20261102_validation/tb_parts.log'
    current=ROOT/'sim/industrial_parts_r1_20261102_validation/tb_parts.log'
    failure=r'kind10 angle0 radius64 offset0 type7 expected3 status4'
    if not baseline.exists() or not current.exists() or not all(re.search(failure,read(p)) for p in [baseline,current]):
        issues.append('Prior shape/shadow limitation comparison incomplete')
    else: out['knownFailureComparison']={'unchanged':True,'diagnostic':failure,
        'beforeLog':str(baseline.relative_to(ROOT)),'beforeHash':digest(baseline),
        'afterLog':str(current.relative_to(ROOT)),'afterHash':digest(current)}
    csi=ROOT/'sim/industrial_csi_r4_20261102_validation/tb_ae_csi_system.log'
    if csi.exists():
        observations=[dict(zip(['frame','valid','luma','cfg','aeCfg','exposure','gain','locked'],map(int,m))) for m in
            re.findall(r'CSI AE frame=(\d+) valid=(\d+) luma=(\d+) cfg=(\d+)/(\d+) exp=(\d+) gain=(\d+) locked=(\d+)',read(csi))]
        locked=[o for o in observations if o['locked']]
        if locked:
            out['csi']={'firstLock':locked[0],'holdFramesAfterLock':len(locked)-1,'lastFrame':observations[-1]}
            if not 144<=locked[0]['luma']<=160 or len(locked)<13: issues.append('CSI lock/12-frame hold incomplete')
    if r['status']=='complete':
        timing=read(phy/'final_timing.rpt');route=read(phy/'route_flow.status');area=read(phy/'camera_to_dsi_display_phy.area')
        physical={'setupWnsNs':r['setupWnsNs'],'holdWnsNs':r['holdWnsNs'],
                  'staCoveragePct':float(re.search(r'STA coverage\s*:\s*([\d.]+)%',timing)[1])}
        for label in ['Setup','Hold']:
            m=re.search(label+r'\s*:\s*WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)',route)
            if not m or int(m[1])<0 or int(m[2])!=0 or int(m[3])!=0: issues.append('Final '+label+' timing failed')
        constraint=re.search(r'^Constraint File\s*:\s*(.*?);\s*$',timing,re.M)
        if not constraint or Path(constraint[1]).resolve()!=ROOT/'td_project/camera_to_dsi_display.sdc': issues.append('Wrong executed SDC')
        for name in ['slice','lut6','eram','dsp']:
            m=re.search(r'^#'+name+r'\s+(\d+)\s+out of\s+(\d+)',area,re.M)
            physical[name]={'used':int(m[1]),'available':int(m[2])}
            if int(m[1])>int(m[2]): issues.append('Resource overflow: '+name)
        logs=[read(max(q.glob('td_*.log'),key=lambda p:p.stat().st_mtime)) for q in (syn,phy)]
        errors=re.findall(r'^.*\b[A-Z]+-\d+\s+(?:ERROR|FATAL)\b.*$','\n'.join(logs),re.M)
        drc=re.search(r'Stage \d+ \| Routing DRC.*?End Stage \d+ \| Routing DRC',logs[1],re.S)
        physical['routingDrcCompleted']=bool(drc)
        physical['drcChecks']={s:bool(drc and s in drc[0]) for s in ['No multi-drive.','No abnormal timing path.','Check Pass.']}
        physical['errors']=errors
        physical['warningCounts']=dict(Counter(re.findall(r'^([A-Z]+-\d+\s+(?:CRITICAL-)?WARNING):','\n'.join(logs),re.M)))
        if errors or not all(physical['drcChecks'].values()): issues.append('Implementation/DRC failed')
        out['physical']=physical;out['bit']=r['bit'];out['bitHash']=digest(r['bit'])
        if out['bitHash']!=r['bitHash']: issues.append('Bit hash differs from record')
    else: pending.append('TD build and final timing')
    if args.check_default:
        default_bit=ROOT/'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit'
        same=default_bit.exists() and digest(default_bit)==r.get('bitHash')
        for old,new,files in [(syn,default_bit.parent.parent/'syn_1',['camera_to_dsi_display_gate.db']),
                              (phy,default_bit.parent,['final_timing.rpt','camera_to_dsi_display_phy.ts','camera_to_dsi_display_phy.area','route_flow.status'])]:
            same=bool(same and all((new/f).exists() and digest(old/f)==digest(new/f) for f in files))
        same=bool(same and 'set parent ../syn_1' in read(default_bit.parent/'settings.cfg'))
        default_dirs=[default_bit.parent.parent/'syn_1',default_bit.parent]
        default_lists=all(source_list(q/'camera_to_dsi_display.prj')==source_list(r['project']) for q in default_dirs)
        default_roms=all((q/name).exists() and digest(q/name)==digest(ROOT/'user_source/hdl_source'/name)
            for q in default_dirs for name in ['industrial_font16.hex','logo_idx.hex','logo_pal.hex'])
        same=bool(same and default_lists and default_roms)
        out['defaultRun']={'verified':same,'bit':str(default_bit),
                           'sourceListsMatch':default_lists,'romAssetsMatch':default_roms}
        if not same: issues.append('Default run identity mismatch')
    out['status']='verified_no_board_test' if not issues and not pending else 'incomplete'
    save(EVIDENCE/'verification.json',out)
    print(json.dumps({k:out[k] for k in ['status','passedCount','requiredCount','pendingTests','issues']},ensure_ascii=False,indent=2))
    if args.release:
        if out['status']!='verified_no_board_test': raise SystemExit('Release blocked by evidence')
        RELEASE.mkdir(exist_ok=True,parents=True)
        shutil.copy2(r['bit'],RELEASE/'camera_to_dsi_display_industrial.bit')
        shutil.copy2(args.build_record,RELEASE/'build_record.json')
        shutil.copy2(EVIDENCE/'verification.json',RELEASE/'verification.json')
        for f in ['final_timing.rpt','camera_to_dsi_display_phy.ts','camera_to_dsi_display_phy.area','route_flow.status','camera_to_dsi_display_exception.timing']:
            if (phy/f).exists(): shutil.copy2(phy/f,RELEASE/f)
        for item in r['inputHashes']:
            p=Path(item['Path']);dest=RELEASE/'sources'/p.relative_to(ROOT)
            dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
        for item in passed:
            p=ROOT/item['log'];dest=RELEASE/'test_logs'/(item['top']+'.log');dest.parent.mkdir(exist_ok=True);shutil.copy2(p,dest)
    if out['status']!='verified_no_board_test': raise SystemExit(1)

if __name__=='__main__': main()
