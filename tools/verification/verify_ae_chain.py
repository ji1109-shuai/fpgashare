"""Verify only this copy's AE release, with traceable RTL/log/build hashes."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'sim/ae_chain_20261101_validation'


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def read(path: Path) -> str:
    return path.read_text(encoding='utf-8-sig', errors='replace')


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--build-record', type=Path, required=True)
    ap.add_argument('--release', action='store_true')
    args = ap.parse_args()
    record = json.loads(read(args.build_record))
    result = {
        'created': datetime.now().astimezone().isoformat(),
        'deliverable': 'power-on AE acquisition, independent pixel meter, actual I2C feedback, converge then hold',
        'project': str(ROOT), 'entry': str(ROOT / 'td_project/camera_to_dsi_display.al'),
        'passes': [], 'pendingTests': [], 'issues': [],
        'knownLimitations': [
            'No board download or physical camera/light/conveyor validation.',
            'Synthetic photometric response with datasheet N+2 latency; RAM behavioural models.',
            'Legacy ambient soft-shadow multi-target regression failure remains; recognition RTL unchanged.',
            'No motion/frame-difference/predictive-ID upgrade in this change.',
            'Existing SDC exceptions and incomplete STA coverage remain; ACK is not register readback.',
        ],
    }
    # Existing artifacts are authoritative; never select an arbitrary other copy.
    assert Path(record['project']).resolve() == ROOT / 'td_project/camera_to_dsi_display.al'
    preserved = json.loads(read(EVIDENCE / 'preserved_hashes.json'))
    result['protectedFiles'] = []
    for item in preserved:
        p = Path(item['Path'])
        unchanged = digest(p) == item['Hash'].upper()
        result['protectedFiles'].append({'path': str(p), 'hash': digest(p), 'unchanged': unchanged})
        if not unchanged:
            result['issues'].append(f'Protected source changed: {p}')

    rtl = ROOT / 'user_source/hdl_source'
    top = read(rtl / 'design_top_wrapper.v')
    isp = read(rtl / 'isp/isp_top.v')
    ae = read(rtl / 'uiisp_beta/ae_set.v')
    cfg = read(rtl / 'uics500_cfg/uicfgcs500.v')
    checks = {
        'bootAuto': 'O_ae_auto<=1' in top,
        'independentMeterConnected': all(s in top for s in (
            '.I_luma(S_ae_meter_luma)', '.I_luma_valid(S_ae_meter_valid)',
            '.I_luma_upd(S_ae_meter_upd)', '.O_ae_luma(S_ae_meter_luma)',
            '.O_ae_valid(S_ae_meter_valid)', '.O_ae_upd(S_ae_meter_upd)')),
        'preAwbPixelsAndMarkers': all(s in isp for s in (
            '.I_tdata(m_aixs_tdata_96),.I_tvalid(m_aixs_tvalid)',
            '.I_tuser(m_aixs_tuser),.I_tlast(m_aixs_tlast)')),
        'noMotorOrTargetAeGate': all(s not in ae + top for s in (
            'I_auto_hold', 'I_scene_clear', 'S_ae_motor_hold')),
        'sensorNackRetry': all(s in cfg for s in (
            '.O_iic_bus_error(iic_bus_error)', 'transaction_error',
            'if(!transaction_error && !iic_bus_error)')),
        'datasheetMinimumAndStableCoarseStep': 'EXP_MIN=3' in ae and 'desired_ae+coarse_exp_step' in ae,
    }
    result['chainChecks'] = checks
    result['issues'] += [f'Failed static connection check: {k}' for k, v in checks.items() if not v]

    suites = {
        'ae_chain_release_final_20261101_validation': [
            'tb_ae_meter', 'tb_ae_chain', 'tb_ae_chain_dark', 'tb_ae_chain_midlight',
            'tb_ae_chain_extreme', 'tb_ae_chain_motor', 'tb_ae_chain_nack', 'tb_ae_chain_boot_nack'],
        'ae_chain_units_release_20261101_validation': [
            'tb_ae_once', 'tb_ae_once_single', 'tb_ae_menu_status', 'tb_ae_menu_status_rd2',
            'tb_tracker_speed_boundary', 'tb_screen_menu', 'tb_batch_counter'],
        'ae_chain_raw_20261101_validation': ['tb_ae_raw_isp'],
        'ae_chain_full_system_20261101_validation': ['tb_ae_full_system'],
        'ae_chain_colour_20261101_validation': ['tb_awb_auto_reference', 'tb_auto_wb_isp'],
        'ae_chain_video_20261101_validation': ['tb_isp_video_modes', 'tb_video_tail_isp', 'tb_video_tail_isp_sobel'],
        'ae_chain_parts_20261101_validation': [
            'tb_box_tracking', 'tb_recognition_latency', 'tb_parts_multi_backlit', 'tb_parts_multi_backlit_latency'],
    }
    for folder, tops in suites.items():
        for name in tops:
            p = ROOT / 'sim' / folder / (name + '.log')
            s = read(p) if p.exists() else ''
            passed = re.findall(r'^.*(?:ALL PASS|TB_PASS screen_menu_control|PASS: simultaneous counting, overrun stop and reject recovery).*$', s, re.M)
            if re.search(r'Fatal:|Error:|TB_FAIL|\bFAIL\b', s):
                result['issues'].append(f'Failed simulation: {p}')
            elif not passed or 'Exiting xsim' not in s:
                result['pendingTests'].append(name)
            else:
                result['passes'].append({'top': name, 'log': str(p.relative_to(ROOT)),
                                         'logHash': digest(p), 'result': passed[-1].strip()})
    result['passedCount'] = len(result['passes'])
    result['requiredCount'] = sum(map(len, suites.values()))
    result['testSourceHashes'] = [
        {'path': str(p.relative_to(ROOT)), 'hash': digest(p)}
        for p in [ROOT / 'sim' / n for n in (
            'tb_ae_chain.sv', 'tb_ae_raw_isp.sv', 'tb_ae_once.sv', 'tb_ae_menu_status.sv',
            'tb_screen_menu.v', 'tb_auto_wb_isp.v', 'run_ae_chain_regression.ps1', 'run_ae_raw_isp.ps1')]
    ]
    negative = ROOT / 'sim/ae_chain_nack_negative_20261101_validation/tb_ae_chain_boot_nack.log'
    result['negativeControl'] = {'log': str(negative.relative_to(ROOT)), 'verified': False}
    if negative.exists():
        result['negativeControl'].update({'logHash': digest(negative),
            'verified': 'initialization skipped a NACK register' in read(negative)})

    changed = [i['Path'] for i in record['inputHashes'] if digest(Path(i['Path'])) != i['Hash'].upper()]
    result['build'] = {'record': str(args.build_record.resolve()), 'status': record['status'],
                       'inputCount': len(record['inputHashes']), 'changedInputs': changed}
    prior_path = ROOT / 'td_project/camera_to_dsi_display_Runs/ae_once_build_20261101_193113.json'
    prior = {i['Path']: i['Hash'] for i in json.loads(read(prior_path))['inputHashes']}
    differences = [str(Path(i['Path']).relative_to(ROOT)) for i in record['inputHashes']
                   if prior.get(i['Path']) != i['Hash']]
    allowed = {str(Path('user_source/hdl_source') / n) for n in (
        'design_top_wrapper.v', 'isp/isp_top.v', 'uics500_cfg/uicfgcs500.v',
        'uiisp_beta/ae_set.v', 'hdmi_mixer.v')}
    result['build']['productionChangesFromPriorBit'] = differences
    if set(differences) != allowed:
        result['issues'].append('Production scope differs from the five intended AE files')
    for name in ('l298n_motor_control', 'conveyor_batch_counter'):
        pattern = r'\bmodule\s+' + name + r'\b.*?\bendmodule\b'
        old = re.search(pattern, read(EVIDENCE / 'before/design_top_wrapper.v'), re.S)
        new = re.search(pattern, top, re.S)
        if not old or not new or old.group() != new.group():
            result['issues'].append(f'Unrelated control module changed: {name}')
    if changed:
        result['issues'].append('Source changed since TD build began')
    # TD's generated settings.cfg is the executed source of SDCList. Some
    # older project templates leave a basename-only SDC metadata entry in .prj;
    # keep that warning visible and verify the effective file, never ignore it.
    def sources(p: Path) -> list[str]:
        block = re.search(r'<Source_Files>.*?</Source_Files>', read(p), re.S).group()
        paths = [(p.parent / n).resolve() for n in re.findall(r'<File Path="([^"]+)"', block)]
        if p.suffix == '.prj':
            settings = read(p.parent / 'settings.cfg')
            sdc = re.search(r'^set SDCList \{"([^"]+)"\}', settings, re.M)
            assert sdc, 'Cannot resolve executed SDCList'
            actual = (p.parent / sdc[1]).resolve()
            assert actual.is_file(), f'Executed SDC missing: {actual}'
            paths = [actual if q.suffix == '.sdc' and q.name == actual.name else q for q in paths]
        return sorted(str(q).lower() for q in paths)
    current = sources(ROOT / 'td_project/camera_to_dsi_display.al')
    result['build']['sourceListsMatch'] = all(
        sources(Path(record[k]) / 'camera_to_dsi_display.prj') == current for k in ('synthesis', 'implementation'))
    if not result['build']['sourceListsMatch']:
        result['issues'].append('TD run source list differs from the project entry')
    result['build']['sdcResolution'] = 'Effective SDCList in both settings.cfg resolves to the unchanged project SDC; basename-only .prj metadata may warn.'

    if record['status'] == 'complete':
        phy = Path(record['implementation'])
        timing = read(phy / 'final_timing.rpt')
        route = read(phy / 'route_flow.status')
        area = read(phy / 'camera_to_dsi_display_phy.area')
        result['physical'] = {'setupWnsNs': record['setupWnsNs'], 'holdWnsNs': record['holdWnsNs'],
            'staCoveragePct': float(re.search(r'STA coverage\s*:\s*([\d.]+)%', timing)[1])}
        constraint = re.search(r'^Constraint File\s*:\s*(.*?);\s*$', timing, re.M)
        if not constraint or Path(constraint[1]).resolve() != ROOT / 'td_project/camera_to_dsi_display.sdc':
            result['issues'].append('Final STA used an unexpected constraint file')
        for k in ('slice', 'lut6', 'eram', 'dsp'):
            match = re.search(r'^#' + k + r'\s+(\d+)\s+out of\s+(\d+)', area, re.M)
            result['physical'][k] = {'used': int(match[1]), 'available': int(match[2])}
            if int(match[1]) > int(match[2]):
                result['issues'].append(f'Resource overflow: {k}')
        for label in ('Setup', 'Hold'):
            match = re.search(label + r'\s*:\s*WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)', route)
            if not match or int(match[1]) < 0 or int(match[2]) != 0 or int(match[3]) != 0:
                result['issues'].append(f'Non-final or failing {label} route timing')
        logs = list(phy.glob('td_*.log'))
        impl_log = read(max(logs, key=lambda p: p.stat().st_mtime))
        drc = re.search(r'Routing DRC.*?(?:End|end).*?Routing DRC', impl_log, re.S)
        result['physical']['routingDrcCompleted'] = bool(re.search(r'End.*Routing DRC|Routing DRC.*(?:complete|finish)', impl_log, re.I))
        errors = re.findall(r'^.*\b[A-Z]+-\d+\s+(?:ERROR|FATAL)\b.*$', impl_log, re.M)
        result['physical']['implementationErrors'] = errors
        if errors or not result['physical']['routingDrcCompleted']:
            result['issues'].append('Implementation errors or incomplete routing DRC')
        bit = Path(record['bit'])
        if digest(bit) != record['bitHash'].upper():
            result['issues'].append('Bit hash differs from the build record')
        result['bit'] = str(bit)
        result['bitHash'] = digest(bit)
        result['bitBytes'] = bit.stat().st_size
    elif record['status'] != 'running':
        result['issues'].append('TD build did not complete successfully')

    result['status'] = ('failed' if result['issues'] else 'pending' if
        result['pendingTests'] or record['status'] != 'complete' else 'verified_no_board_test')
    output = EVIDENCE / 'verification.json'
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    if args.release:
        assert result['status'] == 'verified_no_board_test', result
        assert result['negativeControl']['verified'], 'Expected old-NACK negative control missing'
        dest = ROOT / 'release_archive/ae_chain_boot_20261101'
        dest.mkdir(parents=True, exist_ok=True)
        delivered = dest / 'camera_to_dsi_display_ae_chain_boot.bit'
        if delivered.exists():
            assert digest(delivered) == result['bitHash'], 'Refusing to overwrite a different release bit'
        else:
            shutil.copy2(result['bit'], delivered)
        assert digest(delivered) == result['bitHash'], 'Copied bit did not match the verified build'
        for name in ['final_timing.rpt', 'camera_to_dsi_display_phy.ts', 'camera_to_dsi_display_phy.area',
                     'camera_to_dsi_display_exception.timing', 'route_flow.status']:
            shutil.copy2(Path(record['implementation']) / name, dest / name)
        result['deliveredBit'] = str(delivered)
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
        shutil.copy2(output, dest / 'verification.json')
        shutil.copy2(args.build_record, dest / args.build_record.name)
    print(json.dumps({'status': result['status'], 'passed': result['passedCount'],
        'required': result['requiredCount'], 'pending': result['pendingTests'], 'issues': result['issues'],
        'build': result['build'], 'physical': result.get('physical'),
        'bit': result.get('deliveredBit'), 'bitHash': result.get('bitHash')}, ensure_ascii=False, indent=2))
    if result['issues']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
