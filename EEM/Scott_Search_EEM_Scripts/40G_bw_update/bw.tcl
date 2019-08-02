::cisco::eem::event_register_syslog pattern "%L2-BM-6-ACTIVE : FortyGigE" maxrun_sec 240
 
# bw.tcl -- Fault Manager script for automatically triggering 40GE RSVP reservations
#
#ident "bw.tl 1.4"
#
# Trigger tunnel shut/noshut as a result of FortyGigE member link down/up
#
# %L2-BM-6-ACTIVE : FortyGigE0/3/0/1 is Active as part of Bundle-Ether226
# %L2-BM-6-ACTIVE : FortyGigE0/3/0/1 is no longer Active as part of Bundle-Ether226 (Link is down)
#
# 03/06/2013 - v1.0 - acg - initial release
# 11/27/2013 - v1.1 - acg - update with comments from Shafqat
#       - change log file name to daily from current time
# 12/17/2013 - v1.2 - acg - update log file directory location
#       - change log file location to harddisk:eem/bw
# 02/07/2014 - v1.3 - acg - update reservation calculation
#       - set resv [expr int($bw / 8.79)]
# 02/09/2014 - v1.4 - acg - update reservation calculation
#       - set resv [expr $resv + 4550000]
 
global term_rows
 
#
# proc xmit{} - procedure to execute a CLI command
#
proc xmit {cmd} {
        global errorInfo
        global term_rows
        upvar cli cli
 
        if [catch {cli_exec $cli(fd) "$cmd"} result] {
                error $result $errorInfo
        } else {
                set term_rows $result
        }
}
 
#
# proc screenSave{} - procedure to take input an write (append) to a well known file
#
proc screenSave {theScreen} {
        global errorInfo
        upvar file_name file_name
 
        if [catch {set theFile [open "${file_name}" a] } ] {
                error "Cannot open file: ${file_name}" $errorInfo
                # send_error "Reason: $theFile"
                exit 1
        }
        puts $theFile "$theScreen"
        close $theFile
}
 
# errorInfo gets set by namespace if any of the auto_path directories
# do not contain a valid tclIndex file.  It is not an error just left
# over stuff.  So we set the errorInfo value to null so that we don't
# have left over errors in it.
set errorInfo ""
set term_rows ""
 
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
# set timestamp [clock format [clock seconds] -format "%Y%m%d-%H%M%S"]
set timestamp [clock format [clock seconds] -format "%b%d-%Y"]
 
# extract key data time from ios_msg
array set arr_einfo [event_reqinfo]
# Extract the message that triggered the event
set full_msg $arr_einfo(msg)
 
# find {Active}/{no longer Active} in message
set msg [lindex [split $full_msg ":"] 3]
set int [lindex $msg 0]
set state [lindex $msg 2]
set bundle [lindex $msg [lsearch $msg "Bundle-Ether*"] ]
set bundle_num [lindex [split $bundle "r"] 1 ]
set file_name "harddisk:/eem/bw/$bundle.$timestamp"
 
# record ios_msg which triggered this event
screenSave "Trigger Message: $full_msg"
 
# set action varialble for later use in logging
if {$state == "Active"} {
        set action "Added"
} else {
        set action "Removed"
}
 
# open a CLI FD
if [catch {cli_open} result] {
        error $result $errorInfo
} else {
        array set cli $result
}
 
# run the CLI command to get the explicit path / tunnel-id mapping
xmit "sh explicit-paths"
screenSave $term_rows
 
# find the matching entry for the tunnel with membership change
foreach line [split $term_rows "\n"] {
        if {[regexp -- "^Path BL${bundle_num}.*_399" $line]} {
                set tunnel [lindex [split [lindex $line 1] "_"] 4]
                break
        }
}
 
# run the CLI commands to get the state of the bundle
 
action_syslog priority notice msg "%OS-SYSLOG-ATT-BW: $bundle - $int $action"
 
xmit "show bundle $bundle"
screenSave $term_rows
 
set bw 0
set resv 0
 
# for each member that is active, sum the total BW, then set resv total_BW/8.79
foreach line [split $term_rows "\n"] {
        if {[regexp -- {^  Fo.*Active} $line]} {
                set bw [expr $bw + 40000000]
                # set resv [expr int($bw / 8.79)]
                set resv [expr $resv + 4550000]
 
        }
}
 
# enter config mode and apply the BW to the appropriate tunnel
 
xmit "config t"
screenSave $term_rows
 
xmit "int tunnel-te $tunnel signalled-band $resv"
screenSave $term_rows
 
xmit "commit"
screenSave $term_rows
 
xmit "end"
screenSave $term_rows
 
# drain the FD to be sure we got everything from the command output
set drain_result [cli_read_drain $cli(fd)]
screenSave $drain_result
 
# close the CLI
after 1000
if [catch {cli_close $cli(fd) $cli(tty_id)} result] {
        error $result $errorInfo
}
 
# write to syslog with the file name of the log file
action_syslog priority notice msg "%OS-SYSLOG-ATT-BW: Output written to file $file_name"
