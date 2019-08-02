::cisco::eem::event_register_syslog pattern "SSHD.*SECURITY-SSHD-6-INFO_SUCCESS.*Successfully authenticated user.*lpp-oss-st1" maxrun 600

###############################################################################################################
# NAME: xml_timeout_captures.tcl
# AUTH: Scott Search (ssearch@cisco.com)
# DATE: 7/24/13
# VERS: v0.4
#
# Need to set the following EEM environment variable:
# -------------------------------------------------------------
# set _xml_timeout_captures_storage_location "disk0:/XML_timeout_captures"
#
# Example pattern:
# ----------------
#  RP/0/7/CPU0:Jul 24 05:36:19.316 : SSHD_[65744]: %SECURITY-SSHD-6-INFO_SUCCESS : Successfully authenticated user 'lpp-oss-st1' 
#    from '199.37.175.171' on 'vty0'(cipher 'aes256-cbc', mac 'hmac-sha1')
#
###############################################################################################################

# Import namespace libraries:
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

# Verify the environment vars:
if {![info exists _xml_timeout_captures_storage_location]} {
  set result "**ERROR: EEM policy error environment var _xml_timeout_captures_storage_location not set"
  action_syslog msg $result
  exit 1
}

###########################################
# Procs
###########################################
proc sleep {wait_time} {
  after [expr {int($wait_time * 1000)}]
}

proc Get_CMDs {_xml_timeout_captures_storage_location stamp} {
  global cmds
  set cmds "
        show proc cpu | inc CPU
        show proc cpu | e 0% .*0% .*0%
        show management xml trace
        show management xml mda trace
        show processes location all
        show processes
        show proc cpu location 0/0/cpu0 | inc CPU
        show proc cpu location 0/15/cpu0 | inc CPU
        show mem sum location 0/7/cpu0
        show mem sum location 0/8/cpu0
        show mem sum location 0/0/cpu0
        show mem sum location 0/15/cpu0
        show proc blocked location 0/7/cpu0
        show proc blocked location 0/8/cpu0
        show processes blocked location 0/0/cpu0
        show processes blocked location 0/15/cpu0
        show xml sessions detail
        show ssh
        show ssh session detail
        show config lock
        show config sessions detail
        show user all
        show cfgmgr trace
        show cfgmgr commitdb
        show xml trace
        show config trace
        show tech sysdb
  "

;#        show tcp trace

}

proc Get_Debug_CMDs {} {
  global debug_cmds
  set debug_cmds "
        debug management xml tty data
        debug xml
        debug xml trace
        debug ssh client
        debug ssh server
        debug config connections
        debug config errors
        debug config lock
        debug ssh traffic
  "
}


############
#   main   #
############
global FH
global _xml_timeout_captures_storage_location
global cmds
global debug_cmds

set msg ""
set node [info hostname]

set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
set stamp [clock format [clock sec] -format "%T_%b_%d_%Y"]
set month_day [clock format [clock sec] -format "%b %d"]
regsub -all {:} $stamp "." stamp

set cmds [Get_CMDs $_xml_timeout_captures_storage_location $stamp]
set debug_cmds [Get_Debug_CMDs]

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message the finally kicked off the EEM script:
set syslog_msg $arr_einfo(msg)

regsub -all {[ \r\t\n]+} $syslog_msg " " syslog_msg
regsub -all {^[ ]} $syslog_msg "" syslog_msg
regsub -all {[ ]$} $syslog_msg "" syslog_msg

set LogFile "xml_timeout_captures_$stamp"
set output_file "$_xml_timeout_captures_storage_location/$LogFile"

# open the output file (for write):
if [catch {open $output_file w} result] {
    error $result
}
set FH $result

puts $FH "*Timestamp = $date"
puts $FH "Cisco XML Timeout Captures"
puts $FH "Node: $node\n"
puts $FH "SYSLOG MSG:\n$syslog_msg\n\n"

sleep 30

# Open router (vty) connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}

if [catch {cli_exec $cli(fd) "term len 0"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "term mon disable"} result] {
  error $result $errorInfo
}


if [catch {cli_exec $cli(fd) "show users"} result] {
  error $result $errorInfo
}
# Remove trailing router prompt
regexp {\n*(.*\n)([^\n]*)$} $result junk output

set connected 0
foreach line [split $output "\n"] {
  if {[regexp "lpp-oss-st1" $line]} {
    set connected 1
  }
}

if {$connected == 1} {
  # User 'lpp-oss-st1' still connected.  Capture the outputs

  # Run list of commands from the proc Get_CMDs
  foreach cmd [split $cmds "\n"] {
    # Trim up the cmd remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $cmd " " cmd
    # Remove any leading white space:
    regsub -all {^[ ]} $cmd "" cmd

    if {$cmd != ""} {
      puts $FH "Running CMD: $cmd"
      if [catch {cli_exec $cli(fd) "$cmd"} result] {
        error $result $errorInfo
      }
      # Remove trailing router prompt
      regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output

      puts $FH "$cmd_output\n\n"
    }
  }

  # Run list of Debug commands from the proc Get_Debug_CMDs
  puts $FH ""
  foreach cmd [split $debug_cmds "\n"] {
    # Trim up the cmd remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $cmd " " cmd
    # Remove any leading white space:
    regsub -all {^[ ]} $cmd "" cmd

    if {$cmd != ""} {
      puts $FH "Running CMD: $cmd"
      if [catch {cli_exec $cli(fd) "$cmd"} result] {
        error $result $errorInfo
      }
    }
  }

  sleep 10

  if [catch {cli_exec $cli(fd) "undebug all"} result] {
    error $result $errorInfo
  }

  # Next do a 'show log | inc SSHD | inc "<month> <day>"'
  if [catch {cli_exec $cli(fd) "show log | inc \"$month_day\""} result] {
    error $result $errorInfo
  }
  # Remove trailing router prompt
  regexp {\n*(.*\n)([^\n]*)$} $result junk cmd_output
  puts $FH "\nDebugs Below:"
  puts $FH "$cmd_output\n\n"

  cli_close $cli(fd) $cli(tty_id)

  close $FH
  regsub -all "\[ \t\n\]" $output_file {} output_file

  set msg "Completed the EEM policy xml_timeout_captures"
  action_syslog msg $msg
} else {
  set msg "EEM policy xml_timeout_captures Exited user 'lpp-oss-st1' no longer logged in"
  
  puts $FH "$msg"
  action_syslog msg $msg
}

