"""Create a separate verifier using the established physical/report checks."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[2]
folder=Path(__file__).parent
s=(folder/'verify_industrial.py').read_text(encoding='utf-8-sig')
prefix=s[:s.index('SUITES =')]
suites={
 'visual_core_final_20261102_validation':['tb_industrial_tone','tb_industrial_enhance','tb_industrial_counter','tb_industrial_tracker','tb_industrial_menu','tb_ae_target','tb_ae_once','tb_ae_once_single','tb_ae_boot_keys','tb_industrial_ui','tb_industrial_ui_rd2'],
 'visual_ae_final_20261102_validation':['tb_ae_meter','tb_ae_chain','tb_ae_chain_dark','tb_ae_chain_midlight','tb_ae_chain_extreme','tb_ae_chain_gain_low','tb_ae_chain_gain_high','tb_ae_chain_motor','tb_ae_chain_nack','tb_ae_chain_boot_nack','tb_ae_chain_target_low','tb_ae_chain_target_high','tb_ae_chain_retarget'],
 'visual_video_final_20261102_validation':['tb_video_modes','tb_video_modes_onebeat','tb_video_modes_720p','tb_isp_video_modes','tb_video_mode_osd','tb_target_overlay','tb_parts_overlay','tb_video_tail_isp','tb_video_tail_isp_sobel','tb_video_tail_isp_enhance','tb_video_tail_isp_compare'],
 'visual_csi_20261102_validation':['tb_ae_csi_enhance'],
 'visual_photo_20261102_validation':['tb_industrial_photo'],
}
common=s[s.index('def read('):s.index('    prior_path=')]
checks=s[s.index('    top=read('):s.index("    guard=EVIDENCE/")]
checks=checks.replace("item['top']=='tb_ae_csi_system'","item['top']=='tb_ae_csi_enhance'")
protection='''    baseline=json.loads(read(EVIDENCE/'before_manifest.json'))
    diff=[i['path'] for i in baseline if digest(ROOT/i['path'])!=i['sha256'].upper()]
    expected={'user_source/hdl_source/'+n for n in ['design_top_wrapper.v','hdmi_mixer.v','isp/isp_top.v','img_video_modes.v']}
    out['build']['baselineInputCount']=len(baseline)
    out['build']['productionChangesFromIndustrial']=diff
    if set(diff)!=expected: issues.append('Unexpected production or constraint changes')
    guard=json.loads(read(EVIDENCE/'root_guard.json'))
    changes=[i['path'] for i in guard if digest(i['path'])!=i['sha256'].upper()]
    out['otherProjectsProductionChanges']=changes
    if changes: issues.append('Protected root project changed')
    before=read(EVIDENCE/'before/design_top_wrapper.v')
    current=read(ROOT/'user_source/hdl_source/design_top_wrapper.v')
    controls=before.split('module screen_menu_control',1)[1]==current.split('module screen_menu_control',1)[1]
    stripped=chr(10).join(line for line in current.splitlines() if '.I_enhance_compare(' not in line)
    top_unchanged=''.join(before.split())==''.join(stripped.split())
    before_isp=read(EVIDENCE/'before/isp/isp_top.v')
    isp=read(ROOT/'user_source/hdl_source/isp/isp_top.v')
    sync_start=isp.index('reg [1:0] enhance_compare_sync;')
    sync_end=isp.index('reg [1:0] enhance_compare_sync;')+len('reg [1:0] enhance_compare_sync;')
    end_block=isp.index('end',sync_end)+3
    cleaned=isp[:sync_start]+isp[end_block:]
    cleaned=chr(10).join(line for line in cleaned.splitlines() if 'input I_enhance_compare,' not in line and '.I_enhance_compare(' not in line)
    isp_unchanged=''.join(before_isp.split())==''.join(cleaned.split())
    out['preservation']={'motorMenuCounterModulesExact':controls,'topOnlyCompareConnections':top_unchanged,'ispOnlyCompareControl':isp_unchanged}
    if not all(out['preservation'].values()): issues.append('Control or upstream ISP preservation mismatch')
    out['enhancement'].update({'tone':'piecewise weighted-luma S-curve','chromaGain':1.25,'compareSwitch':'SW1','compareLeft':'original','compareRight':'enhanced','defaultTonePoints':{'64':24,'128':128,'192':232},'addedEnhancementClocks':1})
    photo=EVIDENCE/'photo_metrics.json'
    if not photo.exists(): pending.append('RTL photo comparison')
    else:
        out['photo']=json.loads(read(photo))
        if out['photo']['rtlChecks']!=875520: issues.append('Incomplete photo pixel checks')
    out['previousReleaseEvidence']={'path':'sim/industrial_upgrade_20261102_validation/verification.json','reusedForUnchangedColourRecognitionOnly':True}
'''
csi=s[s.index("    csi=ROOT/"):s.index("    if r['status']=='complete':")]
csi=csi.replace('industrial_csi_r4_20261102_validation/tb_ae_csi_system.log','visual_csi_20261102_validation/tb_ae_csi_enhance.log')
tail=s[s.index("    if r['status']=='complete':"):]
result=prefix+'SUITES = '+repr(suites)+chr(10)+chr(10)+common+protection+checks+csi+tail
result=result.replace('sim/industrial_upgrade_20261102_validation','sim/visual_upgrade_20261102_validation').replace('release_archive/industrial_20261102','release_archive/visual_20261102').replace('camera_to_dsi_display_industrial.bit','camera_to_dsi_display_visual.bit')
result=result.replace("'path':'sim/visual_upgrade_20261102_validation/verification.json','reusedForUnchangedColourRecognitionOnly'","'path':'sim/industrial_upgrade_20261102_validation/verification.json','reusedForUnchangedColourRecognitionOnly'")
result=result.replace('Verify the actual industrial release','Verify the actual (4) whole-machine visual release')
(folder/'verify_visual.py').write_text(result,encoding='utf-8')
p=(ROOT/'tools/promote_industrial.ps1').read_text(encoding='utf-8-sig')
p=p.replace('industrial_upgrade_20261102_validation','visual_upgrade_20261102_validation').replace('industrial_20261102','visual_20261102').replace('camera_to_dsi_display_industrial.bit','camera_to_dsi_display_visual.bit').replace('^(syn|phy)_industrial_r[4-9]_','^(syn|phy)_visual_r[0-9]+_').replace('before_industrial_','before_visual_').replace('partial_industrial_','partial_visual_')
(ROOT/'tools/promote_visual.ps1').write_text(p,encoding='utf-8')
inputs=[]
for parent in [ROOT/'user_source',ROOT/'sim']:
    paths=parent.rglob('*') if parent.name=='user_source' else parent.glob('*')
    for path in paths:
        if path.is_file() and path.suffix.lower() in ['.v','.sv','.vh','.hex','.ps1']:
            inputs.append({'path':path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest().upper()})
(ROOT/'sim/visual_upgrade_20261102_validation/test_inputs.json').write_text(json.dumps(inputs,indent=2),encoding='utf-8')
print('Created separate visual verifier/promotion tools; test input count',len(inputs))
