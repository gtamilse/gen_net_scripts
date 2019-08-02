::cisco::eem::event_register_syslog pattern "Clear counters on all interfaces" maxrun 120

####################################################################################################
# Email Option
# To activate the email option the following event manager environment variables must be set:
#   _email_server    _email_from
#   _email_to        _domainname
#
# Example:
#  event manager environment _email_to ssearch@cisco.com
#  event manager environment _domainname cisco.com
#  event manager environment _email_from ssearch@cisco.com
#  event manager environment _email_server 9.3.0.1
#  event manager directory user policy disk0:/eem
#  event manager policy email.tcl username eem-user persist-time 3600 type user
#
####################################################################################################

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
proc send_email {node} {
  global _email_to _email_from
  global _email_server _domainname
  global email_subject

  action_syslog msg "EEM Sending Email"

  foreach recipient [split $_email_to " "] {
    set email [format "Mailservername: %s" "$_email_server"]
    set email [format "%s\nFrom: %s" "$email" "$_email_from"]
    set email [format "%s\nTo: %s" "$email" "$recipient"]
    set email [format "%s\nCc: %s" "$email" ""]
    set email [format "%s\nSubject: %s\n" "$email" $email_subject]

    # Email BODY:
    set email [format "%s\n%s" "$email" "Email sent from router: $node via EEM"]
    set email [format "%s\n%s\n\n" "$email" "Test Message"]
   
    # Send email message:
    if [catch {smtp_send_email $email} result] {
      puts "smtp_send_email: $result"
    }
  }
}

##################################
# MAIN
##################################
global _email_to _email_from
global _email_server _domainname
global email_subject

# Capture the scripts start time:
set time_now [clock seconds]
# Timestamp the script start time to the output log file:
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]

# Log the nodes hostname to the output log file:
set node [info hostname]

set email_subject "EEM email from router $node"

if {[info exists _email_server] && [info exists _domainname] && [info exists _email_from] && [info exists _email_to]} {
  # Call on the send_email proc to generate an email message
  send_email $node
}

