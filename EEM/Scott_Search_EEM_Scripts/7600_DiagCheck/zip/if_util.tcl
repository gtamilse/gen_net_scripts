proc get_envvar { name } {
    set output [string trim [cli "show event manager environment $name"]]
    if { $output != "" && $output != "Environment variable not found" } {
        set val [string trim [lindex [split $output ":"] 1]]
        
        return $val
    }
    
    return ""
}

set val [get_envvar "if_util_intfs"]
if { $val != "" } {
    set iflst [split $val ","]
    set threshold [get_envvar "if_util_threshold"]
    if { $threshold == "" } {
        exit 1
    }
    foreach if $iflst {
        set if [string trim $if]
        set output [cli "show interface $if | inc load"]
        if { ! [regexp {txload (\d+).*rxload (\d+)} $output -> txload rxload] } {
            continue
        }
        
        set txutil [expr int(${txload}.0 / 255.0 * 100.0)]
        set rxutil [expr int(${rxload}.0 / 255.0 * 100.0)]
        set msg "Interface $if exceeded ${threshold}% utilization threshold: Tx: ${txutil}%, Rx: ${rxutil}%"
        if { $txutil > $threshold || $rxutil > $threshold } {
            #regsub -all {[/\.]} $if "" safe_if
            #cli "config t ; event manager applet ifutil$safe_if ; event counter name ${safe_if}CNT entry-val 0 entry-op gt exit-val 0 exit-op gt ; action 1.0 syslog msg $msg"
            #cli "end"
            #cli "event manager run ifutil$safe_if"
            #cli "config t ; no event manager applet ifutil$safe_if ; end"
            cli "logit $msg"
        }
    }
}