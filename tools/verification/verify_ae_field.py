"""Verify the field follow-up, including the native CSI path and boot keys."""
from __future__ import annotations
import argparse
import json
import re
import shutil
from datetime import datetime
from pathlib import Path
from verify_ae_chain import ROOT, read, digest

EVIDENCE = ROOT / 'sim/ae_field_20261101_validation'
SUITES = {
    'ae_field_markers_fixed_20261101_validation': ['tb_image_correction_markers'],
    'ae_field_units_20261101_validation': ['tb_ae_boot_keys', 'tb_ae_once', 'tb_ae_once_single',
        'tb_ae_menu_status', 'tb_ae_menu_status_rd2', 'tb_screen_menu', 'tb_batch_counter'],
    'ae_field_display_final_20261101_validation': ['tb_ae_live_status', 'tb_ae_live_status_rd2'],
    'ae_field_chain_20261101_validation': ['tb_ae_meter', 'tb_ae_chain', 'tb_ae_chain_dark',
        'tb_ae_chain_midlight', 'tb_ae_chain_extreme', 'tb_ae_chain_motor',
        'tb_ae_chain_nack', 'tb_ae_chain_boot_nack'],
    'ae_field_csi_final_20261101_validation': ['tb_ae_csi_system'],
    'ae_field_video_20261101_validation': ['tb_isp_video_modes', 'tb_video_tail_isp', 'tb_video_tail_isp_sobel'],
    'ae_field_colour_20261101_validation': ['tb_awb_auto_reference', 'tb_auto_wb_isp'],
    'ae_field_parts_20261101_validation': ['tb_box_tracking', 'tb_recognition_latency',
        'tb_parts_multi_backlit', 'tb_parts_multi_backlit_latency'],
}

def source_list(path: Path) -> list[str]:
    block = re.search(r'<Source_Files>.*?</Source_Files>', read(path), re.S)[0]
    paths = [(path.parent / x).resolve() for x in re.findall(r'<File Path="([^"]+)"', block)]
    if path.suffix == '.prj':
        sdc = re.search(r'^set SDCList \{"([^"]+)"\}', read(path.parent / 'settings.cfg'), re.M)
        assert sdc, 'No executed SDCList'
        actual = (path.parent / sdc[1]).resolve()
        assert actual.is_file(), actual
        paths = [actual if p.suffix == '.sdc' and p.name == actual.name else p for p in paths]
    return sorted(str(p).lower() for p in paths)

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-record', type=Path, required=True)
    parser.add_argument('--release', action='store_true')
    parser.add_argument('--check-default', action='store_true',
        help='Require the active syn_1/phy_1 runs to match this verified build')
    args = parser.parse_args()
    record = json.loads(read(args.build_record))
    assert Path(record['project']).resolve() == ROOT / 'td_project/camera_to_dsi_display.al'
    result = {'created': datetime.now().astimezone().isoformat(), 'project': str(ROOT),
        'deliverable': 'boot AUTO, release-armed manual keys, native CSI markers, visible AE2 diagnostics, converge then lock',
        'passes': [], 'pendingTests': [], 'issues': [],
        'knownLimitations': ['No board download or new physical camera/light validation.',
            'Sensor optical response and vendor RAMs are simulation models.',
            'Legacy ambient-shadow recognition failure remains; no recognition/motion/AWB change.',
            'Existing warnings, SDC exceptions and incomplete STA coverage remain; I2C ACK is not register readback.']}
    for folder, tops in SUITES.items():
        for top in tops:
            path = ROOT / 'sim' / folder / f'{top}.log'
            s = read(path) if path.exists() else ''
            passed = re.findall(r'^.*(?:ALL PASS|TB_PASS screen_menu_control|PASS: simultaneous counting).*$', s, re.M)
            if re.search(r'Fatal:|Error:|TB_FAIL|\bFAIL\b', s):
                result['issues'].append(f'Simulation failed: {top}')
            elif not passed or 'Exiting xsim' not in s:
                result['pendingTests'].append(top)
            else:
                result['passes'].append({'top': top, 'log': str(path.relative_to(ROOT)),
                    'hash': digest(path), 'result': passed[-1].strip()})
    result['passedCount'] = len(result['passes'])
    result['requiredCount'] = sum(map(len, SUITES.values()))
    csi_log = ROOT / 'sim/ae_field_csi_final_20261101_validation/tb_ae_csi_system.log'
    if any(item['top'] == 'tb_ae_csi_system' for item in result['passes']):
        frames = [dict(zip(['frame', 'valid', 'luma', 'camDone', 'aeDone', 'exposure', 'gain', 'locked'],
                    map(int, match))) for match in re.findall(
            r'CSI AE frame=(\d+) valid=(\d) luma=(\d+) cfg=(\d)/(\d) exp=(\d+) gain=(\d+) locked=(\d)', read(csi_log))]
        locks = [frame for frame in frames if frame['locked']]
        if (not locks or len(locks) < 13 or not 176 <= locks[0]['luma'] <= 216 or locks[-1]['luma'] >= 176
                or any(frame['exposure'] != locks[0]['exposure'] or frame['gain'] != locks[0]['gain'] for frame in locks)
                or [frame['frame'] for frame in frames] != list(range(1, len(frames) + 1))):
            result['issues'].append('CSI convergence or twelve-frame locked hold evidence is incomplete')
        else:
            result['csiClosedLoop'] = {'totalFrames': len(frames), 'firstLockFrame': locks[0]['frame'],
                'lockLuma': locks[0]['luma'], 'lockedExposure': locks[0]['exposure'],
                'lockedGain': locks[0]['gain'], 'holdFramesAfterLock': len(locks) - 1,
                'finalLockedLumaAfterLightChange': locks[-1]['luma'],
                'lightChangeAfterLock': '1/8 scene illumination', 'controlModel': 'ACK-decoded I2C registers, N+2 image delay',
                'nativeAndCorrectedBeatsPerFrame': 230400}
    result['negativeControls'] = []
    negatives = [
        ('ae_field_markers_negative_final_20261101_validation/tb_image_correction_markers.log', 'correction drops/retags RAW'),
        ('ae_field_csi_negative_20261101_validation/tb_ae_csi_system.log', 'CSI/correction frame truncated native=230400 corrected=57600'),
        ('ae_field_boot_negative_20261101_validation/tb_ae_boot_keys_legacy.log', 'startup key level forced MAN/manual values auto=0'),
    ]
    for rel, expected in negatives:
        path = ROOT / 'sim' / rel
        ok = path.exists() and expected in read(path) and 'Fatal:' in read(path)
        result['negativeControls'].append({'log': str(path.relative_to(ROOT)), 'verified': ok,
            'hash': digest(path) if path.exists() else None})
        if not ok:
            result['issues'].append(f'Expected functional negative control missing: {rel}')
    prior = {i['Path']: i['Hash'] for i in json.loads(read(EVIDENCE / 'prior_inputs.json'))}
    changes = [str(Path(i['Path']).relative_to(ROOT)) for i in record['inputHashes'] if prior[i['Path']] != i['Hash']]
    allowed = {str(Path('user_source/hdl_source') / x) for x in
        ['design_top_wrapper.v', 'image_correction.v', 'uiisp_beta/ae_set.v', 'hdmi_mixer.v']}
    if set(changes) != allowed:
        result['issues'].append('Unexpected production scope versus the 20:52 build')
    changed = [i['Path'] for i in record['inputHashes'] if digest(Path(i['Path'])) != i['Hash'].upper()]
    if changed:
        result['issues'].append('Inputs changed since TD began')
    original = read(EVIDENCE / 'before/design_top_wrapper.v')
    top = read(ROOT / 'user_source/hdl_source/design_top_wrapper.v')
    for name in ['l298n_motor_control', 'conveyor_batch_counter']:
        pattern = r'\bmodule\s+' + name + r'\b.*?\bendmodule\b'
        if re.search(pattern, original, re.S)[0] != re.search(pattern, top, re.S)[0]:
            result['issues'].append(f'Protected control logic changed: {name}')
    current = source_list(ROOT / 'td_project/camera_to_dsi_display.al')
    match = all(source_list(Path(record[k]) / 'camera_to_dsi_display.prj') == current for k in ['synthesis', 'implementation'])
    result['build'] = {'record': str(args.build_record.resolve()), 'status': record['status'],
        'inputCount': len(record['inputHashes']), 'changedInputs': changed,
        'productionChangesFromPriorBit': changes, 'sourceListsMatch': match}
    if not match:
        result['issues'].append('Run input list differs from the requested project')
    correction = read(ROOT / 'user_source/hdl_source/image_correction.v')
    ae = read(ROOT / 'user_source/hdl_source/uiisp_beta/ae_set.v')
    mixer = read(ROOT / 'user_source/hdl_source/hdmi_mixer.v')
    checks = {
        'bootAuto': 'O_ae_auto<=1' in top,
        'releaseArmedManualKeys': 'O_camera_keys_armed && !O_menu_open' in top and '!S_camera_keys_armed' in top,
        'realCorrectionMarkers': 'sof_d <= I_raw_valid && I_raw_frame_start' in correction and
            'eol_d <= I_raw_valid && I_raw_frame_end' in correction and 'cnt ==' not in correction,
        'convergenceBandAndCount': 'AE_LOW=176,AE_HIGH=216,AE_CONFIRM_FRAMES=4' in ae and 'AE_LOCK_FRAMES=8' in ae,
        'visibleVersionAndMeter': '.AE_DIAGNOSTICS ( 1 )' in top and '0:c_char="A";1:c_char="E";2:c_char="2"' in mixer,
    }
    result['chainChecks'] = checks
    result['issues'] += [f'Static chain check failed: {k}' for k, v in checks.items() if not v]
    if record['status'] == 'complete':
        phy = Path(record['implementation'])
        timing = read(phy / 'final_timing.rpt')
        route = read(phy / 'route_flow.status')
        area = read(phy / 'camera_to_dsi_display_phy.area')
        physical = {'setupWnsNs': record['setupWnsNs'], 'holdWnsNs': record['holdWnsNs'],
            'staCoveragePct': float(re.search(r'STA coverage\s*:\s*([\d.]+)%', timing)[1])}
        constraint = re.search(r'^Constraint File\s*:\s*(.*?);\s*$', timing, re.M)
        if not constraint or Path(constraint[1]).resolve() != ROOT / 'td_project/camera_to_dsi_display.sdc':
            result['issues'].append('Unexpected executed SDC')
        for label in ['Setup', 'Hold']:
            m = re.search(label + r'\s*:\s*WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)', route)
            if not m or int(m[1]) < 0 or int(m[2]) != 0 or int(m[3]) != 0:
                result['issues'].append(f'Final {label} timing failed')
        for name in ['slice', 'lut6', 'eram', 'dsp']:
            m = re.search(r'^#' + name + r'\s+(\d+)\s+out of\s+(\d+)', area, re.M)
            physical[name] = {'used': int(m[1]), 'available': int(m[2])}
            if int(m[1]) > int(m[2]):
                result['issues'].append(f'Resource overflow: {name}')
        log = read(max(phy.glob('td_*.log'), key=lambda p: p.stat().st_mtime))
        physical['routingDrcCompleted'] = bool(re.search(r'End.*Routing DRC', log))
        drc_match = re.search(r'Stage \d+ \| Routing DRC.*?End Stage \d+ \| Routing DRC', log, re.S)
        drc = drc_match[0] if drc_match else ''
        physical['routingChecks'] = {label: text in drc for label, text in [
            ('noMultiDrive', 'No multi-drive.'), ('noAbnormalTimingPath', 'No abnormal timing path.'),
            ('boundCheckPassed', 'Check Pass.')]}
        warning_codes = re.findall(r'^([A-Z]+-\d+)\s+((?:CRITICAL-)?WARNING):', log, re.M)
        physical['warningCounts'] = {f'{code} {level}': warning_codes.count((code, level))
            for code, level in sorted(set(warning_codes))}
        physical['implementationErrors'] = re.findall(r'^.*\b[A-Z]+-\d+\s+(?:ERROR|FATAL)\b.*$', log, re.M)
        if (not physical['routingDrcCompleted'] or not all(physical['routingChecks'].values())
                or physical['implementationErrors']):
            result['issues'].append('Routing DRC incomplete or implementation failed')
        result['physical'] = physical
        bit = Path(record['bit'])
        result.update(bit=str(bit), bitHash=digest(bit), bitBytes=bit.stat().st_size)
        if result['bitHash'] != record['bitHash']:
            result['issues'].append('Bit differs from TD record')
    elif record['status'] != 'running':
        result['issues'].append('Physical build failed or was cancelled')
    promotion_path = EVIDENCE / 'default_run_promotion.json'
    if args.check_default or promotion_path.exists():
        default_issues = []
        if not promotion_path.exists():
            default_issues.append('Default-run promotion record is missing')
        else:
            promotion = json.loads(read(promotion_path))
            runs = ROOT / 'td_project/camera_to_dsi_display_Runs'
            syn, phy = runs / 'syn_1', runs / 'phy_1'
            if (Path(promotion['buildRecord']).resolve() != args.build_record.resolve()
                    or promotion['bitHash'] != record.get('bitHash')):
                default_issues.append('Default promotion refers to a different build')
            for key, default in [('synthesis', syn), ('implementation', phy)]:
                if not default.is_dir() or source_list(default / 'camera_to_dsi_display.prj') != current:
                    default_issues.append(f'Default {key} source list differs')
            checks = [(syn, Path(record['synthesis']), 'camera_to_dsi_display_gate.db')]
            checks += [(phy, Path(record['implementation']), name) for name in [
                'camera_to_dsi_display.bit', 'final_timing.rpt', 'camera_to_dsi_display_phy.ts',
                'camera_to_dsi_display_phy.area', 'camera_to_dsi_display_exception.timing', 'route_flow.status']]
            for default, original, name in checks:
                if not (default / name).is_file() or digest(default / name) != digest(original / name):
                    default_issues.append(f'Default artifact mismatch: {name}')
            if not re.search(r'^set parent ../syn_1\s*$', read(phy / 'settings.cfg'), re.M):
                default_issues.append('Default physical run does not use syn_1')
            project_text = read(ROOT / 'td_project/camera_to_dsi_display.al')
            for name in ['syn_1', 'phy_1']:
                if not re.search(r'<Run Name="' + name + r'"[^>]*Active="true"', project_text):
                    default_issues.append(f'Default run is not active: {name}')
            old_phy = Path(promotion['previousImplementationBackup'])
            old_syn = Path(promotion['previousSynthesisBackup'])
            if (old_phy.parent != runs or old_syn.parent != runs or not old_syn.is_dir()
                    or not (old_phy / 'camera_to_dsi_display.bit').is_file()
                    or digest(old_phy / 'camera_to_dsi_display.bit') != promotion['previousDefaultBitHash']):
                default_issues.append('Previous default runs were not preserved')
            archived = ROOT / 'release_archive/ae_field_boot_20261101/camera_to_dsi_display_ae_field_boot.bit'
            if not archived.is_file() or digest(archived) != record.get('bitHash'):
                default_issues.append('Archived bit differs from the promoted build')
            result['defaultRun'] = {'verified': not default_issues, 'bit': str(phy / 'camera_to_dsi_display.bit'),
                'bitHash': digest(phy / 'camera_to_dsi_display.bit'), 'promotionRecord': str(promotion_path),
                'previousImplementationBackup': str(old_phy), 'previousSynthesisBackup': str(old_syn)}
        result['issues'].extend(default_issues)
    result['status'] = 'failed' if result['issues'] else 'pending' if result['pendingTests'] or record['status'] != 'complete' else 'verified_no_board_test'
    output = EVIDENCE / 'verification.json'
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    if args.release:
        assert result['status'] == 'verified_no_board_test', result
        dest = ROOT / 'release_archive/ae_field_boot_20261101'
        dest.mkdir(parents=True, exist_ok=True)
        delivered = dest / 'camera_to_dsi_display_ae_field_boot.bit'
        assert not delivered.exists() or digest(delivered) == result['bitHash'], 'Different bit already archived'
        shutil.copy2(result['bit'], delivered)
        assert digest(delivered) == result['bitHash']
        result['deliveredBit'] = str(delivered)
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
        archive_sources = [output, args.build_record] + [Path(record['implementation']) / n for n in
            ['final_timing.rpt', 'camera_to_dsi_display_phy.ts', 'camera_to_dsi_display_phy.area',
             'camera_to_dsi_display_exception.timing', 'route_flow.status']]
        if promotion_path.exists():
            archive_sources.append(promotion_path)
        for path in archive_sources:
            shutil.copy2(path, dest / path.name)
        physical = result['physical']
        csi = result['csiClosedLoop']
        default = result.get('defaultRun')
        default_status = ('已核验默认syn_1/phy_1、原始run和本归档bit一致。' if default and default['verified']
            else '默认syn_1/phy_1尚未完成同步，暂不按默认路径交付。')
        notes = f'''# 现场MAN反馈后的AE2固件

工程：`{ROOT}`，入口：`td_project/camera_to_dsi_display.al`。

## 本次文件

- 固件：`{delivered.name}`，{result['bitBytes']}字节。
- SHA256：`{result['bitHash']}`。
- TD完成时间：{record['finished']}。
- {default_status}
- 默认下载文件：`td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`。
- 旧默认run保留在`verification.json`中记录的备份目录。

## 上板检查

1. 烧录本目录bit或已核验的默认bit，上电不按相机键，应显示`AE2:AUTO`。
2. `I:11`表示初始化/参数配置完成，`V1`表示测光有效；两者不是传感器寄存器读回。
3. 初始亮度超出176～216时，`W`应随运行时I2C序列完成增长，EXP或GAIN自动改变。
4. 连续8个完整有效测光包达标后显示`AE2:LOCK`及绿色`S:8/8`，此后自动写入停止。
5. 如需重新适应光照，在菜单中显式MAN→AUTO或复位；直接手动编辑会转MAN。
6. `Y`为十六进制亮度，目标区间为`B0～D8`；无`AE2`标识时先核对所选固件及烧录流程。

## 已完成验证

- {result['passedCount']}/{result['requiredCount']}项定向功能顶层通过，另有3个旧源码功能负对照按预期失败。
- 完整CSI→RAW10→流转换/校正→720p ISP→测光→AE→实际I2C解码→N+2合成光照闭环。
- 共{csi['totalFrames']}帧，第{csi['firstLockFrame']}帧锁定，锁定测光{csi['lockLuma']}；
  锁后再降低合成光照并检查{csi['holdFramesAfterLock']}帧，最终测光{csi['finalLockedLumaAfterLightChange']}，EXP/GAIN及写入请求保持。
- 每帧原始/校正均230400拍；启动按键持低、两种OSD读延迟、AWB、Sobel/EDGE与DDR连续性、多目标及计数回归通过。
- 原SDC下最终Setup WNS {physical['setupWnsNs']:+.3f}ns、Hold WNS {physical['holdWnsNs']:+.3f}ns，TNS/违例端点均0；Routing DRC完成。
- Slice {physical['slice']['used']}/{physical['slice']['available']}，LUT6 {physical['lut6']['used']}/{physical['lut6']['available']}，
  ERAM {physical['eram']['used']}/{physical['eram']['available']}，DSP {physical['dsp']['used']}/{physical['dsp']['available']}。
- STA覆盖率{physical['staCoveragePct']}%，既有约束例外及工具告警保留，62项生产输入与构建时哈希一致。

尚未下载到板子，未宣称真实光照、相机颜色或最高带速已经通过；光学响应和厂商RAM为仿真模型。
AWB、识别、帧差/速度预测、电机及计数算法本轮未修改；未提交或推送Git。
'''
        (dest / 'README.md').write_text(notes, encoding='utf-8')
        (dest / 'SHA256SUMS.txt').write_text(f"{result['bitHash']}  {delivered.name}\n", encoding='ascii')
    print(json.dumps({k: result.get(k) for k in ['status', 'passedCount', 'requiredCount', 'pendingTests',
        'issues', 'build', 'physical', 'defaultRun', 'bitHash', 'deliveredBit']}, ensure_ascii=False, indent=2))
    if result['issues']:
        raise SystemExit(1)

if __name__ == '__main__':
    main()
