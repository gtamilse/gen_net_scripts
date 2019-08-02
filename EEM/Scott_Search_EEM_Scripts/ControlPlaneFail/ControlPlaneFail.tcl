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
# This EEM script is triggered off the above syslog pattern as long as the syslog message is generated 3 times
# within a 3 second period.  The script then parses the routers syslog history for further ATM Layer 3 
# failures and extracts the LC locations.  If the same ATM LC locations exist the script then runs a number of
# trace commands, such as:
#
#   show qsm trace location <LC location>
#   show qsm trace loc <RP location>
#   show arm trace location <RP location>
#
# If the above trace outputs yield failures the script then continues and generates syslog message, opens a 
# file handle on the routers disk and writes the outputs to this file.  Lastly, if the user has the above email
# environment settings within the routers configuration the script will generate an email.
#
# Copyright (c) 2011 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------

############################################################################################################
# Syslog Messages:
#
# RP/0/8/CPU0::Sep 16 00:08:06.891 : ospf[361]: %ROUTING-OSPF-5-ADJCHG : Process 50, Nbr 165.87.242.176 on ATM0/12/0/0.210
#  in area 0.0.0.54 from FULL to DOWN, Neighbor Down: interface down or detached,vrf default vrfid 0x60000000
# RP/0/8/CPU0::Sep 16 00:08:06.894 : ospf[361]: %ROUTING-OSPF-5-ADJCHG : Process 50, Nbr 165.87.242.97 on ATM0/12/0/0.211 
#  in area 0.0.0.54 from FULL to DOWN, Neighbor Down: interface down or detached,vrf default vrfid 0x60000000
# RP/0/8/CPU0::Sep 16 00:08:06.898 : ospf[361]: %ROUTING-OSPF-5-ADJCHG : Process 50, Nbr 32.119.158.24 on ATM0/12/0/1.210 
#  in area 0.0.0.54 from FULL to DOWN, Neighbor Down: interface down or detached,vrf default vrfid 0x60000000
#
# RP/0/8/CPU0::Sep 16 00:08:06.961 : pim[371]: %ROUTING-IPV4_PIM-5-NBRCHG : PIM neighbor 32.119.247.161 DOWN on 
#  AT0/12/0/0.210 - interface state changed
# RP/0/8/CPU0::Sep 16 00:08:06.967 : pim[371]: %ROUTING-IPV4_PIM-5-NBRCHG : PIM neighbor 32.119.247.162 DOWN on 
#  AT0/12/0/0.210 - interface state changed
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

proc extract_location {line} {
  set location ""

  regsub -all {[ \r\t\n]+} $line " " line
  regsub -all {^[ ]} $line "" line
  regsub -all {[ ]$} $line "" line

  if {[regexp {ATM|AT0} $line]} {
    regexp {ATM(\d+\/\d+\/\d+\/\d+).*} $line - location

    if {$location == ""} {
      regexp {AT(\d+\/\d+\/\d+\/\d+).*} $line - location
    }
  }
  return $location
}

proc extract_month_day {line} {
  set month_day ""
  set month ""
  set day ""

  regsub -all {[ \r\t\n]+} $line " " line
  regsub -all {^[ ]} $line "" line
  regsub -all {[ ]$} $line "" line

  if {[regexp {^RP} $line]} {
    regexp {^RP.*\/CPU0:(\w+) (\d+) .*} $line - month day
    if {$day < 10} {
      set month_day "$month  $day"
    } else {
      set month_day "$month $day"
    }
  }
  return $month_day
}

proc process_syslog_history {} {
  global seconds_to_go_back
  set locations ""
  set concat_string ""

  # Capture the syslogs history:
  set hist_list [sys_reqinfo_syslog_history]
  # Remove the following characters from $hist_list: {}"
  regsub -all {\{|\}|\"} $hist_list {} hist_list

  foreach rec $hist_list {
    foreach syslog $rec {
      if {[regexp {^time_sec} $syslog]} {
        if {[llength $concat_string] > 4} {
          if {[regexp {ATM|AT0} $concat_string] && [regexp {DOWN} $concat_string]} {
            set time_rec [lindex $concat_string 0]
            # Verify the time_rec string is numeric:
            if {[string is double -strict $time_rec] || [string is digit -strict $time_rec]} {
              if {$time_rec > $seconds_to_go_back} {
                if {$concat_string != ""} {
                  lappend locations [extract_location $concat_string]
                }
              }
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
  return $locations
}

proc parse_qsm_trace {output} {
  set found 0
  set rp ""

# show qsm trace location 0/12/CPU0 | i "informing qsm that node"
# Sep 16 00:03:06.731 qsm_critical 0/12/CPU0 t1  qsm_node_is_down: pid=28702 informing qsm that node(node0_8_CPU0) is down 
# Sep 16 00:03:08.525 qsm_critical 0/12/CPU0 t1  qsm_node_is_down: pid=28702 informing qsm that node(node0_7_CPU0) is down

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp {qsm_critical} $line] && [regexp {qsm_node_is_down} $line]} {
      set found 1
      regexp {node\((.*)\) .*} $line - node

      regsub {node0_} $node "0/" node
      regsub {\_} $node "/" node
      lappend rp $node
    }
  }
  if {$found != 1} { exit 1 }
  return $rp
}

proc parse_qsm_rp_trace {output} {
  set found 0

  # RP/0/8/CPU0:PLWRSW1002CR1#show qsm trace loc 0/8/CPU0 | i Sep 16 00:
  # Sep 16 00:03:06.739 qsm_normal 0/8/CPU0 t1  received_dbdump_request_message. received from node: (9/6/20501)
  # RP/0/8/CPU0:PLWRSW1002CR1#show qsm trace loc 0/7/CPU0 | i Sep 16 00:
  # Sep 16 00:03:08.532 qsm_normal 0/7/CPU0 t8  received_dbdump_request_message. received from node: (9/6/20501)

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp {received_dbdump_request_message. received from node} $line]} { set found 1 }
  }
  if {$found != 1} { exit 1 }
}

proc parse_arm_trace {output location} {
  set found 0

  # 4) Then grep for the string in arm trace "Close producer 'ipv4_ma <affected LC>', reason 0" followed by 
  #    "Notify consumers about IP address of" from the command below
  #     From the active RP at the affected day we should see ALL the interfaces having this message.
  # ------------------------------------------------------------------------------------------------------------------ 
  # 
  # RP/0/8/CPU0:PLWRSW1002CR1#show arm trace location 0/8/CPU0 | be Sep 16 
  # Mon Sep 19 18:19:58.561 GMT
  # Sep 16 00:03:06.754 ipv4_arm/prod 0/8/CPU0 t1  Close producer 'ipv4_ma 0/12/CPU0', reason 0
  # Sep 16 00:08:06.860 ipv4_arm/cons 0/8/CPU0 t1  Notify consumers about IP address of ATM0/12/0/0.210 changed to 0.0.0.0
  # Sep 16 00:08:06.860 ipv4_arm/cons 0/8/CPU0 t1  Notify consumers about IP address of ATM0/12/0/0.211 changed to 0.0.0.0
  # Sep 16 00:08:06.860 ipv4_arm/cons 0/8/CPU0 t1  Notify consumers about IP address of ATM0/12/0/1.210 changed to 0.0.0.0
  # Sep 16 00:08:06.860 ipv4_arm/cons 0/8/CPU0 t1  Notify consumers about IP address of ATM0/12/0/1.211 changed to 0.0.0.0

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp {Close producer} $line] && [regexp {ipv4_ma} $line]} {
      if {[regexp "$location" $line]} { set found 1 }
    }
  }
  if {$found != 1} { exit 1 }
}

proc extract_active_rp {output} {
  set active_rp ""

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp {^Node} $line]} {
      regexp {^Node (.*) is in} $line - active_rp
    }
  }
  if {$active_rp == ""} { exit 1 }
  return $active_rp
}

proc send_email {FH node syslog_msg msg} {
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

proc OpenFile_GenSyslog_SendEmail {date_time kickoff_msg location total_output} {
  global FH
  set filename "ControlPlaneFail.$date_time"

  # Open the output file (for write):
  if [catch {open $_ControlPlaneFail_storage_location/$filename w} result] {
    error $result
  }
  set FH $result
  puts $FH "*Timestamp = $date_time"

  # Log the nodes hostname to the output log file:
  set node [info hostname]
  puts $FH "Node: $node"

  set syslog_msg "Node: $node - EEM ControlPlaneFail POLICY DETECTED A POSSIBLE ENGINE 3 ATM LC FAILURE"

  set email_subject "**Node $node - EEM ControlPlaneFail POLICY DETECTED A POSSIBLE ENGINE 3 ATM LC FAILURE"
  # Verify if the routers configuration has the _ControlPlaneFail_email_subject line configuration set:
  if {[info exists _ControlPlaneFail_email_subject]} {
    set email_subject "$node $_ControlPlaneFail_email_subject"
  }

  puts $FH "\nTriggering Syslog Message:\n"
  puts $FH "$kickoff_msg\n"

  puts $FH "\n"
  set msg "EEM Script (ControlPlaneFail) detected possible E3 ATM LC failure: $location."
  set msg "$msg\n\nOutputs Captured Below:\n"
  set msg "$msg\n$total_output\n"
  puts $FH $msg
  action_syslog msg $msg

  # Send an email message if all below exists:
  if {[info exists _email_server] && [info exists _domainname] && [info exists _email_from] && [info exists _email_to]} {
    # Call on the send_email proc to generate an email message
    send_email $FH $node $syslog_msg $msg
  }
  close $FH
}


#######
# main
#######
global FH
global syslog_msg email_subject
global _email_to _email_from
global _email_server _domainname
global seconds_to_go_back

# Capture the scripts start time:
set time_now [clock seconds]
set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
# Set the seconds to go back (10 seconds):
set seconds_to_go_back [expr $time_now - 10]

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message that finally kicked off the EEM script:
set kickoff_msg $arr_einfo(msg)

# Determine the location from the kickoff_msg:
set location [extract_location $kickoff_msg]

regexp {^(\d+\/\d+)\/} $location - c1
set LC_location "$c1/CPU0"

set locations [process_syslog_history]
set locations_length [llength $locations]
set unique_locations [lsort -unique $locations]
set num_unique_locations [llength $unique_locations]

if {$locations_length < 1} { exit 1 }
if {![regexp "$location" $unique_locations]} { exit 1 }

# Get the month/day values from the original syslog msg
set month_day [extract_month_day $kickoff_msg]

######################
# Open Node Connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}
if [catch {cli_exec $cli(fd) "term len 0"} result] {
  error $result $errorInfo
}
######################

# run CMD
if [catch {cli_exec $cli(fd) "show qsm trace location $LC_location | inc \"informing qsm that node\""} result] {
  error $result $errorInfo
}
# Remove trailing router prompt
regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
set RPs [parse_qsm_trace $cmd_output]
set total_output $cmd_output

# run CMD
if [catch {cli_exec $cli(fd) "show red | inc ACTIVE"} result] {
  error $result $errorInfo
}
regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
set ActiveRP [extract_active_rp $cmd_output]
set total_output "$total_output\n\n$cmd_output"

# run CMD
if [catch {cli_exec $cli(fd) "show qsm trace location $ActiveRP | inc $month_day"} result] {
  error $result $errorInfo
}
regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
parse_qsm_rp_trace $cmd_output
set total_output "$total_output\n\n$cmd_output"

# run CMD
if [catch {cli_exec $cli(fd) "show arm trace location $ActiveRP | beg $month_day"} result] {
  error $result $errorInfo
}
regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
set total_output "$total_output\n\n$cmd_output"
parse_arm_trace $cmd_output $LC_location


# Restart the LC location QSM
if [catch {cli_exec $cli(fd) "process restart qsm location $LC_location"} result] {
  error $result $errorInfo
}


# If the EEM script makes it this far then there is definitely a problem with the Routers ATM LC
#
# Next open a file, generate syslogs and possibly send an email if required
OpenFile_GenSyslog_SendEmail $date_time $kickoff_msg $LC_location $total_output

