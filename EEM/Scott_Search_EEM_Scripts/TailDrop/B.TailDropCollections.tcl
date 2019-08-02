::cisco::eem::event_register_syslog pattern "RX PDMA Ring out" maxrun 600

###################################################################
# Trigger syslog events:
# ----------------------------------------------------------
# Taildrop on QAD queue 8 owned by netio (jid=268)
# Taildrop on XIPC queue 1 owned by netio (jid=268)
###################################################################

#------------------------------------------------------------------
# If a Taildrop on * queue * by netio is generated this script is run
#
# January 2018 - Scott Search (ssearch@cisco.com)
#
# Copyright (c) 2018 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
#set run_flag "harddisk:/eem/TailDropCollections_run_flag"


##################################
# PROCs:
##################################
proc get_location {line} {
  set location ""

  regsub -all {[ \r\t\n]+} $line " " line
  regsub -all {^[ ]} $line "" line
  regsub -all {[ ]$} $line "" line

  set location [ lindex [split $line ":"] 0 ]
  regsub -all {^LC\/} $location "" location

  return $location
} ;# get_location


proc get_JobID {output} {
  set Jobid 0
  set good 0

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp "ProcId JobId Count" $line]} {
      set good 1
    }

    if {$good ne 0} {
      regexp {^\d+ (\d+) \d+ \d+} $line - Jobid
    }
  }

  return $Jobid
} ;# get_JobID


proc get_PakHandles {output} {
  set handles ""
  set PakHandle ""
  set good 0

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp "Pakhandle Job" $line]} {
      set good 1
    }

    if {$good ne 0} {
      if {[regexp {^0x} $line]} {
        set PakHandle [lindex [split $line " "] 0]
        lappend handles $PakHandle
      }
    }
  }

  return $handles
} ;# get_PakHandles


proc capture_interfaces {output} {
  set iface ""
  set interfaces ""

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp {up.*up$} $line]} {
      set iface [lindex [split $line " "] 0]
      lappend interfaces $iface
    }
  }

  return $interfaces
} ;# capture_interfaces


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
set location ""
set cmds ""
set cmd ""

# Capture the scripts start time:
set time_now [clock seconds]

set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]

set filename "TailDropCollections.$date_time"
set output_file "harddisk:/eem/$filename"

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

# Capture location from syslog trigger
set location [get_location $syslog_msg]


# If the $run_flag file exists exit from script:
#if [file exists $run_flag] {
#  set msg "EEM policy TailDropCollections.tcl was triggered, however, the run_flag file: $run_flag exists"
#  action_syslog msg $msg
#
#  set msg "$msg\nDelete $run_flag in order to activate the EEM TailDropCollections.tcl script."
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

# Set the terminal length to 0 and enable the timestamps
set start "
term len 0
term exec prompt timestamp
"

foreach CMD [split $start "\n"] {
  if [catch {cli_exec $cli(fd) $CMD} result] {
    error $result $errorInfo
  }
  puts $FH "$result\n\n"
}

lappend cmds "show packet-memory inuse summary location $location "
lappend cmds "show spp buffer location $location "
lappend cmds "show spp client detail location $location  | inc allocator"

# Run static commands listed above
foreach CMD [split $cmds] {
  if {$CMD == ""} { continue }
  if [catch {cli_exec $cli(fd) $CMD} result] {
    error $result $errorInfo
  }
  puts $FH "$result\n\n"
}


# Get JobID
set CMD "show packet-memory inuse summary location $location"
if [catch {cli_exec $cli(fd) $CMD} result] {
  error $result $errorInfo
}
puts $FH "$result\n\n"
set jobID [get_JobID $result]

set CMD "show packet-memory jobid $jobID location $location"
if [catch {cli_exec $cli(fd) $CMD} result] {
  error $result $errorInfo
}
puts $FH "$result\n\n"


# Get PakHandles
set CMD "show packet-memory inuse location $location"
if [catch {cli_exec $cli(fd) $CMD} result] {
  error $result $errorInfo
}
puts $FH "$result\n\n"
set PakHandles [get_PakHandles $result]

foreach PakHandle $PakHandles {
  set cmd "show packet-memory pakhandle $PakHandle location $location"
  if [catch {cli_exec $cli(fd) $cmd} result] {
    error $result $errorInfo
  }
  puts $FH "$result\n\n"
}



# Get interfaces
set CMD "show interfaces location $location | inc line protocol is up"
if [catch {cli_exec $cli(fd) $CMD} result] {
  error $result $errorInfo
}
puts $FH "$result\n\n"
set Interfaces [capture_interfaces $result]

# Shutdown the interfaces on the triggered location
if [catch {cli_exec $cli(fd) "conf t"} result] {
  error $result $errorInfo
}

foreach iface $Interfaces {
  if [catch {cli_exec $cli(fd) "interface $iface"} result] {
    error $result $errorInfo
  }
  puts $FH "$result\n\n"

  if [catch {cli_exec $cli(fd) "shut"} result] {
    error $result $errorInfo
  }
  puts $FH "$result\n\n"
}

if [catch {cli_exec $cli(fd) "commit"} result] {
  error $result $errorInfo
}

if [catch {cli_exec $cli(fd) "end"} result] {
  error $result $errorInfo
}

close $FH


























