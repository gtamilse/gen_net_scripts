::cisco::eem::event_register_syslog pattern "L2-SPA-3-PLIM_HEARTBEAT_ERR" maxrun 600

# ::cisco::eem::event_register_syslog pattern "Clear counters on all interfaces" maxrun 600

#------------------------------------------------------------------
# PLIM_heartbeat_collection EEM Script
#
# September 2014 - Scott Search (ssearch@cisco.com)
#
# EEM script/policy to detect the syslog pattern above in the event a xr12k node experiences 
# an engine 5 SPA PLIM ERROR.  This script will capture a number of commands for later analysis.
#
# EEM Script is dependent on the following event manager environment variable(s):
#   _PLIM_heartbeat_collection_storage_location <storage>  -Disk/hardisk storage location "disk0:/eem"
#
# Email Option
# To activate the email option the following event manager environment variables must be set:
#   _email_server    _email_from
#   _email_to        _domainname
#
# EEM Script Logic:
#
# This script is triggered by the syslog pattern above.  
# The script captures numerous show command outputs from EXEC, ADMIN and the SHELL.
#
# If the above email environment variables are set the script will then generate an email to the 
# users listed within the _email_to.
#
# Copyright (c) 2014 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------


############################################################################################################
# Syslog Message:
#
# g_spa_3[159]: %L2-SPA-3-PLIM_HEARTBEAT_ERR : SPA-4XT3/E3: bay 3 heartbeat missed, expected seq# 4981185 received seq# 4981184, 
#    Time since last message 38s
############################################################################################################

# Define the namespace
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
##################################
# Verify the environment vars:
##################################
# Storage location:
if {![info exists _PLIM_heartbeat_collection_storage_location]} {
  set result "EEM policy error: environment var _PLIM_heartbeat_collection_storage_location not set"
  error $result $errInfo
}

# Below var flag is used to verify if the PLIM collections ran previously:
set PLIM_collection_run_flag "$_PLIM_heartbeat_collection_storage_location/flag.PLIM_heartbeat_collection"

##################################
# Default syslog/email messages
##################################
set msg_repeat 1
set repeat $msg_repeat

##################################
# PROCs:
##################################
proc sleep {wait_time} {
  after [expr {int($wait_time * 1000)}]
}

proc extract_location {line} {
  global FH
  set location ""

  regsub -all {[ \r\t\n]+} $line " " line
  regsub -all {^[ ]} $line "" line
  regsub -all {[ ]$} $line "" line

  if {[regexp {^time_sec} $line]} {
    regexp "\{(.*): .*" $line - msg
    set location [ lindex [split $msg ":"] 0 ]
    regsub -all {^LC\/} $location "" location
  } else {
    set location [ lindex [split $line ":"] 0 ]
    regsub -all {^LC\/} $location "" location
  }
  return $location
}

proc send_syslog {msg repeat} {
  set kont 0

  while {$kont < $repeat} {
    action_syslog msg $msg
    incr kont
  }
}

proc send_email {node syslog_msg msg} {
  global FH
  global _email_to _email_from
  global _email_server _domainname
  global email_subject

  action_syslog msg "Sending PLIM_heartbeat_collection Detection to $_email_to"

  foreach recipient [split $_email_to " "] {
    set email [format "Mailservername: %s" "$_email_server"]
    set email [format "%s\nFrom: %s" "$email" "$_email_from"]
    set email [format "%s\nTo: %s" "$email" "$recipient"]
    set email [format "%s\nCc: %s" "$email" ""]
    set email [format "%s\nSubject: %s\n" "$email" $email_subject]

    # Email BODY:
    set email [format "%s\n%s" "$email" "The $node node experienced the following syslog:"]
    set email [format "%s\n%s\n\n" "$email" "$syslog_msg"]
    set email [format "%s\n%s" "$email" "$msg"]
   
    # Send email message:
    if [catch {smtp_send_email $email} result] {
      puts "smtp_send_email: $result"
    }
 
    puts $FH "EMAIL DATA BELOW SENT TO: $_email_to\n"
    puts $FH $email
  }
}

proc get_interfaces {cmd_output} {
  global subinterfaces main_interfaces

  foreach line [split $cmd_output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp {^ATM} $line]} {
      set iface [ lindex [split $line " "] 0 ]
      if {[regexp {\.} $iface]} {
        lappend subinterfaces $iface
      } else {
        lappend main_interfaces $iface
      }
    }
  }
}

proc get_SPA {cmd cmd_output} {
  global node_name SPA

  foreach line [split $cmd_output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {![regexp {CPU0} $line] && ![regexp "$cmd" $line]} {
      if {[regexp {^\d+\/\d+\/\d+} $line]} {
        set first_column [lindex $line 0]
        lappend node_name $first_column

        regexp {^\d+\/\d+\/(\d+)} $first_column - spa
        lappend SPA $spa
      }
    }
  }
  set SPA [lsort -unique $SPA]
  set SPA [lindex $SPA 0]
  set node_name [lsort -unique $node_name]
  set node_name [lindex $node_name 0]
}

proc get_process_blocked_pids {output} {
  global pids jids

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp {^\d+ \d+ \d+ .*} $line] && [regexp {g_spa_|spa_192_jacket_v2} $line]} {
      set jid [lindex $line 0]
      set pid [lindex $line 1]
      lappend jids $jid
      lappend pids $pid

      set jids [lsort -unique $jids]
      set pids [lsort -unique $pids]
    }
  }
}

proc determine_LC_type {output} {
  global channel

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp {CHOC12} $line]} {
      set channel 3
    }
  }
}


##################################
# main/MAIN
##################################
global FH
global syslog_msg
global _email_to _email_from
global _email_server _domainname
global email_subject
global node_name SPA
global pids jids

set jids ""
set pids ""
set show_cmds ""
set skip_get_SPA 0
set channel 1
set updated_NodeName ""

# Capture the scripts start time:
set time_now [clock seconds]

set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
set filename "PLIM_heartbeat_collection.$date_time"
set output_file "$_PLIM_heartbeat_collection_storage_location/$filename"

# Open the output file (for write):
if [catch {open $output_file w} result] {
    error $result
}
set FH $result

# Timestamp the script start time to the output log file:
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]
puts $FH "Timestamp: $date"

# Log the nodes hostname to the output log file:
set node [info hostname]
puts $FH "Node: $node"

set syslog_msg "Node: $node - EEM PLIM_heartbeat_collection POLICY DETECTED A POSSIBLE Heartbeat loss FAILURE"

set email_subject "**Node $node - EEM PLIM_heartbeat_collection POLICY DETECTED A POSSIBLE Heartbeat loss FAILURE"
if {[info exists _PLIM_heartbeat_collection_email_subject]} {
  set email_subject "$node $_PLIM_heartbeat_collection_email_subject"
}

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message the finally kicked off the EEM script:
set kickoff_msg $arr_einfo(msg)

# Remove extra spaces/etc from the $kickoff_msg
regsub -all {[ \r\t\n]+} $kickoff_msg " " kickoff_msg
regsub -all {^[ ]} $kickoff_msg "" kickoff_msg
regsub -all {[ ]$} $kickoff_msg "" kickoff_msg


# If the $PLIM_collection_run_flag file exists exit from script:
if [file exists $PLIM_collection_run_flag] {
  set msg "EEM policy PLIM collection $PLIM_collection_run_flag FLAG exists No Action Taken!"
  action_syslog msg $msg

  set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
  puts $FH "\nTimestamp = $date"
  set msg "$msg\nDelete $PLIM_collection_run_flag in order to activate the EEM PLIM Collection script.\n\nSyslog Kickoff:\n$kickoff_msg\n"
  puts $FH $msg
  close $FH
  exit
} else {
  # Create the $PLIM_collection_run_flag file
  if [catch {open $PLIM_collection_run_flag w} result] {
      error $result
  }
  set RUN $result
  set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
  puts $RUN "Timestamp = $date"
  close $RUN
}


# Determine the location from the kickoff_msg:
set location [extract_location $kickoff_msg]
puts $FH "location extracted from kickoff_msg: $location"

#set location "0/2/CPU0"

# Verify the location variable exists
if {$location == ""} {
  error "Exiting EEM script - No location detected"
  exit 1
}


# Extract the slot number from the location
regexp {^\d+\/(\d+)\/CPU0} $location - slot
puts $FH "slot: $slot"

# If the kickoff_msg has 'bay # heartbeat' within it extract the bay id from the syslog message
if {[regexp { bay \d+ heartbeat} $kickoff_msg]} {
  regexp { bay (\d+) heartbeat} $kickoff_msg - bay_id
  puts $FH "bay_id: $bay_id"
  set SPA $bay_id

  set node_name "0/$slot/$bay_id"
  set location_partial "0/$slot"
  set skip_get_SPA 1 

  puts $FH "node_name: $node_name"
  puts $FH "SPA: $SPA"
  puts $FH "location_partial: $location_partial"
} else {
  # If the kickoff_msg does not contain the bay id then we need to find a SPA port from the LC location
  set msg "Unable to determine SPA bay id from syslog kickoff_msg.  Script will gather SPA IDs from 'show platform'."
  puts $FH "\n$msg\n"
}

# location without the CPU0
regsub -all {CPU0$} $location "" location_partial
if {$location_partial == ""} {
  error "Exiting EEM script - No location_partial extracted. Cannot continue execution."
  exit 1
}


############################################################
# Set the DEFAULT show commands to capture from the router:
############################################################
lappend show_cmds "show platform"
lappend show_cmds "show log"
lappend show_cmds "show processes cpu location $location"
lappend show_cmds "show controllers sonet $location_partial*"
lappend show_cmds "show hw-module trace all level error location $location"
lappend show_cmds "show hw-module trace pltfm level sum loc $location"
lappend show_cmds "show hw-module trace all level detailed location $location"
lappend show_cmds "show hw-module fpd location all "
############################################################
# End of DEFAULT show commands
############################################################

puts $FH "\nFinal Syslog Trigger:"
puts $FH "--------------------------------"
puts $FH "$kickoff_msg\n"
puts $FH "\n"
set msg "EEM Script (PLIM_heartbeat_collection) detected possible Heartbeat failure. EEM Script will capture a number of outputs."
puts $FH "$msg\n"
action_syslog msg $msg


#######################
# Open Node Connection
#######################
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}

if {$skip_get_SPA != 1} {
  set cmd "show platform | inc $location_partial"
  if [catch {cli_exec $cli(fd) $cmd} result] {
    error $result $errorInfo
  }
  # Remove trailing router prompt
  #regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
  puts $FH $result

  # get_SPA returns:  node_name  SPA
  get_SPA $cmd $result

  puts $FH "\nSPA: $SPA"
  puts $FH "node_name: $node_name\n"
}

# Create the updated_NodeName.  Example: node0_2_1
regsub -all {\/} $node_name "_" updated_NodeName
set updated_NodeName "node$updated_NodeName"
puts $FH "updated NodeName: $updated_NodeName\n"


# Determine the LC type and channel id
set cmd "show platform | inc $node_name"
if [catch {cli_exec $cli(fd) $cmd} result] {
  error $result $errorInfo
}
# Remove trailing router prompt
#regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
puts $FH $result

# determine_LC_type returns:  channel
determine_LC_type $result
puts $FH "channel: $channel\n"


if {$SPA != ""} {
  set cmd "debug spa disable-heartbeat process g_spa_$SPA location $location"
  puts $FH "Running CMD: $cmd"
  if [catch {cli_exec $cli(fd) $cmd} result] {
    error $result $errorInfo
  }
  # Remove trailing router prompt
  #regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
  puts $FH $result
}

if {$node_name != ""} {
  lappend show_cmds "show hw-module subslot $node_name counters fpga"
  lappend show_cmds "show hw-module subslot $node_name counters spi4"
  lappend show_cmds "show hw-mod subslot $node_name errors fpga"
  lappend show_cmds "show hw-mod subslot $node_name plim-subblock"
  lappend show_cmds "show hw-mod subslot $node_name errors fpga"
  lappend show_cmds "show hw-mod subslot $node_name plim-subblock"
  lappend show_cmds "show hw-module subslot $node_name counters fpga"
  lappend show_cmds "show hw-module subslot $node_name counters spi4"
  lappend show_cmds "show hw-mod subslot $node_name errors fpga"
  lappend show_cmds "show hw-mod subslot $node_name plim-subblock"
  lappend show_cmds "show hw-mod subslot $node_name errors fpga"
  lappend show_cmds "show hw-mod subslot $node_name plim-subblock"
  lappend show_cmds "show hw-mod subslot $node_name errors fpga"
  lappend show_cmds "show hw-mod subslot $node_name plim-subblock"
  lappend show_cmds "show hw-mod subslot $node_name errors fpga"
  lappend show_cmds "show hw-module subslot $node_name counters fpga"
  lappend show_cmds "show hw-module subslot $node_name counters spi4"
}


set run 0
while {$run <= 2} { 
  set cmd "show processes blocked location $location"   ;# Run 3 times get the PIDs for g_spa_ and spa_192_jacket_v2
  if [catch {cli_exec $cli(fd) $cmd} result] {
    error $result $errorInfo
  }
  # Remove trailing router prompt
  #regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
  puts $FH $result

  # get_process_blocked_pids returns: jids  pids
  get_process_blocked_pids $result
  incr run
}

if {$pids != ""} {
  foreach pid [split $pids " "] {
    set cmd "follow process $pid stackonly iteration 3 location $location"
    if [catch {cli_exec $cli(fd) $cmd} result] {
      error $result $errorInfo
    }
    # Remove trailing router prompt
    #regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
    puts $FH $result
  }
} else {
  puts $FH "\nNo 'g_spa' OR 'spa_192_jacket_v2' PIDs found. Skipping the 'follow process' command\n"
}

if {$jids != ""} {
  foreach jid [split $jids " "] {
    set cmd "dumpcore running $jid location $location"
    if [catch {cli_exec $cli(fd) $cmd} result] {
      error $result $errorInfo
    }
    # Remove trailing router prompt
    #regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
    puts $FH $result
  }
} else {
  puts $FH "\nNo 'g_spa' OR 'spa_192_jacket_v2' JIDs found. Skipping the 'dumpcore' command\n"
}

# Next run the DEFAULT 'show_cmds' list
foreach cmd $show_cmds {
  puts $FH "Running CMD: $cmd"

  if [catch {cli_exec $cli(fd) $cmd} result] {
    error $result $errorInfo
  }
  # Remove trailing router prompt
  #regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
  puts $FH $result
  puts $FH ""
}

if {$SPA != ""} {
  puts $FH "\nAttaching to LC\n\n"

  ###########################################
  # Attach to LC and run some show commands:
  ###########################################
  set cmd "run attach $location"
  puts $FH "Running CMD: $cmd"
  if [catch {cli_write $cli(fd) $cmd} result] {
    error $result $errorInfo
  }
  if [catch {cli_read_pattern $cli(fd) "ksh-LC>"} result] {
    error $result $errorInfo
  }

  set cmd "qad_show -p /dev/shmem/spa_ingress_q"
  puts $FH "Running CMD (5 times): $cmd"
  for {set kont 0} {$kont <= 4} {incr kont} {
    if [catch {cli_write $cli(fd) "$cmd\n"} result] {
      error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "ksh-LC>"} result] {
      error $result $errorInfo
    }
    puts $FH "OUTPUT:\n$result"
  }

  set cmd "qad_show -p /dev/shmem/spa_egress_q"
  puts $FH "Running CMD (5 times): $cmd"
  for {set kont 0} {$kont <= 4} {incr kont} {
    if [catch {cli_write $cli(fd) "$cmd\n"} result] {
      error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "ksh-LC>"} result] {
      error $result $errorInfo
    }
    puts $FH "OUTPUT:\n$result"
  }

  set cmd "fab_lc_dbg -s"
  puts $FH "Running CMD (3 times): $cmd"
  for {set kont 0} {$kont <= 2} {incr kont} {
    if [catch {cli_write $cli(fd) "$cmd\n"} result] {
      error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "ksh-LC>"} result] {
      error $result $errorInfo
    }
    puts $FH "OUTPUT:\n$result"
  }

  set cmd "qad_show -i"
  puts $FH "Running CMD (2 times): $cmd"
  for {set kont 0} {$kont <= 1} {incr kont} {
    if [catch {cli_write $cli(fd) "$cmd\n"} result] {
      error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "ksh-LC>"} result] {
      error $result $errorInfo
    }
    puts $FH "OUTPUT:\n$result"
  }

  set cmd "show_spabrg -b txedrp,bay=$SPA,chan=$channel"
  puts $FH "Running CMD (5 times): $cmd"
  for {set kont 0} {$kont <= 4} {incr kont} {
    if [catch {cli_write $cli(fd) "$cmd\n"} result] {
      error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "ksh-LC>"} result] {
      error $result $errorInfo
    }
    puts $FH "OUTPUT:\n$result"
  }

  set cmd "pidin"
  puts $FH "Running CMD (2 times): $cmd"
  for {set kont 0} {$kont <= 1} {incr kont} {
    if [catch {cli_write $cli(fd) "$cmd\n"} result] {
      error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "ksh-LC>"} result] {
      error $result $errorInfo
    }
    puts $FH "OUTPUT:\n$result"
  }

  if {$pids != ""} {
    foreach pid [split $pids " "] {
      set cmd "attach_process -p $pid -S –i3"
      puts $FH "Running CMD (1 time): $cmd"
      if [catch {cli_write $cli(fd) "$cmd\n"} result] {
        error $result $errorInfo
      }
      if [catch {cli_read_pattern $cli(fd) "ksh-LC>"} result] {
        error $result $errorInfo
      }
      puts $FH "OUTPUT:\n$result"
    }
  } else {
    puts $FH "\nNo 'g_spa' OR 'spa_192_jacket_v2' PIDs found. Skipping the 'attach_process' command\n"
  }

  set cmd "ls /net/$updated_NodeName"
  puts $FH "Running CMD (1 time): $cmd"
  if [catch {cli_write $cli(fd) "$cmd\n"} result] {
    error $result $errorInfo
  }
  if [catch {cli_read_pattern $cli(fd) "ksh-LC>"} result] {
    error $result $errorInfo
  }
  puts $FH "OUTPUT:\n$result"

  set cmd "cat /net/$updated_NodeName/dev/cpu_util"
  puts $FH "Running CMD (5 times): $cmd"
  for {set kont 0} {$kont <= 4} {incr kont} {
    if [catch {cli_write $cli(fd) "$cmd\n"} result] {
      error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "ksh-LC>"} result] {
      error $result $errorInfo
    }
    puts $FH "OUTPUT:\n$result"
  }

  set cmd "cat /proc/qnetstats"
  puts $FH "Running CMD (3 times): $cmd"
  for {set kont 0} {$kont <= 2} {incr kont} {
    if [catch {cli_write $cli(fd) "$cmd\n"} result] {
      error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "ksh-LC>"} result] {
      error $result $errorInfo
    }
    puts $FH "OUTPUT:\n$result"
  }

  set cmd "cat /net/$updated_NodeName/proc/qnetstats"
  puts $FH "Running CMD (1 time): $cmd"
  if [catch {cli_write $cli(fd) "$cmd\n"} result] {
    error $result $errorInfo
  }
  if [catch {cli_read_pattern $cli(fd) "ksh-LC>"} result] {
    error $result $errorInfo
  }
  puts $FH "OUTPUT:\n$result"

  # Put this at the end of the LC Shell captures
  set cmd "cat /net/$updated_NodeName/dev/slog"
  puts $FH "Running CMD (1 time): $cmd"
  if [catch {cli_write $cli(fd) "$cmd\n"} result] {
    error $result $errorInfo
  }
  if [catch {cli_read_pattern $cli(fd) "ksh-LC>"} result] {
    error $result $errorInfo
  }
  puts $FH "OUTPUT:\n$result"


  # Exit out of the LC Shell
  if [catch {cli_write $cli(fd) "exit"} result] {
    error $result $errorInfo
  }


  # Turn off the 'debug spa' command
  set cmd "no debug spa disable-heartbeat process g_spa_$SPA location $location"
  puts $FH "Running CMD: $cmd"
  if [catch {cli_exec $cli(fd) $cmd} result] {
    error $result $errorInfo
  }
  # Remove trailing router prompt
  #regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
  puts $FH $result
}


set output_file "$_PLIM_heartbeat_collection_storage_location/$filename"

set msg "EEM script PLIM_heartbeat_collection ($node) COMPLETED.  EEM script captures saved to file:\n$output_file"
send_syslog $msg $repeat

# Send an email message if all below exists:
if {[info exists _email_server] && [info exists _domainname] && [info exists _email_from] && [info exists _email_to]} {
  # Call on the send_email proc to generate an email message
  send_email $node $syslog_msg $msg
}

close $FH
