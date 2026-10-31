import_device eagle_s20.db -package EG4S20BG256
open_project tf_sdram_hdmi_media_extension_candidate.al -single_run
load_run_param -run syn_1
commit_param -step design
elaborate -top tf_sdram_hdmi_media_top
read_adc tf_sdram_hdmi_media_extension_candidate.adc
read_sdc tf_sdram_hdmi_media_extension_candidate.sdc
optimize_rtl
commit_param -step gate
optimize_gate -packarea media_gate.area
legalize_phy_inst
update_timing
report_timing_summary -file media_gate.timing
# TD documented multi-seed option: move away from a local PCM-queue route conflict.
set_param place seed 23
commit_param -step place
place
update_timing -mode manhattan
report_timing_summary -file media_place.timing
# Match TD doc/scripts/MultiSeed.tcl: defer hold repair until after routing.
commit_param -step route
set_param route fix_hold off
set_param flow qor_monitor off
route
fix_hold
set_param route fix_hold on
set_param flow qor_monitor on
update_timing -mode final
report_timing_status -file media_phy.ts
report_timing_summary -file media_pr.timing
report_timing_exception -file media_exception.timing
commit_param -step bitgen
bitgen -bit tf_sdram_hdmi_media_extension_candidate.bit
exit



