::cisco::eem::event_register_none maxrun_sec 60

# Define the namespace
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
##################################
# main
##################################
global FH
global msg_repeat syslog_msg
global _email_to _email_from
global _email_server _domainname
global email_subject


# Open Node Connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}
if [catch {cli_exec $cli(fd) "term len 0"} result] {
  error $result $errorInfo
}
puts "After term len 0"




if [catch {cli_write $cli(fd) "run"} result] {
  error $result $errorInfo
}
puts "After cli_write"

if [catch {cli_read_pattern $cli(fd) "#"} result] {
  error $result $errorInfo
}
puts "After cli_read_pattern"

puts "Entering the command  ls /net"
if [catch {cli_write $cli(fd) "ls /net"} result] {
  error $result $errorInfo
}

if [catch {cli_read_pattern $cli(fd) "#"} result] {
  error $result $errorInfo
}

if [catch {cli_read_drain $cli(fd)} result] {
  error $result $errorInfo
}
puts "DRAIN:\n$result"

if [catch {cli_write $cli(fd) "exit"} result] {
  error $result $errorInfo
}

############################################################

if [catch {cli_exec $cli(fd) "show clock"} result] {
  error $result $errorInfo
}
puts $result

############################################################

if [catch {cli_write $cli(fd) "run attach 0/2/cpu0"} result] {
  error $result $errorInfo
}

if [catch {cli_read_pattern $cli(fd) "ksh-LC"} result] {
  error $result $errorInfo
}

if [catch {cli_write $cli(fd) "cat /proc/qnetstats*"} result] {
  error $result $errorInfo
}
if [catch {cli_read_pattern $cli(fd) "ksh-LC"} result] {
  error $result $errorInfo
}
puts "OUTPUT for (cat /proc/qnetstats*):\n$result"

if [catch {cli_write $cli(fd) "pidin -p 1 fds"} result] {
  error $result $errorInfo
}
if [catch {cli_read_pattern $cli(fd) "ksh-LC"} result] {
  error $result $errorInfo
}
puts "OUTPUT for (pidin -p 1 fds):\n$result"

if [catch {cli_write $cli(fd) "show_psarb_listener -c -l all -A"} result] {
  error $result $errorInfo
}
if [catch {cli_read_pattern $cli(fd) "ksh-LC"} result] {
  error $result $errorInfo
}
puts "OUTPUT for (show_psarb_listener -c -l all -A):\n$result"

if [catch {cli_write $cli(fd) "exit"} result] {
  error $result $errorInfo
}

############################################################

if [catch {cli_exec $cli(fd) "show clock"} result] {
  error $result $errorInfo
}
puts $result


puts "Completed"
