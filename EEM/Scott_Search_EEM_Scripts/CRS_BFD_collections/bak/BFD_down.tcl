::cisco::eem::event_register_syslog pattern "L2-BFD-6-SESSION_STATE_DOWN : BFD session to neighbor .* has gone down. Reason: Nbor signalled down" maxrun 600

#------------------------------------------------------------------
# If the following syslog example pattern is generated this EEM script will be triggered:
#
#  %L2-BFD-6-SESSION_STATE_DOWN : BFD session to neighbor 12.12.1.14 on interface TenGigE0/2/0/3 has gone down. Reason: Nbor signalled down
#
# September 2017 - Scott Search (ssearch@cisco.com)
#
# Copyright (c) 2017 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------
#
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
set cmds "
show tech bundle
show tech bfd
show tech cef
show tech cef platform
show logging
"

##################################
# PROCs:
##################################
proc get_interface {line} {
  set iface ""

  regsub -all {[ \r\t\n]+} $line " " line
  regsub -all {^[ ]} $line "" line
  regsub -all {[ ]$} $line "" line

  if {[regexp {BFD session to neighbor} $line]} {
    regexp "on interface (.*) has gone down" $line - iface
  }

  return $iface
} ;# get_interface


proc get_bundleID {output} {
  set ID ""

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp {^bundle id} $line]} {
      regexp {^bundle id (\d+) .*} $line - ID
    } 
  }
  
  return $ID
} ;# get_bundleID


proc get_locations {output} {
  set loc ""
  set locations ""

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp {^\S+\d+\/\d+\/\d+\/\d+.*} $line]} {
      regexp {^\S+\d+\/(\d+)\/\d+\/\d+.*} $line - loc
      lappend locations $loc
    } 
  }

  set locations [lsort -unique $locations]

  return $locations
} ;# get_locations


proc sleep {N} {
   after [expr {int($N * 1000)}]
}


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

set filename "BFD_collections.$date_time"
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

set iface [get_interface $syslog_msg]


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
}

set cmd "show run interface $iface"
if [catch {cli_exec $cli(fd) $cmd} result] {
  error $result $errorInfo
}
puts $FH "$result\n\n"

set ID [get_bundleID $result]


set cmd "show bundle bundle-e $ID | inc Active"
if [catch {cli_exec $cli(fd) $cmd} result] {
  error $result $errorInfo
}
puts $FH "$result\n\n"

set locations [get_locations $result]


# Enter a loop to run the below bundle load-balancing and cef adjacency commands a few times then the show tech's with a 5 sec interval
set loop 1

while { $loop < 6 } {
  incr loop

  # Run the "show bundle load-balancing bundle-eth $ID detail location $location"  command
  foreach location $locations {
    set cmd "show bundle load-balancing bundle-eth $ID det loc $location"
    if [catch {cli_exec $cli(fd) $cmd} result] {
      error $result $errorInfo
    }
    puts $FH "$result\n\n"
  }

  # Run the "show cef adjacency bundle-eth $ID hardware <egress/ingress> detail location $location"  command
  foreach location $locations {
    set cmd1 "show cef adjacency bundle-eth $ID hardware egress det location $location"
    set cmd2 "show cef adjacency bundle-eth $ID hardware ingress det location $location"

    if [catch {cli_exec $cli(fd) $cmd1} result] {
      error $result $errorInfo
    }
    puts $FH "$result\n\n"

    if [catch {cli_exec $cli(fd) $cmd2} result] {
      error $result $errorInfo
    }
    puts $FH "$result\n\n"
  }


  # Running the list of commands:
  foreach CMD [split $cmds "\n"] {
    if {$CMD == ""} { continue }
    if [catch {cli_exec $cli(fd) $CMD} result] {
      error $result $errorInfo
    }
    puts $FH "$result\n\n"
  }

  sleep 5
} # End of loop


close $FH
