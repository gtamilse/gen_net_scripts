::cisco::eem::event_register_syslog pattern "PKT_INFRA-LINK-3-UPDOWN : Interface FortyGigE.*changed state to Up" maxrun 240

#------------------------------------------------------------------
# Up_40G_bw_update.tcl
# October 2012 - Scott Search (ssearch@cisco.com)
# Version: v0.1
#
# Syslog message:
# PKT_INFRA-LINK-3-UPDOWN : Interface FortyGigE5/3/0/0, changed state to Up
#
# EEM script will be triggered off the above syslog message.  This eem script will be triggered off one of the FortyGigE
# interface that comes Up.  The script then determines the mapped TE dummy interface and performs a no shut for the 
# dummy interface
#
# Below environment varibales need to be set within the XR config:
# set _storage_location "disk0:/eem"
# set _up_40G_output_log "Up_40G_bw_update"
# set _40G_mappings "40G_mappings"
#
#
# Copyright (c) 2012 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

action_syslog msg "EEM policy Up_40G_bw_update has started"

# Verify the environment vars:
if {![info exists _storage_location]} {
  set result "**ERROR: EEM policy error environment var _storage_location not set"
  puts $result
  action_syslog msg $result
  exit 1
}

if {![info exists _up_40G_output_log]} {
  set result "**ERROR: EEM policy error environment var _up_40G_output_log not set"
  puts $result
  action_syslog msg $result
  exit 1
}

if {![info exists _40G_mappings]} {
  set result "**ERROR: EEM policy error environment var _40G_mappings not set"
  puts $result
  action_syslog msg $result
  exit 1
}
#################################################################################################


###########################################
# Procedures
###########################################
proc sleep {wait_time} {
  after [expr {int($wait_time * 1000)}]
}

proc extract_interface {syslog} {
  regsub -all {[ \r\t\n]+} $syslog " " syslog
  regsub -all {^[ ]} $syslog "" syslog
  regsub -all {[ ]$} $syslog "" syslog

  regexp {Interface (FortyGigE\d+\/\d+\/\d+\/\d+), changed} $syslog - interface
  return $interface
}

proc determine_tunnel_dummy {Interface FH} {
  global _storage_location
  global _40G_mappings
  set return_tunnel_int ""

  set mapping_file "$_storage_location/$_40G_mappings"
  puts $FH "mapping_file: $mapping_file\n"

  if {![file exists $mapping_file]} {
    action_syslog msg "**ERROR: EEM policy Up_40G_bw_update 40Gig mappings file unknown or does not exist"
    exit 1
  }

  # open file for read
  set OPEN_FH [open $mapping_file r]
  set file_contents [read $OPEN_FH]
  close $OPEN_FH

  # process the data
  set contents [split $file_contents "\n"]
  foreach line $contents {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    set FortyGig_int [ lindex [split $line " "] 0 ]
    set Tunnel_int   [ lindex [split $line " "] 1 ]

    if {($FortyGig_int != "" && $Tunnel_int != "")} {
      if {$FortyGig_int == $Interface} {
        set return_tunnel_int $Tunnel_int
      }
    }
  }
  return $return_tunnel_int
}

proc parse_log_history {ShowLog Interface} {
  global FH
  set interface_Up 0
  set interface_Down 0
  set kont 0
  set result 1

  puts $FH "\n{parse_log_history} ShowLog: $ShowLog\n"
  puts $FH "{parse_log_history} Search Interface: $Interface\n"

  set output [split $ShowLog "\n"]
  foreach line $output {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {([regexp "Line protocol on Interface FortyGigE" $line] && [regexp "state to Down" $line])} {
      if {[regexp $Interface $line]} {
        puts $FH "Down LINE: $line"
        set interface_Down $kont
      }
    }

    if {([regexp "Line protocol on Interface FortyGigE" $line] && [regexp "state to Up" $line])} {
      if {[regexp $Interface $line]} {
        puts $FH "Up LINE: $line"
        set interface_Up $kont
      }
    }
    incr kont
  }
  if {$interface_Up > 0 && $interface_Down > 0} {
    if {$interface_Up < $interface_Down} {
      puts $FH "\nFound the $Interface should still be down as the syslog Up was before the syslog Down message"
      puts $FH "interface_Up: $interface_Up"
      puts $FH "interface_Down: $interface_Down\n"
      set result 0
    } else {
      puts $FH "\nFound the $Interface maybe back up after the Down syslog message"
      puts $FH "interface_Up: $interface_Up"
      puts $FH "interface_Down: $interface_Down\n"
    }
    puts $FH "\n"
  }
  return $result
}


###########################################
# MAIN/main
###########################################
sleep 2 

# Globals:
global FH
global _storage_location
global _40G_mappings

set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
set stamp [clock format [clock sec] -format "%T_%b_%d_%Y"]
regsub -all {:} $stamp "." stamp
set _up_40G_output_log "${_up_40G_output_log}_$stamp"

# set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# extract the syslog message:
set syslog_msg $arr_einfo(msg)

set Interface [extract_interface $syslog_msg]

# open the output file (for write):
if [catch {open $_storage_location/$_up_40G_output_log w} result] {
    error $result
}
set FH $result

puts $FH "*Timestamp = $date"
puts $FH "Cisco Up_40G_bw_update"
puts $FH "by: Scott Search (ssearch@cisco.com)\n"

puts $FH "SYSLOG MSG:\n$syslog_msg\n\n"
puts $FH "Interface Up: $Interface\n"

set dummy_interface [determine_tunnel_dummy $Interface $FH]
puts $FH "Tunnel dummy interface: $dummy_interface\n"

if {$dummy_interface != ""} {
  puts $FH "No Shutdown Tunnel Dumy Interface: $dummy_interface\n"

  # open Node Connection
  if [catch {cli_open} result] {
    error $result $errorInfo
  } else {
    array set cli $result
  }

  ###############################################################################################
  # Below the script will look to see if this FortyGigE interface changed state to Up
  ###############################################################################################
  if [catch {cli_exec $cli(fd) "show log last 30 | inc PKT_INFRA-LINEPROTO-5-UPDOWN"} result] {
    error $result $errorInfo
  }
  # Remove trailing router prompt
  regexp {\n*(.*\n)([^\n]*)$} $result junk ShowLog
  set continue [parse_log_history $ShowLog $Interface]
  if {!$continue} {
    set result "**INFO: EEM policy Up_40G_bw_update Found the $Interface maybe back up. Check router and EEM policy log file"
    puts $FH "\n$result\n"
    action_syslog msg $result
    close $FH
    exit 1
  }
  ###############################################################################################

  # set node hostname:
  set node [info hostname]
  puts $FH "Node: $node"

  # no-shut the Tunnel dummy interface
  if [catch {cli_exec $cli(fd) "config"} result] {
    error $result $errorInfo
  }
  if [catch {cli_exec $cli(fd) "interface $dummy_interface"} result] {
    error $result $errorInfo
  }
  if [catch {cli_exec $cli(fd) "no shutdown"} result] {
    error $result $errorInfo
  }
  if [catch {cli_exec $cli(fd) "commit"} result] {
    error $result $errorInfo
  }
  if [catch {cli_exec $cli(fd) "end"} result] {
    error $result $errorInfo
  }

  puts $FH "Dummy Interface now no shutdown\n"
  close $FH

  action_syslog msg "EEM policy Up_40G_bw_update no shutdwon following Tunnel Dummy interface: $dummy_interface"
} else {
  action_syslog msg "**ERROR: EEM policy Up_40G_bw_update unable to determine the Tunnel Dummy Interface"
}
