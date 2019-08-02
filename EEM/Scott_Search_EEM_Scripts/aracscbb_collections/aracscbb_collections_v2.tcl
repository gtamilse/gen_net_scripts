::cisco::eem::event_register_syslog pattern "Successfully authenticated.*aracscbb.*" maxrun 600

#------------------------------------------------------------------
# If user "aracscbb" logs into router we will collect a number of show commands
#
# July 2017 - Scott Search (ssearch@cisco.com)
#
# Copyright (c) 2017 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------
#
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
set run_flag "disk0:/eem/aracscbb_run_flag"

set cmds "
term len 0
show process blocked
term exec prompt timestamp
show exec trace last 250
show process blocked
show log last 250
show process blocked
show configuration commit list
show management xml trace last 250
show process blocked
show management xml client trace last 250
show management xml mda trace last 250
show process blocked
show management xml tty trace last 250
show process blocked
show mda trace last 250
show process blocked
show tty trace info all all last 250
show tty trace error all all last 250
show process blocked
"


##################################
# PROCs:
##################################
proc send_syslog {msg repeat} {
  set kont 0

  while {$kont < $repeat} {
    action_syslog msg $msg
    incr kont
  }
} ;# send_syslog


##################################
# MAIN/main
##################################
global FH

# Capture the scripts start time:
set time_now [clock seconds]

set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]

set filename "aracscbb_collections.$date_time"
set output_file "disk0:/eem/$filename"

# Open the output file (for write):
if [catch {open $output_file w} result] {
    error $result
}
set FH $result

# Timestamp the script start time to the output log file:
puts $FH "Start Timestamp: $date"

# Log the nodes hostname to the output log file:
set node [info hostname]
puts $FH "Node: $node"

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message the finally kicked off the EEM script:
set syslog_msg $arr_einfo(msg)


# If the $run_flag file exists exit from script:
#if [file exists $run_flag] {
#  set msg "EEM policy aracscbb_collections.tcl was triggered, however, the run_flag file: $run_flag exists"
#  action_syslog msg $msg
#
#  set msg "$msg\nDelete $run_flag in order to activate the EEM aracscbb_collections.tcl script."
#  set msg "$msg\n$syslog_msg"
#  puts $FH $msg
#  close $FH
#  exit
#}

# Create the run_flag file
#if [catch {open $run_flag w} result] {
#    error $result
#}
#set RUN $result
#puts $RUN "Timestamp = $date"
#close $RUN

# Open router connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}


# Running the list of commands:
foreach CMD [split $cmds "\n"] {
  if {$CMD == ""} { continue }
  if [catch {cli_exec $cli(fd) $CMD} result] {
    error $result $errorInfo
  }
  puts $FH "$result\n\n"
}

close $FH
