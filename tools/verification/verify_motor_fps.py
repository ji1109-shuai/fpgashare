"""Evidence gate for automatic reject recovery, PWM and complete-frame FPS."""
import argparse
import difflib
import json
import re
import shutil
from collections import Counter
from datetime import datetime
from pathlib import Path
from verify_visual import digest, read, save, source_list

ROOT=Path(__file__).resolve().parents[2]
EVIDENCE=ROOT/'sim/motor_resume_20261102_validation'
RELEASE=ROOT/'release_archive/motor_fps_20261102'
SUITES={
 'motor_fps_display_20261102_validation':['tb_fps_display'],
 'motor_fps_core_r5_20261102_validation':['tb_frame_rate','tb_motor_resume','tb_industrial_counter','tb_industrial_menu','tb_industrial_tracker','tb_ae_target','tb_ae_boot_keys','tb_industrial_ui','tb_industrial_ui_rd2'],
 'motor_fps_opt_debug_20261102_validation':['tb_motor_resume','tb_industrial_tracker'],
 'motor_fps_video_20261102_validation':['tb_video_mode_osd','tb_target_overlay','tb_parts_overlay','tb_video_tail_isp_enhance','tb_video_tail_isp_compare'],
}
ROMS=['industrial_font16.hex','logo_idx.hex','logo_pal.hex']

def main():
 ap=argparse.ArgumentParser()
 ap.add_argument('--build-record',required=True,type=Path)
 ap.add_argument('--release',action='store_true')
 ap.add_argument('--check-default',action='store_true')
 args=ap.parse_args();r=json.loads(read(args.build_record));issues=[];pending=[];passes=[]
 def check(ok,msg):
  if not ok: issues.append(msg)
 out={'created':datetime.now().astimezone().isoformat(),'project':str(ROOT),'boardProgrammed':False,'issues':issues,'pending':pending,'passes':passes,
  'motor':{'pwmHz':10000,'levelsPercent':[0,65,80,100],'autoResumeAfterFreshClearPublications':3,'manualStopCancelsResume':True,'doneKeepsStopped':True,'ambiguousFaultRequiresAck':True},
  'fps':{'source':'Complete packed ISP frame before video_in','wordsPerFrame':172800,'referenceClockHz':50000000,'windowSeconds':1,'hdmiRefreshNotMeasured':True,'stoppedCameraReportsZero':True},
  'limitations':['No board test; PWM duty is not measured conveyor speed.','Faster conveyor recognition accuracy requires board validation.','Existing warnings, SDC exceptions and incomplete STA coverage remain.']}
 baseline=json.loads(read(EVIDENCE/'before_manifest.json'))
 changed=[i['path'] for i in baseline if digest(ROOT/i['path'])!=i['sha256'].upper()]
 check(set(changed)=={'user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/hdmi_mixer.v'},'Unexpected production changes')
 out['productionChanges']=changed;out['baselineInputCount']=len(baseline)
 guard=json.loads(read(EVIDENCE/'root_guard.json'))
 out['protectedRootChanges']=[i['path'] for i in guard if digest(i['path'])!=i['sha256'].upper()]
 check(not out['protectedRootChanges'],'Protected root changed')
 snapshot=json.loads(read(EVIDENCE/'test_inputs.json'))
 check(all(digest(ROOT/i['path'])==i['sha256'].upper() for i in snapshot),'Test input snapshot changed')
 for folder,tops in SUITES.items():
  for top in tops:
   p=ROOT/'sim'/folder/(top+'.log');s=read(p) if p.exists() else '';summaries=re.findall(r'^.*ALL PASS.*$',s,re.M)
   if re.search(r'Fatal:|Error:|\bFAIL\b',s): issues.append('Failed simulation '+folder+'/'+top)
   elif not summaries or 'Exiting xsim' not in s: pending.append(top)
   else: passes.append({'top':top,'log':str(p.relative_to(ROOT)),'sha256':digest(p),'result':summaries[-1]})
 for item in passes:
  if item['top'] in ['tb_industrial_ui','tb_industrial_ui_rd2']:
   check('47188 HUD glyph pixels' in item['result'] and '605612 transparent pixels' in item['result'],'FPS HUD raster coverage missing')
 negative=ROOT/'sim/motor_fps_negative_20261102_validation/tb_motor_resume.log'
 check('actual PWM high clocks 50 expected 65' in read(negative),'Old motor negative control did not fail as expected')
 out['negativeControl']={'log':str(negative.relative_to(ROOT)),'sha256':digest(negative),'status':'expected_failure'}
 recovery_negative=ROOT/'sim/motor_fps_recovery_negative_20261102_validation/tb_industrial_counter.log'
 check('counts=000000000002 expected=000000000001' in read(recovery_negative),'Old ACK-only recovery was not rejected')
 out['recoveryNegativeControl']={'log':str(recovery_negative.relative_to(ROOT)),'sha256':digest(recovery_negative),'status':'expected_failure'}
 out['simulationDiagnosticHistory']={'failedLogs':['sim/motor_resume_core_r2_20261102_validation/tb_motor_resume.log','sim/motor_resume_core_r3_20261102_validation/tb_industrial_tracker.log'],
  'observation':'No-debug optimized XSim changed outcome with diagnostic visibility; no production change was made to hide the failures.',
  'finalConfigurations':['--O0 --debug typical','--debug typical with optimization enabled'],
  'rootCause':'Simulator visibility/optimization sensitivity observed; exact compiler cause not established.'}
 prior=json.loads(read(ROOT/'sim/visual_upgrade_20261102_validation/verification.json'))
 oldinputs=json.loads(read(ROOT/'sim/visual_upgrade_20261102_validation/test_inputs.json'))
 production_prior=[i['path'] for i in oldinputs if i['path'].startswith('user_source/') and digest(ROOT/i['path'])!=i['sha256'].upper()]
 check(set(production_prior)==set(changed),'Changed production logic invalidates prior ISP/AE evidence')
 # Only reuse tests for unchanged ISP, tone and AE modules, never old motor,
 # menu, counter, tracker or mixer tests. Current tests cover those separately.
 reuse_names={'tb_industrial_tone','tb_industrial_enhance','tb_industrial_photo','tb_ae_meter','tb_ae_chain','tb_ae_chain_dark','tb_ae_chain_midlight','tb_ae_chain_extreme','tb_ae_chain_gain_low','tb_ae_chain_gain_high','tb_ae_chain_nack','tb_ae_chain_boot_nack','tb_ae_chain_target_low','tb_ae_chain_target_high','tb_ae_chain_retarget','tb_ae_csi_enhance'}
 reused=[i for i in prior['passes'] if i['top'] in reuse_names]
 check(len(reused)==len(reuse_names) and all(digest(ROOT/i['log'])==i['sha256'].upper() for i in reused),'Prior unchanged logic evidence mismatch')
 out['reusedEvidence']={'record':'sim/visual_upgrade_20261102_validation/verification.json','sha256':digest(ROOT/'sim/visual_upgrade_20261102_validation/verification.json'),'scope':'Unchanged AE/CSI/ISP/enhancement modules only; full CSI was not rerun this release.','passes':reused}
 check(Path(r['project']).resolve()==ROOT/'td_project/camera_to_dsi_display.al','Wrong project')
 check(all(digest(i['Path'])==i['Hash'].upper() for i in r['inputHashes']),'Build input changed')
 syn,phy=Path(r['synthesis']),Path(r['implementation'])
 check(all(source_list(d/'camera_to_dsi_display.prj')==source_list(r['project']) for d in [syn,phy]),'Executed source list differs')
 check(all(digest(d/n)==digest(ROOT/'user_source/hdl_source'/n) for d in [syn,phy] for n in ROMS),'ROM copies differ')
 out['build']={'record':str(args.build_record.resolve()),'status':r['status'],'inputCount':len(r['inputHashes']),'physicalSettingsHash':digest(phy/'settings.cfg')}
 for name in ['design_top_wrapper.v','hdmi_mixer.v']:
  before=read(EVIDENCE/'before'/name);after=read(ROOT/'user_source/hdl_source'/name)
  (EVIDENCE/(name+'.patch')).write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='before/'+name,tofile='after/'+name)),encoding='utf-8')
 if r['status']!='complete': pending.append('Final TD build and timing')
 else:
  route=read(phy/'route_flow.status');timing=read(phy/'final_timing.rpt');area=read(phy/'camera_to_dsi_display_phy.area')
  physical={'setupWnsNs':r['setupWnsNs'],'holdWnsNs':r['holdWnsNs'],'staCoveragePct':float(re.search(r'STA coverage\s*:\s*([\d.]+)%',timing)[1])}
  for label in ['Setup','Hold']:
   m=re.search(label+r'\s*:\s*WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)',route)
   check(bool(m and int(m[1])>=0 and int(m[2])==0 and int(m[3])==0),'Final '+label+' timing failed')
  constraint=re.search(r'^Constraint File\s*:\s*(.*?);\s*$',timing,re.M)
  check(bool(constraint and Path(constraint[1]).resolve()==ROOT/'td_project/camera_to_dsi_display.sdc'),'Wrong executed SDC')
  for name in ['slice','lut6','eram','dsp']:
   m=re.search(r'^#'+name+r'\s+(\d+)\s+out of\s+(\d+)',area,re.M)
   physical[name]={'used':int(m[1]),'available':int(m[2])};check(int(m[1])<=int(m[2]),'Resource overflow '+name)
  logs=[read(max(d.glob('td_*.log'),key=lambda p:p.stat().st_mtime)) for d in [syn,phy]]
  errors=re.findall(r'^.*\b[A-Z]+-\d+\s+(?:ERROR|FATAL)\b.*$','\n'.join(logs),re.M)
  drc=re.search(r'Stage \d+ \| Routing DRC.*?End Stage \d+ \| Routing DRC',logs[1],re.S)
  physical['errors']=errors;physical['routingDrcCompleted']=bool(drc)
  check(not errors and bool(drc and all(t in drc[0] for t in ['No multi-drive.','No abnormal timing path.','Check Pass.'])),'Physical errors or DRC failure')
  physical['warningCounts']=dict(Counter(re.findall(r'^([A-Z]+-\d+\s+(?:CRITICAL-)?WARNING):','\n'.join(logs),re.M)))
  previous=json.loads(read(ROOT/'sim/ui_overlay_20261102_validation/verification.json'))
  previous_record=json.loads(read(previous['build']['record']))
  oldlogs=[read(max(Path(previous_record[k]).glob('td_*.log'),key=lambda p:p.stat().st_mtime)) for k in ['synthesis','implementation']]
  critical=lambda ss: sorted(set(re.findall(r'^.*\b[A-Z]+-\d+ CRITICAL-WARNING:.*$','\n'.join(ss),re.M)))
  newcritical=sorted(set(critical(logs))-set(critical(oldlogs)))
  reviews=json.loads(read(EVIDENCE/'warning_reviews.json')) if (EVIDENCE/'warning_reviews.json').exists() else []
  check(all(i.get('reason') and i['before'] in critical(oldlogs) and i['after'] in newcritical for i in reviews),'Invalid warning review')
  unresolved=[s for s in newcritical if s not in {i['after'] for i in reviews}]
  check(not unresolved,'New critical warnings require review')
  comparison={'previousCriticalWarnings':critical(oldlogs),'currentCriticalWarnings':critical(logs),'rawNewCriticalWarnings':newcritical,'reviewedChanges':reviews,'unresolved':unresolved}
  save(EVIDENCE/'critical_warning_comparison.json',comparison);out['criticalWarningComparison']=comparison;out['physical']=physical
  warning_review=json.loads(read(EVIDENCE/'all_warning_comparison.json'))
  check(set(warning_review['newWarningLines'])=={i['warning'] for i in warning_review['reviews']} and all(i['reason'] for i in warning_review['reviews']),'Unreviewed warning differences')
  check(all(digest(EVIDENCE/i['path'])==i['sha256'] for i in warning_review['clockAnalysisLogs']),'Clock analysis evidence changed')
  out['allWarningComparison']=warning_review
  out['bit']=r['bit'];out['bitHash']=digest(r['bit']);check(out['bitHash']==r['bitHash'],'Bit hash differs from record')
 if args.check_default:
  ds=ROOT/'td_project/camera_to_dsi_display_Runs/syn_1';dp=ds.parent/'phy_1'
  same=digest(dp/'camera_to_dsi_display.bit')==r.get('bitHash')
  for src,dst,names in [(syn,ds,['camera_to_dsi_display_gate.db']),(phy,dp,['final_timing.rpt','camera_to_dsi_display_phy.ts','camera_to_dsi_display_phy.area','route_flow.status'])]:
   same=same and all(digest(src/n)==digest(dst/n) for n in names)
  same=same and 'set parent ../syn_1' in read(dp/'settings.cfg')
  same=same and all(source_list(d/'camera_to_dsi_display.prj')==source_list(r['project']) for d in [ds,dp])
  same=same and all(digest(d/n)==digest(ROOT/'user_source/hdl_source'/n) for d in [ds,dp] for n in ROMS)
  check(same,'Default run mismatch');out['defaultRun']={'verified':bool(same),'bit':str(dp/'camera_to_dsi_display.bit')}
 out['passedCount']=len(passes);out['requiredCount']=sum(map(len,SUITES.values()))
 out['status']='verified_no_board_test' if not issues and not pending else 'incomplete'
 save(EVIDENCE/'verification.json',out)
 print(json.dumps({k:out[k] for k in ['status','passedCount','requiredCount','issues','pending']},ensure_ascii=False,indent=2))
 if args.release:
  if out['status']!='verified_no_board_test': raise SystemExit('Release blocked by evidence')
  RELEASE.mkdir(parents=True,exist_ok=True);shutil.copy2(r['bit'],RELEASE/'camera_to_dsi_display_motor_fps.bit')
  shutil.copy2(args.build_record,RELEASE/'build_record.json')
  for p in EVIDENCE.iterdir():
   if p.is_file() and p.suffix in ['.json','.patch','.png']: shutil.copy2(p,RELEASE/p.name)
  for n in ['final_timing.rpt','camera_to_dsi_display_phy.ts','camera_to_dsi_display_phy.area','route_flow.status','camera_to_dsi_display_exception.timing']:
   if (phy/n).exists(): shutil.copy2(phy/n,RELEASE/n)
  for i in r['inputHashes']:
   p=Path(i['Path']);dst=RELEASE/'sources'/p.relative_to(ROOT);dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dst)
  for i in passes:
   dst=RELEASE/'test_logs'/Path(i['log']).parent.name/Path(i['log']).name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/i['log'],dst)
  doc=ROOT/'docs/MOTOR_FPS_20261102.md'
  if doc.exists(): shutil.copy2(doc,RELEASE/doc.name)
 if out['status']!='verified_no_board_test': raise SystemExit(1)

if __name__=='__main__': main()
