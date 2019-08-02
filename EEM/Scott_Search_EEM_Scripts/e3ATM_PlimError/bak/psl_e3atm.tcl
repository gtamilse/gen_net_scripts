::cisco::eem::event_register_syslog occurs 5 period 10 pattern "ROUTING-LDP-5-NBR_CHANGE.*DOWN.*IP address removed" maxrun 3600

#------------------------------------------------------------------
# Eng3ATMcap EEM Script
#
# January 2011 - Scott Search (ssearch@cisco.com)
#
# EEM script/policy to detect the syslog pattern above in the event a xr12k node experiences 
# an engine 3 ATM LC failure.  This script will verify the LC failure signature and capture
# a number of commands for later analysis.
#
# EEM Script is dependent on the following event manager environment variable(s):
#   _Eng3ATMcap_storage_location <storage>  -Disk/hardisk storage location "harddisk:/eem"
#
# Email Option
# To activate the email option the following event manager environment variables must be set:
#   _email_server    _email_from
#   _email_to        _domainname
#
# EEM Script Logic:
#
# This script is triggered by the syslog pattern above.  Once the script is triggered the script
# analyzes the previous logs for the pattern1 and pattern2 below.  If these patterns are matched
# within a 45 second period from when the script was triggered the script continues.  If the 
# patterns below do not match within this 45 second period the script will exit.  Once the script
# continues the script captures numerous show command outputs from EXEX, ADMIN and the SHELL.  If
# the above email environment variables are set the script will then generate an email to the 
# users listed within the _email_to.
#
# Copyright (c) 2011 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------

# Define the namespace
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
######################################################################
# Below is an additional syslog msg pattern the script will filter on:
######################################################################
set pattern1 "ROUTING-OSPF-5-ADJCHG : Process"
set pattern2 "from FULL to DOWN, Neighbor Down: interface down or detached"

############################################
# Syslog messages we are most interested in:
############################################
;# mpls_ldp[313]: %ROUTING-LDP-5-NBR_CHANGE : Neighbor 165.87.247.165:0, DOWN (IP address removed)
;# RP/0/7/CPU0::Dec 10 16:55:12.309 : ospf[336]: %ROUTING-OSPF-5-ADJCHG : Process 2, Nbr 165.87.247.165 on ATM0/11/0/0.210 in area 10.10.3.1 from FULL to DOWN, Neighbor Down: interface down or detached,vrf default vrfid 0x60000000

##################################
# Verify the environment vars:
##################################
# Storage location:
if {![info exists _Eng3ATMcap_storage_location]} {
  set result "EEM policy error: environment var _Eng3ATMcap_storage_location not set"
  error $result $errInfo
}

##################################
# Default syslog/email messages
##################################
set msg_repeat 1

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

  if [regexp {(ATM\d+\/\d+\/) *} $line - iface] {
    regsub -all {^ATM} $iface "" location
    append location "CPU0"
  }
  if {$location != ""} {
    puts $FH "ATM LC location extracted: $location"
  }
  return $location
}

proc get_job_id {retval} {
  global FH
  set job_id 0

  foreach line [split $retval "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line

    regexp {^Job Id: (\d+)} $line - job_id
  }

  if {$job_id != 0} {
    puts $FH "Debug: job id found: $job_id"
  } else {
    puts $FH "Debug: job id not found"
  }
  return $job_id
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

  action_syslog msg "Sending Eng3ATMcap Detection to $_email_to"

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
# main
##################################
global FH
global msg_repeat syslog_msg
global _email_to _email_from
global _email_server _domainname
global email_subject

if {[info exists _Eng3ATMcap_msg_repeat]} {
  set repeat $_Eng3ATMcap_msg_repeat
} else {
  set repeat $msg_repeat
}

# Capture the scripts start time:
set time_now [clock seconds]
# Set the seconds to go back from the previously captured script start time (45 seconds):
set seconds_to_go_back [expr $time_now - 45]

set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
set filename "Eng3ATMcap.$date_time"
# Open the output file (for write):
if [catch {open $_Eng3ATMcap_storage_location/$filename w} result] {
    error $result
}
set FH $result

############################################################
# Set the show commands to capture from the router:
############################################################
set show_cmds "sh red"

set admin_show_cmds "show redun"
###################################################
# End of show commands
###################################################

# Timestamp the script start time to the output log file:
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]
puts $FH "*Timestamp = $date"

# Log the nodes hostname to the output log file:
set node [info hostname]
puts $FH "Node: $node"

set syslog_msg "Node: $node - EEM Eng3ATMcap POLICY DETECTED A POSSIBLE ENGINE 3 ATM LC FAILURE"

set email_subject "**Node $node - EEM Eng3ATMcap POLICY DETECTED A POSSIBLE ENGINE 3 ATM LC FAILURE"
# Verify if the routers configuration has the _Eng3ATMcap_email_subject line configuration set:
if {[info exists _Eng3ATMcap_email_subject]} {
  set email_subject "$node $_Eng3ATMcap_email_subject"
}

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message the finally kicked off the EEM script:
set kickoff_msg $arr_einfo(msg)

puts $FH "\nFinal Syslog Trigger:\n"
puts $FH "$kickoff_msg\n"

# Capture the syslogs history:
set hist_list [sys_reqinfo_syslog_history]
# Remove the following characters from $hist_list: {}"
regsub -all {\{|\}|\"} $hist_list {} hist_list

set GoBack_msgs 0
set concat_string ""
foreach rec $hist_list {
  foreach syslog $rec {
    if {[regexp {^time_sec} $syslog]} {
      if {[llength $concat_string] > 4} {
        ;#puts $FH "DEBUG: concat_string: $concat_string"
        if {[regexp $pattern1 $concat_string] && [regexp $pattern2 $concat_string]} {
          ;#puts $FH "DEBUG: concat_string: $concat_string"
          set time_rec [lindex $concat_string 0]
          # Verify the time_rec string is numeric:
          if {[string is double -strict $time_rec] || [string is digit -strict $time_rec]} {
            ;#puts $FH "DEBUG: time_rec: $time_rec"
            if {$time_rec > $seconds_to_go_back} {
              incr GoBack_msgs
              ;#puts $FH "DEBUG: increment GoBack_msgs"
              lappend locations [extract_location $concat_string]
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

set GoBack_value 6
if {$GoBack_msgs < $GoBack_value} {
  # Exit from script
  set msg "EEM Script (Eng3ATMcap) exiting due to GoBack_msgs below required value ($GoBack_value) found ($GoBack_msgs)"
  puts $FH $msg
  action_syslog msg $msg
  close $FH
  exit
}

puts $FH "\n"
set msg "EEM Script (Eng3ATMcap) detected possible E3 ATM LC failure. EEM Script will capture a number of command outputs"
puts $FH $msg
action_syslog msg $msg

# Open Node Connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}
if [catch {cli_exec $cli(fd) "term len 0"} result] {
  error $result $errorInfo
}

puts $FH "\nLocations before sort: $locations"
set unique_locations [lsort -unique $locations]
puts $FH "unique_locations: $unique_locations\n"
set locations $unique_locations
set num_locations [llength $locations]

#################################
# Capture the EXEC show commands:
#################################
foreach cmd [split $show_cmds "\n"] {
  # Trim up the cmd remove extra space/tabs etc:
  regsub -all {[ \r\t\n]+} $cmd " " cmd
  # Remove any leading white space:
  regsub -all {^[ ]} $cmd "" cmd
  puts $FH "command output (EXEC): $cmd"
 
  if [catch {cli_exec $cli(fd) "$cmd"} result] {
    error $result $errorInfo
  }
  # Remove trailing router prompt
  regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
  puts $FH $cmd_output
  puts $FH ""
}

# Enter Admin mode:
if [catch {cli_exec $cli(fd) "admin"} result] {
  error $result $errorInfo
}

###################################
# Capture the ADMIN show commands:
###################################
foreach cmd [split $admin_show_cmds "\n"] {
  # Trim up the cmd remove extra space/tabs etc:
  regsub -all {[ \r\t\n]+} $cmd " " cmd
  # Remove any leading white space:
  regsub -all {^[ ]} $cmd "" cmd
  puts $FH "command output (ADMIN): $cmd"
 
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

set msg "EEM script Eng3ATMcap ($node) detected a possible Engine 3 LC failure and captured a number of commands"
send_syslog $msg $repeat

# Send an email message if all below exists:
if {[info exists _email_server] && [info exists _domainname] && [info exists _email_from] && [info exists _email_to]} {
  # Call on the send_email proc to generate an email message
  send_email $node $syslog_msg $msg
}

close $FH
