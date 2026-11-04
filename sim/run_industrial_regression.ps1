param([string]$VivadoRoot='D:/AMDDesignTools/2025.2/Vivado',
 [string]$BuildName='industrial_core_20261102_validation',
 [string]$DesignSource='',
 [string[]]$ElaborationFlags=@('--O0','--debug','typical'),
 [string[]]$Tops=@('tb_industrial_enhance','tb_industrial_counter'))
$ErrorActionPreference='Stop'
$v=$VivadoRoot
$env:PATH="$v/lib/win64.o;$v/bin/unwrapped/win64.o;$v/tps/win64/jre21.0.5_11/bin/server;$v/tps/win64/jre21.0.5_11/bin;$v/tps/win64;"+$env:PATH
$env:XILINX_VIVADO=$v;$env:RDI_DATADIR="$v/data";$env:RDI_APPROOT=$v;$env:HDI_APPROOT=$v
$env:RDI_OPT_EXT='.o';$env:TCL_LIBRARY="$v/tps/tcl/tcl8.6";$env:RDI_LIBDIR="$v/lib/win64.o";$env:RDI_BINDIR="$v/bin";$env:RDI_PLATFORM='win64'
$build=Join-Path $PSScriptRoot $BuildName
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
 $r='../../user_source/hdl_source'
 if(!$DesignSource){$DesignSource="$r/design_top_wrapper.v"}
 Copy-Item "$r/logo_idx.hex","$r/logo_pal.hex","$r/industrial_font16.hex" -Destination . -Force
 $tests=@('../tb_batch_buzzer.sv','../tb_fps_display.sv','../tb_frame_rate.sv','../tb_motor_resume.sv','../tb_industrial_tone.sv','../tb_industrial_photo.sv','../tb_industrial_enhance.sv','../tb_industrial_counter.sv','../tb_industrial_tracker.sv','../tb_industrial_ui.sv','../tb_industrial_menu.sv','../tb_ae_target.sv','../tb_ae_once.sv','../tb_ae_boot_keys.sv') | Where-Object {Test-Path -LiteralPath $_}
 & "$v/bin/unwrapped/win64.o/xvlog.exe" -sv "$r/img_video_modes.v" "$r/img_proj.v" $DesignSource "$r/hdmi_mixer.v" "$r/osd_char_lib.v" "$r/uiisp_beta/ae_set.v" $tests
 if($LASTEXITCODE -ne 0){throw 'Industrial compile failed'}
 foreach($top in $Tops){
  & "$v/bin/unwrapped/win64.o/xelab.exe" $top -s $top -timescale 1ns/1ps @ElaborationFlags
  if($LASTEXITCODE -ne 0){throw "Industrial elaboration failed: $top"}
  & "$v/bin/unwrapped/win64.o/xsim.exe" $top -runall -log "$top.log"
  $log=Get-Content "$top.log" -Raw
  if($LASTEXITCODE -ne 0 -or $log -notmatch 'ALL PASS' -or $log -match 'Fatal:|Error:|\bFAIL\b'){throw "Industrial simulation failed: $top"}
 }
}finally{Pop-Location}
