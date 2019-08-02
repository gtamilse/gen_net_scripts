::cisco::eem::event_register_syslog occurs 3 period 3 pattern "ROUTING-OSPF-5-ADJCHG .* on ATM.* from FULL to DOWN" maxrun 120

#------------------------------------------------------------------
# ControlPlaneFail EEM Script
#
# October 2011 - Scott Search (ssearch@cisco.com)
#
# EEM Script is dependent on the following event manager environment variable(s):
#   _ControlPlaneFail_storage_location <storage>  -Disk/hardisk storage location "harddisk:/eem"
#
# Email Option
# To activate the email option the following event manager environment variables must be set:
#   _email_server    _email_from
#   _email_to        _domainname
#
# EEM Script Logic:
#
# Copyright (c) 2011 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------

############################################################################################################
# Syslog Messages:
#
# RP/0/8/CPU0::Sep 16 00:08:06.891 : ospf[361]: %ROUTING-OSPF-5-ADJCHG : Process 50, Nbr 165.87.242.176 on ATM0/12/0/0.210 in area 0.0.0.54 from FULL to DOWN, Neighbor Down: interface down or detached,vrf default vrfid 0x60000000
# RP/0/8/CPU0::Sep 16 00:08:06.894 : ospf[361]: %ROUTING-OSPF-5-ADJCHG : Process 50, Nbr 165.87.242.97 on ATM0/12/0/0.211 in area 0.0.0.54 from FULL to DOWN, Neighbor Down: interface down or detached,vrf default vrfid 0x60000000
# RP/0/8/CPU0::Sep 16 00:08:06.898 : ospf[361]: %ROUTING-OSPF-5-ADJCHG : Process 50, Nbr 32.119.158.24 on ATM0/12/0/1.210 in area 0.0.0.54 from FULL to DOWN, Neighbor Down: interface down or detached,vrf default vrfid 0x60000000
#
# RP/0/8/CPU0::Sep 16 00:08:06.961 : pim[371]: %ROUTING-IPV4_PIM-5-NBRCHG : PIM neighbor 32.119.247.161 DOWN on AT0/12/0/0.210 - interface state changed
# RP/0/8/CPU0::Sep 16 00:08:06.967 : pim[371]: %ROUTING-IPV4_PIM-5-NBRCHG : PIM neighbor 32.119.247.162 DOWN on AT0/12/0/0.210 - interface state changed
############################################################################################################

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
##################################
# Verify the environment vars:
##################################
# Storage location:
if {![info exists _ControlPlaneFail_storage_location]} {
  puts "**ERROR: EEM policy error: environment var _ControlPlaneFail_storage_location not set"
  exit 1
}

##################################
# PROCs:
##################################
proc sleep {wait_time} {
  after [expr {int($wait_time * 1000)}]
}

proc extract_location_time_sec {line} {
  global FH
  set location ""

  # Trim up the line remove extra space/tabs etc:
  regsub -all {[ \r\t\n]+} $line " " line
  # Remove any leading white space:
  regsub -all {^[ ]} $line "" line
  # Remove any ending white space:
  regsub -all {[ ]$} $line "" line

  if {[regexp {^time_sec} $line]} {
    regexp "\{(.*): .*" $line - msg
    set location [ lindex [split $msg ":"] 0 ]
    regsub -all {^LC\/} $location "" location
    puts $FH "Location Extracted: $location\n"
  } else {
    set location [ lindex [split $line ":"] 0 ]
    regsub -all {^LC\/} $location "" location
    puts $FH "Location Extracted: $location\n"
  }
  return $location
}

proc extract_location {line} {
  global FH
  set location ""

  # Trim up the line remove extra space/tabs etc:
  regsub -all {[ \r\t\n]+} $line " " line
  # Remove any leading white space:
  regsub -all {^[ ]} $line "" line
  # Remove any ending white space:
  regsub -all {[ ]$} $line "" line

  if {[regexp {ATM|AT0} $line]} {
    regexp {ATM(\d+\/\d+\/\d+\/\d+).*} $line - location

    if {$location == ""} {
      regexp {AT(\d+\/\d+\/\d+\/\d+).*} $line - location
    }
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

  action_syslog msg "Sending Control Plane Failure Detection to $_email_to"

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


#######
# main
#######
global FH
global msg_repeat syslog_msg
global _email_to _email_from
global _email_server _domainname
global email_subject
global subinterfaces main_interfaces

# Capture the scripts start time:
set time_now [clock seconds]
# Set the seconds to go back (10 seconds):
set seconds_to_go_back [expr $time_now - 10]

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message that finally kicked off the EEM script:
set kickoff_msg $arr_einfo(msg)

# Determine the location from the kickoff_msg:
set locations [extract_location $kickoff_msg]
puts "locations: $locations"

# Capture the syslogs history:
set hist_list [sys_reqinfo_syslog_history]
# Remove the following characters from $hist_list: {}"
regsub -all {\{|\}|\"} $hist_list {} hist_list

set concat_string ""
foreach rec $hist_list {
  foreach syslog $rec {
    if {[regexp {^time_sec} $syslog]} {
      if {[llength $concat_string] > 4} {
        if {[regexp {ATM|AT0} $concat_string] && [regexp {DOWN} $concat_string]} {

          set time_rec [lindex $concat_string 0]
;# puts "EEM DEBUG: concat_string: $concat_string"
;#          set location [lindex $concat_string 4]
;#          # Remove the : from the location string
;#          set location [ lindex [split $location ":"] 0 ]
          # Verify the time_rec string is numeric:
          if {[string is double -strict $time_rec] || [string is digit -strict $time_rec]} {
;#            if {[regexp -nocase "cpu0$" $location]} {
;#              puts $FH "Location Extracted: $location"
              if {$time_rec > $seconds_to_go_back} {
if {$concat_string != ""} {
puts "EEM DEBUG: concat_string: $concat_string"
set loca [extract_location $concat_string]
puts "loca: $loca"
}
;#                lappend locations $location
              }
;#            }
          }
          # Reset the concat_string variable:
          set concat_string ""
        }
      } else {
        if {![regexp {^time_sec} $syslog]} {
          lappend concat_string $syslog
        }
      }
    } else {
      if {![regexp {^rec_list} $syslog]} {
        lappend concat_string $syslog
      }
    }
  }
}






;#if {[info exists _ControlPlaneFail_msg_repeat]} {
;#  set repeat $_ControlPlaneFail_msg_repeat
;#} else {
;#  set repeat 1
;#}
;#
;#set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
;#set filename "ControlPlaneFail.$date_time"
;## Open the output file (for write):
;#if [catch {open $_ControlPlaneFail_storage_location/$filename w} result] {
;#    error $result
;#}
;#set FH $result
;#
;## Timestamp the script start time to the output log file:
;#set date [clock format $time_now -format "%T %Z %a %b %d %Y"]
;#puts $FH "*Timestamp = $date"
;#
;## Log the nodes hostname to the output log file:
;#set node [info hostname]
;#puts $FH "Node: $node"
;#
;#set syslog_msg "Node: $node - EEM ControlPlaneFail POLICY DETECTED A POSSIBLE ENGINE 3 ATM LC FAILURE"
;#
;#set email_subject "**Node $node - EEM ControlPlaneFail POLICY DETECTED A POSSIBLE ENGINE 3 ATM LC FAILURE"
;## Verify if the routers configuration has the _ControlPlaneFail_email_subject line configuration set:
;#if {[info exists _ControlPlaneFail_email_subject]} {
;#  set email_subject "$node $_ControlPlaneFail_email_subject"
;#}
;#
;#puts $FH "\nTriggering Syslog Message:\n"
;#puts $FH "$kickoff_msg\n"



;#puts $FH "\n"
;#set msg "EEM Script (ControlPlaneFail) detected possible E3 ATM LC failure. EEM Script will capture a number of outputs"
;#puts $FH $msg
;#action_syslog msg $msg

;#set run 0

;## Open Node Connection
;#if [catch {cli_open} result] {
;#  error $result $errorInfo
;#} else {
;#  array set cli $result
;#}
;#if [catch {cli_exec $cli(fd) "term len 0"} result] {
;#  error $result $errorInfo
;#}

;## location_partial will contain the location, minus the 'CPU0'
;#regsub -all {CPU0$} $location "" location_partial
;#set atm "ATM$location_partial"
;#set cmd "show ipv4 int brie | inc $atm"

;#if [catch {cli_exec $cli(fd) "$cmd"} result] {
;#  error $result $errorInfo
;#}
;## Remove trailing router prompt
;#regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
;##puts $FH $cmd_output

;#get_interfaces $cmd_output

;#set msg "EEM script ControlPlaneFail ($node) detected a possible Engine 3 ATM LC failure and captured a number of commands"
;#send_syslog $msg $repeat
;#
;## Send an email message if all below exists:
;#if {[info exists _email_server] && [info exists _domainname] && [info exists _email_from] && [info exists _email_to]} {
;#  # Call on the send_email proc to generate an email message
;#  send_email $node $syslog_msg $msg
;#}
;#
;#close $FH
