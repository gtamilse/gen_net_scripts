::cisco::eem::event_register_syslog occurs 3 period 10 pattern "fabricq_mgr.*FABRIC-FABRICQ-3-RESET : Reseting Fabricq ASIC Device" maxrun 300

#------------------------------------------------------------------
# s2FailDetect EEM Script
#
#
# May 2010 - Scott Search (ssearch@cisco.com)
# Updated: 06/14/2010 -ssearch
# Updated: 09/08/2010 -ssearch: Modified the syslog history processing
#
#
# This tool is an EEM policy to detect the syslog pattern above in the
# event a CRS node experiences S2/Fabric problems.  This script will 
# eventually cost-out the node.
#
# EEM Script is dependent on the following event manager environment variables:
#   _s2FailDetect_ospf_id <xxx>               -User must provide routers router ospf process id *
#   _s2FailDetect_second_diff 30              -Defined seconds diff for syslog msg matching
#   _s2FailDetect_unique_locations 3          -Defined number of unique locations 
#   _s2FailDetect_output_log <logfile name>   -User must provide the output log file name "s2FailDetect.log"
#   _s2FailDetect_storage_location <storage>  -Disk/hardisk storage location "harddisk:/eem"
#
# NOTES:
#   * _s2FailDetect_ospf_id -Can be set to 0 and the EEM script will NOT COST OUT router. Optional.
#
# Syslog Message Generation:
#   _s2FailDetect_msg_repeat <x>       -Msg generation repeated x number of times (default 1)
#   _s2FailDetect_msg_CostOut          -Msg sent via syslog/email generation when router is COSTED OUT
#   _s2FailDetect_msg_NoCostOut        -Msg sent via syslog/email generation when router is NOT COSTED OUT
#   _s2FailDetect_msg_NoCostOut_NotMet -Msg sent via syslog/email generation when router is NOT COSTED OUT
#                                       due to all requirments not met.
#
# Email Option
# To activate the email option the following event manager environment variables must be set:
#   _email_server    _email_from
#   _email_to        _domainname
#
#
# EEM Script Logic:
#
# The script is triggered by the syslog pattern above.  If the pattern occurs 3 times and within
# a 10 second period this EEM policy will be started.  The script checks the syslogs via the
# sys_reqinfo_syslog_history for matching events within the _s2FailDetect_second_diff from the
# triggering syslog event pattern.  If there are at minimum _s2FailDetect_unique_locations the
# script proceeds with the costing out of the router.
# 
#
# Copyright (c) 2010 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------
#
#
# The namespace import commands that follow import some cisco TCL extensions
# that are required to run this script

# Define the namespace
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
##########################################################################################
# Set the pattern the script will filter on (maybe set within the eem environment vars):
##########################################################################################
set pattern "FABRIC-FABRICQ-3-RESET : Reseting Fabricq ASIC Device"

###################################################
# Set the show commands to capture from the router:
###################################################
set admin_show_cmds "show controllers fabricq health
                     show controllers fabric plane all
                     show platform"

##################################
# Verify the environment vars:
##################################
# Storage location:
if {![info exists _s2FailDetect_storage_location]} {
  set result "EEM policy error: environment var _s2FailDetect_storage_location not set"
  error $result $errInfo
}
# Output log file:
if {![info exists _s2FailDetect_output_log]} {
  set result "EEM policy error: environment var _s2FailDetect_output_log not set"
  error $result $errInfo
}
# Seconds difference, used for comparing previous matched syslogs:
if {![info exists _s2FailDetect_second_diff]} {
  set result "EEM policy error: environment var _s2FailDetect_second_diff not set"
  error $result $errInfo
}
# Unique locations for comparing:
if {![info exists _s2FailDetect_unique_locations]} {
  set result "EEM policy error: environment var _s2FailDetect_unique_locations not set"
  error $result $errInfo
}

##################################
# Default syslog/email messages
##################################
set msg_repeat 1
set msg_CostOut "EEM s2FailDetect policy detected a possible Node S2 problem. Node has been COSTED OUT"
set msg_NoCostOut "EEM s2FailDetect policy detected possible S2 problem. NO COST OUT performed\
                   due to _s2FailDetect_ospf_id not set"
set msg_NoCostOut_NotMet "EEM s2FailDetect policy detected possible S2 problem. Yet unique locations below\
                          threshold ($_s2FailDetect_unique_locations)"


##################################
# PROCs:
##################################
proc extract_location {line} {
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
    puts $FH "Location Extracted: $location\n"
  } else {
    set location [ lindex [split $line ":"] 0 ]
    puts $FH "Location Extracted: $location\n"
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

  action_syslog msg "Sending S2 Fail Detect Detection to $_email_to"

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


##################################
# Main/main
##################################
global FH
global _email_to _email_from
global _email_server _domainname
global msg_repeat msg_CostOut
global msg_NoCostOut msg_NoCostOut_NotMet
global msg_repeat email_subject
set locations ""

if {[info exists _s2FailDetect_msg_repeat]} {
  set repeat $_s2FailDetect_msg_repeat
} else {
  set repeat $msg_repeat
}

# Open the output file (for write):
if [catch {open $_s2FailDetect_storage_location/$_s2FailDetect_output_log w} result] {
    error $result
}
set FH $result

# Capture the scripts start time:
set time_now [clock seconds]
# Set the seconds to go back from the previously captured script start time:
set seconds_to_go_back [expr $time_now - $_s2FailDetect_second_diff]

# Timestamp the script start time to the output log file:
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]
puts $FH "*Timestamp = $date"

# Log the nodes hostname to the output log file:
set node [info hostname]
puts $FH "Node: $node"

set email_subject "**Node $node Possible S2 Fail Detection**"
# Verify if the routers configuration has the _s2FailDetect_email_subject line configuration set:
if {[info exists _s2FailDetect_email_subject]} {
  # Gaurav requested subject line:
  #    CRS Fabric Error Detected: Potential Serious Black Hole Situation could exist
  set email_subject "$node $_s2FailDetect_email_subject"
}

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message the finally kicked off the EEM script:
set syslog_msg $arr_einfo(msg)

puts $FH "\n"
puts $FH "Final Syslog Trigger:"
puts $FH $syslog_msg
puts $FH "\n"

# Extract the first location from the triggering syslog event:
lappend locations [extract_location $syslog_msg]

# Capture the syslogs history:
set hist_list [sys_reqinfo_syslog_history]
# Remove the following characters from $hist_list: {}"
regsub -all {\{|\}|\"} $hist_list {} hist_list

set concat_string ""
foreach rec $hist_list {
  foreach syslog $rec {
    if {[regexp {^time_sec} $syslog]} {
      if {[llength $concat_string] > 4} {
        ;# puts $FH "DEBUG: concat_string: $concat_string"
 
        if {[regexp $pattern $concat_string]} {
          set time_rec [lindex $concat_string 0]
          set location [lindex $concat_string 4]
          # Remove the : from the location string
          set location [ lindex [split $location ":"] 0 ]
          # Verify the time_rec string is numeric:
          if {[string is double -strict $time_rec] || [string is digit -strict $time_rec]} {
            ;# puts $FH "DEBUG: time_rec: $time_rec"
            if {[regexp -nocase "cpu0$" $location]} {
              puts $FH "Location Extracted: $location"
              if {$time_rec > $seconds_to_go_back} {
                lappend locations $location
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

# Open Node Connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}
# Enter Admin mode:
if [catch {cli_exec $cli(fd) "admin"} result] {
  error $result $errorInfo
}

puts $FH ""
puts $FH "locations before sort: $locations"
set unique_locations [lsort -unique $locations]
puts $FH "unique_locations: $unique_locations\n"
set num_unique_locations [llength $unique_locations]

if {$num_unique_locations > $_s2FailDetect_unique_locations} {
  # Proceed with the node COST OUT as long as $s2FailDetect_ospf_id is set to a value above 0:
  if {[info exists _s2FailDetect_ospf_id]} {
    if {$_s2FailDetect_ospf_id > 0} {
      puts $FH "Unique Locations ($num_unique_locations) above configured\
                _s2FailDetect_unique_locations: $_s2FailDetect_unique_locations"
      puts $FH "Continuing on with Costing Out node!"

      #########################################################
      # Currently the router COST OUT Disabled:
      #########################################################
      set msg "ROUTER COST-OUT CURRENTLY DISABLED WITHIN SCRIPT"
      send_syslog $msg 1

      ;#    # Enter config terminal:
      ;#    if [catch {cli_exec $cli(fd) "config t"} result] {
      ;#      error $result $errorInfo
      ;#    }
      ;#    if [catch {cli_exec $cli(fd) "router ospf $_s2FailDetect_ospf_id"} result] {
      ;#      error $result $errorInfo
      ;#    }
      ;#    if [catch {cli_exec $cli(fd) "max-metric router-lsa include-stub"} result] {
      ;#      error $result $errorInfo
      ;#    }
      ;#    if [catch {cli_exec $cli(fd) "commit"} result] {
      ;#      error $result $errorInfo
      ;#    }
      ;#    if [catch {cli_exec $cli(fd) "end"} result] {
      ;#      error $result $errorInfo
      ;#    }
      # End of Configuration tasks

      # Send syslog message:
      if {[info exists _s2FailDetect_msg_CostOut]} {
        set msg $_s2FailDetect_msg_CostOut
      } else {
        set msg $msg_CostOut
      }
      send_syslog $msg $repeat
    } else {
      # No cost out due to $_s2FailDetect_ospf_id not set above 0
      if {[info exists _s2FailDetect_msg_NoCostOut]} {
        set msg $_s2FailDetect_msg_NoCostOut
      } else {
        set msg $msg_NoCostOut
      }
      send_syslog $msg $repeat
    }
  } else {
    # No cost out due to $_s2FailDetect_ospf_id not set
    if {[info exists _s2FailDetect_msg_NoCostOut]} {
      set msg $_s2FailDetect_msg_NoCostOut
    } else {
      set msg $msg_NoCostOut
    }
    send_syslog $msg $repeat
  }

  if {[info exists _email_server] && [info exists _domainname] && [info exists _email_from] && [info exists _email_to]} {
    # Call on the send_email proc to generate an email message
    send_email $node $syslog_msg $msg
  }
} else {
  # No COST OUT
  puts $FH "Unique Locations ($num_unique_locations) below threshold: $_s2FailDetect_unique_locations"
  puts $FH "Exiting EEM policy without Costing Out node"

  if {[info exists _s2FailDetect_msg_NoCostOut_NotMet]} {
    set msg $_s2FailDetect_msg_NoCostOut_NotMet
  } else {
    set msg $msg_NoCostOut_NotMet
  }
  # Send syslog message:
  send_syslog $msg $repeat
}

puts $FH ""
# Capture the system show commands:
foreach cmd [split $admin_show_cmds "\n"] {
  # Trim up the cmd remove extra space/tabs etc:
  regsub -all {[ \r\t\n]+} $cmd " " cmd
  # Remove any leading white space:
  regsub -all {^[ ]} $cmd "" cmd
  puts $FH "command output: $cmd"
 
  if [catch {cli_exec $cli(fd) "$cmd"} result] {
    error $result $errorInfo
  }
  # Remove trailing router prompt
  regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
  puts $FH $cmd_output
  puts $FH ""
}
# Exit Admin mode:
if [catch {cli_exec $cli(fd) "exit"} result] {
  error $result $errorInfo
}

close $FH
