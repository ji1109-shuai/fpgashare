"""Independent evidence gate for the (4) whole-machine transparent HUD release."""
import argparse
import difflib
import json
import re
import shutil
from collections import Counter
from datetime import datetime
from pathlib import Path
from verify_visual import digest, read, save, source_list

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'sim/ui_overlay_20261102_validation'
PREVIOUS = ROOT / 'sim/visual_upgrade_20261102_validation'
RELEASE = ROOT / 'release_archive/ui_overlay_20261102'
SUITES = {
    'ui_overlay_core_r2_20261102_validation': ['tb_industrial_ui', 'tb_industrial_ui_rd2', 'tb_industrial_menu', 'tb_industrial_counter'],
    'ui_overlay_video_20261102_validation': ['tb_video_mode_osd', 'tb_target_overlay', 'tb_parts_overlay'],
}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--build-record', required=True, type=Path)
    ap.add_argument('--release', action='store_true')
    ap.add_argument('--check-default', action='store_true')
    args = ap.parse_args()
    record = json.loads(read(args.build_record))
    issues, pending, passed = [], [], []
    def check(ok, message):
        if not ok:
            issues.append(message)
    out = {'created': datetime.now().astimezone().isoformat(), 'status': 'incomplete',
        'project': str(ROOT), 'boardProgrammed': False, 'issues': issues, 'pending': pending,
        'testsRunThisRelease': passed,
        'ui': {'transparentLeftHud': True, 'fontPixels': [16,16], 'rowPitchPixels': 20,
            'removedRows': ['AE5 state and measured Y', 'TARGET and tolerance'],
            'batchStatusY': 180, 'contrast': 'per-pixel majority of RGB most significant bits',
            'states': ['RUN','READY','NG / ACK','CLEAR VIEW','COMPLETE'],
            'rightMenuPreserved': True, 'aeTargetRemainsInMenu': True},
        'limitations': ['No board validation.', 'Prior AE/CSI/ISP/enhancement evidence is reused only for unchanged logic.',
            'Existing warnings, SDC exceptions and incomplete STA coverage remain.']}
    baseline = json.loads(read(EVIDENCE/'before_manifest.json'))
    diff = [i['path'] for i in baseline if digest(ROOT/i['path']) != i['sha256'].upper()]
    check(diff == ['user_source/hdl_source/hdmi_mixer.v'], 'Unexpected production changes from visual release')
    out['productionChanges'] = diff
    out['baselineInputCount'] = len(baseline)
    guard = json.loads(read(EVIDENCE/'root_guard.json'))
    changed_guard = [i['path'] for i in guard if digest(i['path']) != i['sha256'].upper()]
    check(not changed_guard, 'Protected root project changed')
    out['otherProjectsProductionChanges'] = changed_guard
    snap = json.loads(read(EVIDENCE/'test_inputs.json'))
    check(all(digest(ROOT/i['path']) == i['sha256'].upper() for i in snap), 'Current test input changed')
    for folder, tops in SUITES.items():
        for top in tops:
            p = ROOT/'sim'/folder/(top+'.log')
            s = read(p) if p.exists() else ''
            summary = re.findall(r'^.*ALL PASS.*$', s, re.M)
            if re.search(r'Fatal:|Error:|\bFAIL\b', s):
                issues.append('Simulation failure: '+top)
            elif not summary or 'Exiting xsim' not in s:
                pending.append(top)
            else:
                passed.append({'top':top,'log':str(p.relative_to(ROOT)), 'sha256':digest(p),'result':summary[-1]})
    for item in passed:
        if item['top'] in ['tb_industrial_ui','tb_industrial_ui_rd2']:
            check('ten full 720p rasters' in item['result'] and '608421 transparent pixels' in item['result'], 'Incomplete transparent HUD coverage')
    negative = json.loads(read(EVIDENCE/'negative_control.json'))
    negative_log = read(ROOT/negative['log'])
    check(negative['status']=='expected_failure' and 'Fatal: HUD RD=0 scenario=0 x=168 y=12' in negative_log,
        'Old panel was not rejected by the new UI test')
    out['negativeControl'] = dict(negative, logHash=digest(ROOT/negative['log']))
    old = json.loads(read(PREVIOUS/'verification.json'))
    check(old['status'] == 'verified_no_board_test', 'Previous visual release not verified')
    old_inputs = json.loads(read(PREVIOUS/'test_inputs.json'))
    old_changes = [i['path'] for i in old_inputs if digest(ROOT/i['path']) != i['sha256'].upper()]
    check(set(old_changes) == {'user_source/hdl_source/hdmi_mixer.v','sim/tb_industrial_ui.sv'}, 'Unexpected changed inputs invalidate reused evidence')
    rerun = {top for tops in SUITES.values() for top in tops}
    reused = [i for i in old['passes'] if i['top'] not in rerun]
    check(len(reused) == 30, 'Unexpected prior evidence count')
    check(all(digest(ROOT/i['log']) == i['sha256'].upper() for i in reused), 'Previous evidence log changed')
    out['reusedFunctionalEvidence'] = {'record':str(PREVIOUS/'verification.json'), 'sha256':digest(PREVIOUS/'verification.json'),
        'count':len(reused),'changedPreviousInputs':old_changes,'passes':reused,
        'scope':'Unchanged AE, CSI, ISP, tone, enhancement and video pipeline; current display/menu/counting tests rerun separately.'}
    out['diagnosticHistory'] = [{'initialLog':'sim/ui_overlay_core_20261102_validation/tb_industrial_ui.log',
        'initialResult':'Unknown synthetic camera background value; raw itself was X.',
        'correction':'Make the testbench background function automatic and pass scenario explicitly, avoiding concurrent static argument storage.',
        'productionRtlChangedForThisCorrection':False,
        'finalRuns':['tb_industrial_ui','tb_industrial_ui_rd2'], 'finalResult':'All ten frames passed for both latencies.'}]
    check(Path(record['project']).resolve() == ROOT/'td_project/camera_to_dsi_display.al', 'Wrong project')
    check(all(digest(i['Path']) == i['Hash'].upper() for i in record['inputHashes']), 'Build inputs changed')
    syn, phy = Path(record['synthesis']), Path(record['implementation'])
    lists_ok = all(source_list(q/'camera_to_dsi_display.prj') == source_list(record['project']) for q in (syn,phy))
    check(lists_ok, 'Executed source lists differ')
    roms = ['industrial_font16.hex','logo_idx.hex','logo_pal.hex']
    rom_ok = all(digest(q/name) == digest(ROOT/'user_source/hdl_source'/name) for q in (syn,phy) for name in roms)
    check(rom_ok, 'Run ROM mismatch')
    out['build'] = {'record':str(args.build_record.resolve()),'status':record['status'],
        'inputCount':len(record['inputHashes']), 'sourceListsMatch':lists_ok,'romAssetsMatch':rom_ok}
    if 'physicalSettingsHash' in record:
        check(digest(phy/'settings.cfg')==record['physicalSettingsHash'], 'Physical strategy settings changed')
        out['build'].update({'physicalStrategy':record['physicalStrategy'], 'physicalParameters':record['physicalParameters'],
            'synthesisReusedFrom':record['synthesisReusedFrom'], 'physicalSettingsHash':record['physicalSettingsHash']})
    before = read(EVIDENCE/'before/hdmi_mixer.v')
    current = read(ROOT/'user_source/hdl_source/hdmi_mixer.v')
    (EVIDENCE/'hdmi_mixer_ui.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True),current.splitlines(True),fromfile='before/hdmi_mixer.v',tofile='after/hdmi_mixer.v')),encoding='utf-8')
    check('AE5:MAN' not in current and 'TARGET: 152 +/-8' not in current and 'control_panel_on' not in current, 'Old debug HUD remains')
    check('AE Y    152' in current and 'BATCH: NG / ACK' in current, 'Required controls/status missing')
    if record['status'] != 'complete':
        pending.append('TD build and final timing')
    else:
        route, timing, area = (read(phy/name) for name in ['route_flow.status','final_timing.rpt','camera_to_dsi_display_phy.area'])
        physical = {'setupWnsNs':record['setupWnsNs'],'holdWnsNs':record['holdWnsNs'],
            'staCoveragePct':float(re.search(r'STA coverage\s*:\s*([\d.]+)%',timing)[1])}
        for label in ['Setup','Hold']:
            m = re.search(label+r'\s*:\s*WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)',route)
            check(bool(m and int(m[1])>=0 and int(m[2])==0 and int(m[3])==0), 'Final '+label+' timing failed')
        constraint = re.search(r'^Constraint File\s*:\s*(.*?);\s*$',timing,re.M)
        check(bool(constraint and Path(constraint[1]).resolve()==ROOT/'td_project/camera_to_dsi_display.sdc'), 'Wrong executed SDC')
        for name in ['slice','lut6','eram','dsp']:
            m = re.search(r'^#'+name+r'\s+(\d+)\s+out of\s+(\d+)',area,re.M)
            physical[name] = {'used':int(m[1]),'available':int(m[2])}
            check(int(m[1])<=int(m[2]), 'Resource overflow: '+name)
        logs = [read(max(q.glob('td_*.log'),key=lambda p:p.stat().st_mtime)) for q in (syn,phy)]
        errors = re.findall(r'^.*\b[A-Z]+-\d+\s+(?:ERROR|FATAL)\b.*$', '\n'.join(logs),re.M)
        drc = re.search(r'Stage \d+ \| Routing DRC.*?End Stage \d+ \| Routing DRC',logs[1],re.S)
        physical['errors'] = errors
        physical['routingDrcCompleted'] = bool(drc)
        physical['drcChecks'] = {s:bool(drc and s in drc[0]) for s in ['No multi-drive.','No abnormal timing path.','Check Pass.']}
        physical['warningCounts'] = dict(Counter(re.findall(r'^([A-Z]+-\d+\s+(?:CRITICAL-)?WARNING):','\n'.join(logs),re.M)))
        check(not errors and all(physical['drcChecks'].values()), 'Implementation/DRC failed')
        previous_record = json.loads(read(old['build']['record']))
        previous_logs = [read(max(Path(previous_record[k]).glob('td_*.log'),key=lambda p:p.stat().st_mtime)) for k in ['synthesis','implementation']]
        critical = lambda ss: sorted(set(re.findall(r'^.*\b[A-Z]+-\d+ CRITICAL-WARNING:.*$', '\n'.join(ss), re.M)))
        prev_critical, new_critical = critical(previous_logs), critical(logs)
        warning_comparison = {'previousRecord':old['build']['record'], 'currentRecord':str(args.build_record),
            'previousCriticalWarnings':prev_critical,'currentCriticalWarnings':new_critical,'newCriticalWarnings':sorted(set(new_critical)-set(prev_critical))}
        # Removal of the AE debug HUD reduces this existing camera-clock load.
        # Review only the exact observed change; never suppress other warnings.
        old_clock_warning = 'PHY-5060 CRITICAL-WARNING: Clock net candidate O_cam_24m_syn_3 has mixed fanouts of 397 clock pins; 1 data/ctrl pins. Please check connection of the net in design.'
        new_clock_warning = old_clock_warning.replace('397 clock pins', '384 clock pins')
        reviewed = []
        if old_clock_warning in prev_critical and new_clock_warning in warning_comparison['newCriticalWarnings']:
            reviewed.append({'before':old_clock_warning,'after':new_clock_warning,
                'reason':'Existing camera-clock mixed-fanout warning; AE diagnostic HUD removal reduces clock sinks 397 to 384. The same one data/control sink remains. No clock RTL or constraints changed.'})
        warning_comparison['rawNewCriticalWarnings'] = warning_comparison['newCriticalWarnings'][:]
        warning_comparison['reviewedExistingWarningChanges'] = reviewed
        warning_comparison['newCriticalWarnings'] = [w for w in warning_comparison['newCriticalWarnings'] if w not in {i['after'] for i in reviewed}]
        save(EVIDENCE/'critical_warning_comparison.json', warning_comparison)
        check(not warning_comparison['newCriticalWarnings'], 'New critical warnings require review')
        out['physical'] = physical
        out['criticalWarningComparison'] = warning_comparison
        out['bit'], out['bitHash'] = record['bit'], digest(record['bit'])
        check(out['bitHash']==record['bitHash'], 'Bit differs from record')
    if args.check_default:
        default_syn = ROOT/'td_project/camera_to_dsi_display_Runs/syn_1'
        default_phy = default_syn.parent/'phy_1'
        same = digest(default_phy/'camera_to_dsi_display.bit') == record.get('bitHash')
        for src,dst,names in [(syn,default_syn,['camera_to_dsi_display_gate.db']), (phy,default_phy,['final_timing.rpt','camera_to_dsi_display_phy.ts','camera_to_dsi_display_phy.area','route_flow.status'])]:
            same = same and all(digest(src/n)==digest(dst/n) for n in names)
        same = same and 'set parent ../syn_1' in read(default_phy/'settings.cfg')
        same = same and all(source_list(q/'camera_to_dsi_display.prj')==source_list(record['project']) for q in (default_syn,default_phy))
        same = same and all(digest(q/n)==digest(ROOT/'user_source/hdl_source'/n) for q in (default_syn,default_phy) for n in roms)
        out['defaultRun'] = {'verified':bool(same),'bit':str(default_phy/'camera_to_dsi_display.bit')}
        check(same, 'Default run identity mismatch')
    out['passedCount'], out['requiredCount'] = len(passed), sum(map(len,SUITES.values()))
    out['status'] = 'verified_no_board_test' if not issues and not pending else 'incomplete'
    save(EVIDENCE/'verification.json',out)
    print(json.dumps({k:out[k] for k in ['status','passedCount','requiredCount','pending','issues']},ensure_ascii=False,indent=2))
    if args.release:
        if out['status']!='verified_no_board_test':
            raise SystemExit('Release blocked by evidence')
        RELEASE.mkdir(parents=True,exist_ok=True)
        shutil.copy2(record['bit'],RELEASE/'camera_to_dsi_display_ui_overlay.bit')
        shutil.copy2(args.build_record,RELEASE/'build_record.json')
        for p in EVIDENCE.iterdir():
            if p.is_file() and p.suffix in ['.json','.patch','.png']:
                shutil.copy2(p,RELEASE/p.name)
        for name in ['final_timing.rpt','camera_to_dsi_display_phy.ts','camera_to_dsi_display_phy.area','route_flow.status','camera_to_dsi_display_exception.timing']:
            if (phy/name).exists():
                shutil.copy2(phy/name,RELEASE/name)
        for item in record['inputHashes']:
            p = Path(item['Path']); dst = RELEASE/'sources'/p.relative_to(ROOT)
            dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(p,dst)
        for item in passed:
            dst = RELEASE/'test_logs'/(item['top']+'.log'); dst.parent.mkdir(exist_ok=True)
            shutil.copy2(ROOT/item['log'],dst)
        doc = ROOT/'docs/UI_OVERLAY_20261102.md'
        if doc.exists():
            shutil.copy2(doc,RELEASE/doc.name)
    if out['status']!='verified_no_board_test':
        raise SystemExit(1)

if __name__ == '__main__':
    main()
