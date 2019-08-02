::cisco::eem::event_register_none maxrun_sec 120

#::cisco::eem::event_register_syslog occurs 2 period 120 pattern "plim_services_.*: HA: XLP .*: Fail String: Cores .* not responding" maxrun 180

#
# Email Option
# To activate the email option the following event manager environment variables must be set:
#   _email_server    _email_from
#   _email_to        _domainname
#
# Copyright (c) 2016 by cisco Systems, Inc.
# All rights reserved.
# Scott Search (ssearch@cisco.com)
#
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

##################################
# Verify the environment vars:
##################################

# Email environment variables:
if {![info exists _email_to]} {
  set result "EEM policy error: environment var _email_to not set"
  error $result $errInfo
}
if {![info exists _email_server]} {
  set result "EEM policy error: environment var _email_server not set"
  error $result $errInfo
}
if {![info exists _domainname]} {
  set result "EEM policy error: environment var _domainname not set"
  error $result $errInfo
}
if {![info exists _email_from]} {
  set result "EEM policy error: environment var _email_from not set"
  error $result $errInfo
}
if {![info exists _sourceIntf]} {
  set result "EEM policy error: environment var _sourceIntf not set"
  error $result $errInfo
}

#################################
# PROCs:
##################################
proc send_syslog {msg repeat} {
  set kont 0

  while {$kont < $repeat} {
    action_syslog msg $msg
    incr kont
  }
} ;# send_syslog


proc send_email {node syslog_msg msg} {
  global _email_to _email_from
  global _email_server _domainname
  global email_subject
  global _sourceIntf

  action_syslog msg "Sending CGSE No Route -- EMAIL Test to $_email_to"

  foreach recipient [split $_email_to " "] {
    set email [format "Mailservername: %s" "$_email_server"]
    set email [format "%s\nFrom: %s" "$email" "$_email_from"]
    set email [format "%s\nTo: %s" "$email" "$recipient"]
    set email [format "%s\nCc: %s" "$email" ""]
    set email [format "%s\nSourceintf: %s" "$email" "$_sourceIntf"]
    set email [format "%s\nSubject: %s\n" "$email" $email_subject]

    # Email BODY:
    set email [format "%s\n%s" "$email" "The $node node CGSE DataPath Error. EMAIL Test."]
    set email [format "%s\n%s\n\n" "$email" "$syslog_msg"]
    set email [format "%s\n%s" "$email" "$msg"]
   
    # Send email message:
    if [catch {smtp_send_email $email} result] {
      puts "smtp_send_email: $result"
    }
  }
} ;# send_email


##################################
# MAIN/main
##################################
global _email_to
global _email_from
global _email_server
global _domainname
global email_subject
global _sourceIntf

set email_subject "CGSE EMAIL test"

set repeat 1 

# Capture the scripts start time:
set time_now [clock seconds]

set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]

set msg "EEM script CGSE_NoRoute -- EMAIL Test"
send_syslog $msg $repeat

# Send an email message if all below exists:
if {[info exists _email_server] && [info exists _domainname] && [info exists _email_from] && [info exists _email_to]} {
  # Call on the send_email proc to generate an email message
  send_email "TestRouter" "Email Test" $msg
}

