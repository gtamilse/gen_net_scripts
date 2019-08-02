#!/usr/local/bin/perl

# FILE: cc_transfer.pl
# VERS: v0.1
# DESC: cc_transfer: Config Commit Transfer is a tool to copy the on router
#       configuration commit archives to another server
# DATE: 3/6/13
# AUTH: Scott Search (ssearch@cisco.com), Cisco Systems

$|=1;  # flush output buffer

#########################
# BEGIN
#########################
use strict;
our ($session, $DIR, $SCRIPTS_DIR);

BEGIN {
  if (exists($ENV{'CISCO_PERL_DIR'})) {
    $SCRIPTS_DIR = $ENV{'CISCO_PERL_DIR'};
    chdir $SCRIPTS_DIR || die "unable to go to $SCRIPTS_DIR:$!\n";
  }
  my $stop  = "\ncc_transfer.pl tool must be run from the tool location directory.\n";
     $stop .= "--OR--\n";
     $stop .= "Set the CISCO_PERL_DIR environment variable\n\n";
     $stop .= "Examples:\n";
     $stop .= "setenv CISCO_PERL_DIR \"/opt/cisco/perl_tools\"\n";
     $stop .= "CISCO_PERL_DIR=/opt/cisco/perl_tools\n\n";
     $stop .= "And/or the tools path is missing the ./lib directory. This tool is\n";
     $stop .= "dependent on modules within the ./lib location!\n\n\n";

  if ($SCRIPTS_DIR) {
    if (!-d "$SCRIPTS_DIR/lib") {
      print STDERR $stop; exit(1);
    }
  } elsif (!-d "./lib") {
    print STDERR $stop; exit(1);
  }
}
if ($SCRIPTS_DIR) {
  if (-d "$SCRIPTS_DIR/lib") {
    use lib $SCRIPTS_DIR . "/lib";
    $DIR = "$SCRIPTS_DIR";
  }
} elsif (-d "./lib") {
  use lib "./lib";
  $DIR = ".";
}

#########################
# MODULES
#########################
use Net::Telnet;
use IO::Pty ();
use POSIX ();

#########################
# GLOBAL VARs
#########################
our (@script_run_errors, @script_run_warnings);
our ($Eastern, $date_time, $date, $time, $current_seconds);
our ($completed_mods, $p_s1, $p_s2, $p_s3, $p_s4, $p_s5);

# Global Hash VARs:
our %htime = ('wait_time1'   => 30,
              'kill_time1'   => 1500);

our %hftpinfo = ();

our %hprompts = ('xr_standard'    => '/.*(#|>|:|\))\s*$|(#|>|:|\))\s*$/',
                'login'           => '/.*(#)\s*$|(#)\s*$|[Nn][Oo][Cc]\s*:\s*$|[Pp]assword\s*:\s*$/',
                'ios_login'       => '/.*(>)\s*$|.*(#)\s*$|(#)\s*$|[Nn][Oo][Cc]\s*:\s*$|[Pp]assword\s*:\s*$/',
                'xr_return'       => '/.*[#|>]$/i',
                'unix_host'       => '/.*(\>|\%|\$|#)\s*$|.*(\>|\%|\$|#)$/',
                'xr_normal'       => '/RP\/.*CPU0:.*[#]\s*$/',
                'xr_interaction2' => '/.*[#|>|\]:|\]?]\s*$/',
                'xr_interaction'  => '/.*[#|>|?|\]]\s*$/i');

our %hglobal = ('sw_ver'               => "v0.1",
                'cmd_log_kont'          => 1,
                'debug'                 => 0,
                'device'                => "",
                'entered_username'      => "",
                'MAIN_LOG'              => "",
                'node_cmd_log'          => "",
                'node_timeout'          => 1800,
                'offline'               => 0,
                'phandle'               => "",
                'rdump'                 => 0,
                'return_prompt'         => "",
                'tool'                  => 0,
                'verbose'               => 0);

# Print output style/font hash:
our %ST = ('reset'       => "\e[0m",        'clr'        => "\033[2J \n",
          'bold'        => "\e[1m",        'cursor'     => "\033[1;1H",
          'under'       => "\e[4m",        'underb'     => "\e[1m\e[4m",
          'black'       => "\e[30m",       'blackb'     => "\e[1m\e[30m",
          'red'         => "\e[31m",       'redb'       => "\e[1m\e[31m",
          'green'       => "\e[32m",       'greenb'     => "\e[1m\e[32m",
          'yellow'      => "\e[33m",       'yellowb'    => "\e[1m\e[33m",
          'blue'        => "\e[34m",       'blueb'      => "\e[1m\e[34m",
          'magenta'     => "\e[35m",       'magentab'   => "\e[1m\e[35m",
          'cyan'        => "\e[36m",       'cyanb'      => "\e[1m\e[36m",
          'reverse'     => "\e[7m",        'revred'     => "\e[31m\e[7m",
          'revblue'     => "\e[34m\e[7m",  'revblack'   => "\e[30m\e[7m",
          'revgreen'    => "\e[32m\e[7m",  'revyellow'  => "\e[33m\e[7m",
          'revmagenta'  => "\e[35m\e[7m",  'revcyan'    => "\e[36m\e[7m");

####################################################################
# Below are the necessary steps for this tool
####################################################################
our $mod     = "Config Commit Transfer Tool\n";
our $mod_s1  = "1.  Verify Server Archive Directories and Create New Archive Directory\n";
our $mod_s2  = "2.  Router Login\n";
our $mod_s3  = "3.  Lock Configuration Mode\n";
our $mod_s4  = "4.  Transfer Archives to Server\n";
our $mod_s5  = "5.  Delete Router Archives\n";
####################################################################

#########################
# SUBROUTINES
#########################

# ----------------------------------------------------------------------------
# Name         : usage
# Purpose      : Display the script usage
# Notes        : None
# ----------------------------------------------------------------------------
sub usage {
  my $msg;

  $msg  = "\n";
  $msg .= "Syntax:\n";
  $msg .= "-----------------\n";
  $msg .= "$0 {-h|-v|-r} <-n router | router_list> {-u <username>}\n";
  $msg .= "\n";
  $msg .= "\n";
  $msg .= "Examples:\n";
  $msg .= "-----------------\n";
  $msg .= "$0 -n engco102me1\n";
  $msg .= "$0 -v -r -n engco102me1\n";
  $msg .= "$0 -n engco102me1 -u user1\n";
  $msg .= "\n";
  $msg .= "\n";
  $msg .= "Options:\n";
  $msg .= "-----------------\n";
  $msg .= "  <>                        : Required\n";
  $msg .= "  {}                        : Optional\n";
  $msg .= "  -h                         : help manual\n";
  $msg .= "  -v                         : verbose mode\n";
  $msg .= "  -r                         : rdump mode\n";
  $msg .= "  -n <router | router_list>  : Run tool with one router or list of routers\n";
  $msg .= "  -u <username>              : Enter username (TACACS ID)\n";
  $msg .= "\n";
  $msg .= "\n";
  $msg .= "Note:\n";
  $msg .= "-----------------\n";
  $msg .= "User running the tool must have their .ftpinfo file setup for ftp username/password\n";
  $msg .= "for the archive destination server (Auriga)\n";
  $msg .= "\n";

  print $ST{bold}, $msg, $ST{reset};
  exit;
} # usage

# ----------------------------------------------------------------------------
# Name         : cl_parse
# Purpose      : Parse the command line options entered
# Returns      : None
# Notes        : None
# ----------------------------------------------------------------------------
sub cl_parse {
  my $kont = 0;
  foreach my $arg (@ARGV) {
    chomp($arg);
    $arg = join(" ", split " ", $arg);

    # Extract the command line entries:
    if ($arg =~ /^-h$/i) {
      usage();
    } elsif ($arg =~ /^-n$/i) {
      $hglobal{device} = $ARGV[$kont+1];
      $hglobal{device} = join(" ", split " ", $hglobal{device});
    } elsif ($arg =~ /^-user$|^-u$/i) {
      $hglobal{entered_username} = $ARGV[$kont+1];
      $hglobal{entered_username} = join(" ", split " ", $hglobal{entered_username});
    } elsif ($arg =~ /^-v$/i) {
      $hglobal{verbose} = 1;
    } elsif ($arg =~ /^-r$/i) {
      $hglobal{rdump} = 1;
    }
    $kont++;
  }

  if (!$hglobal{device}) { usage(); }
  $hglobal{node} = $hglobal{device};
} # cl_parse

# -----------------------------------------------------------------------
# Name         : run_cmd
# Purpose      : Run system command
# Returns      : @output
# Notes        : None
# -----------------------------------------------------------------------
sub run_cmd {
  my ($cmd, $skip, $timeout) = @_;
  my $msg;
  my $wait_msg;
  my @output;
  my @orig_output;
  my @lines;
  my $cli_errors;
  my $return_msg;

  my $prompt = $hprompts{xr_normal};

  if ($cmd =~ /^commit$/ || $cmd =~ /^commit best-effort/) {
    $prompt = $hprompts{xr_standard};
  }

  $session->Net::Telnet::print($cmd);
  if ($timeout) {
    @output = $session->Net::Telnet::waitfor(-Match => $prompt, -Timeout => $timeout, -Errmode => 'return');
  } else {
    @output = $session->Net::Telnet::waitfor(-Match => $prompt, -Errmode => 'return');
  }
  if ($hglobal{verbose} && $hglobal{rdump}) { print "\n"; }

  @lines = split /\n/, $output[0];
  splice(@output,0);
  @output = @lines;
  splice(@lines,0);
  @orig_output = @output;
  if ($#output <= 0) {
    @lines = split /\r/, $output[0];
    splice(@output,0);
    @output = @lines;
  }
  if ($#output <= 0) {
    splice(@output,0);
    @output = @orig_output;
  }

  # Check for errors in CLI command
  if (!$skip) {
    $cli_errors = cli_error_check(@output);
    if ($cli_errors) {
      $msg = "CMD ERROR/FAILED: $cmd\n";

      # Press ENTER/enter key to continue:
      print_box($msg, 0);
      print $ST{redb}, $msg, $ST{reset};
      sleep(3);
      exit;

      if ($return_msg !~ /^y$/i) {
        print $ST{redb}, "Exiting Tool\n", $ST{reset};
        if ($session) { $session->Net::Telnet::cmd(-String=>"exit", -Timeout=>1); }
        if ($session) { $session->close; }
        exit;
      }
    }
  }
  return @output;
} # run_cmd

# -----------------------------------------------------------------------
# Name         : get_date_time
# Purpose      : Provides the current Date and Time
# Returns      : date_time, current_date, current_time
# Notes        : None
# -----------------------------------------------------------------------
sub get_date_time {
  my $month_num;
  my $Eastern;
  my $Eastern_start;
  my $date_time;
  my @month_convert;
  my $current_date;
  my $current_seconds;

  my %month_hash = ('Jan' => 1, 'Feb' => 2, 'Mar' => 3, 'Apr' => 4, 'May' => 5, 'Jun' => 6,
                    'Jul' => 7, 'Aug' => 8, 'Sep' => 9, 'Oct' => 10, 'Nov' => 11, 'Dec' => 12);

  $Eastern_start = gmtime(time-14400);
  $Eastern = gmtime(time-14400) . " EDT";
  $Eastern =~ tr / //s;
  my ($wday, $month, $day, $current_time, $year, $zone) = split(/ /, $Eastern);
  $month_num = $month_hash{$month};

  $current_date = "$month_num-$day-$year";
  $date_time = $current_date . " " . $current_time;
  $current_seconds = time;

  return ($Eastern, $date_time, $current_date, $current_time, $current_seconds);
} # get_date_time

# ----------------------------------------------------------------------------
# Name         : print_box
# Purpose      : Print the outline box with the date and $msg
# Returns      : none
# Notes        : none
# ----------------------------------------------------------------------------
sub print_box {
  my ($msg, $print_handle) = @_;
  my ($Eastern, $date_time, $date, $time, $current_seconds) = get_date_time();
  my $msg2;

  if ($print_handle) {
    $msg2  = '#' x 70 . "\n";
    $msg2 .= "# $Eastern\n";
    $msg2 .= "#\n";
    $msg2 .= "# $msg";
    $msg2 .= '#' x 70 . "\n";
    print {$hglobal{phandle}} $msg2;
  } else {
    print $ST{blueb};
    print '#' x 70 . "\n";
    print "# $Eastern\n";
    print "#\n";
    print "# $msg";
    print '#' x 70 . "\n";
    print $ST{reset};
  }
} # print_box

# ----------------------------------------------------------------------------
# Name         : cli_error_check
# Purpose      : Verify the cli command has no errors or invalid input
# Returns      : 1 if an error/invalid data is detected
# Notes        : none
# ----------------------------------------------------------------------------
sub cli_error_check {
  my (@output) = @_;
  my $result = 0;

  foreach my $line (@output) {
    chomp($line);
    if ($line =~ /Invalid input detected/i) { $result = 1; }
  }
  return $result;
} # cli_error_check

# -----------------------------------------------------------------------
# Name         : verify_router_connectivity
# Purpose      : Verify IP connectivty to the router
# Returns      : $result
# Notes        : None
# -----------------------------------------------------------------------
sub verify_router_connectivity {
  my $router = shift;
  my $result = 1;
  my $msg;
  my @output;
  my $kont = 0;
  my $run = 1;
  my $passed = 0;
  my $total_time = 0;
  my $converted_time;
  my $wait_time = 4;
  my $wait_minutes = 60;
  my $time_check = 0;
  my $end_loop = 0;
  my $attempts = 3;

  my $cmd = "ping -c 2 $router";

  $msg  = "Tool will now verify IPv4 connectivity to the ROUTER ($router) via PINGs (3 attempts)\n";
  if ($hglobal{verbose}) { print $ST{bold}, $msg, $ST{reset}; }
  print {$hglobal{phandle}} $msg;

  while ($run) {
    if (!$attempts) { return 1; }

    splice(@output,0);
    @output = `$cmd`;
    if ($hglobal{verbose}) { print $ST{magentab}, "\n@output\n", $ST{reset}; }
    print {$hglobal{phandle}} "\n@output\n";

    if (@output) {
      if (grep /cannot resolve/i, @output) {
        $msg  = "\nPing test failed, due to router DNS failed lookup\n\n";
        if ($hglobal{verbose}) { print $ST{redb}, $msg, $ST{reset}; }
        print {$hglobal{phandle}} $msg;
        return 1;
      }
      foreach my $line (@output) {
        chomp($line);
        $line = join(" ", split " ", $line);
        if ($line =~ /is alive|bytes from/i) {
          $passed = 1;
        }
      }
    } else {
      $msg = "**WARN: No output for '$cmd'\n";
      if ($hglobal{verbose}) { print $ST{magentab}, $msg, $ST{reset}; }
      print {$hglobal{phandle}} $msg;
    }
    if ($passed) {
        $msg = "IPv4 connectivity to ROUTER ($router) - PASSED\n";
        if ($hglobal{verbose}) { print $ST{bold}, $msg, $ST{reset}; }
        print {$hglobal{phandle}} $msg;
        return 0;
    } else {
      if ($run == 1) {
        $msg = "ROUTER connectivity NOT READY. Sleeping $wait_time seconds\n";
        if ($hglobal{verbose}) { print $ST{bold}, $msg, $ST{reset}; }
        print {$hglobal{phandle}} $msg;
      } else {
        if ($attempts != 1) {
          $converted_time = convert_seconds($total_time);
          $msg = "ROUTER connectivity NOT READY. Sleeping $wait_time seconds. Elapsed time: $converted_time\n";
          if ($hglobal{verbose}) { print $ST{bold}, $msg, $ST{reset}; }
          print {$hglobal{phandle}} $msg;
        }
      }
    }
    $total_time = $total_time + $wait_time;

    if (!$passed) {
      if ($attempts != 1) {
        sleep ($wait_time);
      }
    }
    $time_check = $time_check + $wait_time;
    $run++;
    $attempts--;
  }
  return $result;
} # verify_router_connectivity

# -----------------------------------------------------------------------
# Name         : convert_seconds
# Purpose      : Convert seconds to xdxhxmxs format
# Returns      : none
# Notes        : none
# -----------------------------------------------------------------------
sub convert_seconds {
  my ($sec) = @_;
  my $converted_seconds;

  my $days = int($sec/(24*60*60));
  my $hours = ($sec/(60*60))%24;
  my $mins = ($sec/60)%60;
  my $seconds = $sec%60;

  $converted_seconds =  $days . "d" . $hours . "h" . $mins . "m" . $seconds . "s";
  return $converted_seconds;
} # convert_seconds

# ----------------------------------------------------------------------------
# Name         : display_menu
# Purpose      : Used to display the current menu and step option the tool is
#              : working on and completed
# Returns      : None
# Notes        : None
# ----------------------------------------------------------------------------
sub display_menu {
  my ($current_step, $completed_steps, $to_do_steps, $handle, %hglobal) = @_;
  my $msg;

  if ($hglobal{sw_ver}) {
    $msg  = "Configuration Commit Transfer Tool ($hglobal{sw_ver})\n";
  } else {
    $msg  = "Configuration Commit Transfer Tool\n";
  }
  $msg .= "#\n";

  if ($hglobal{node}) { $msg .= "# Router: $hglobal{node}\n"; }

  $msg .= "#\n";

  if (!$current_step) {   # If $current_step is at 0 then a module has been completed
    $msg .= $completed_steps;
  }
 
  if ($current_step) {
    if (!$completed_steps) {
      $msg .= "# >" . $current_step;
      if ($to_do_steps ne "0") { $msg .= $to_do_steps; }
    } elsif ($to_do_steps) {
      if ($completed_steps ne "0") { $msg .= $completed_steps; }
      $msg .= "# >" . $current_step;
      $msg .= $to_do_steps;
    } elsif (!$to_do_steps) {
      if ($completed_steps ne "0") { $msg .= $completed_steps; }
      $msg .= "# >" . $current_step;
    }
  }
  if ($handle) {
    print $handle $msg;
  } else {
    print_box($msg, 0);
  }
} # display_menu

# -----------------------------------------------------------------------
# Name         : uniquify_array
# Purpose      : Creates a unique array
# Returns      : Returns a unique array
# Notes        : None
# -----------------------------------------------------------------------
sub uniquify_array {
  my @list = @_;
  my %seen = ();
  my @uniqu = grep { ! $seen{$_} ++ } @list;
  return @uniqu;
} # uniquify_array

# -----------------------------------------------------------------------
# Name         : check_commit_failure
# Purpose      : Display the commit failure
# Returns      : $result
# Notes        : None
# -----------------------------------------------------------------------
sub check_commit_failure {
  my $msg = shift;

  run_cmd("show config fail", 1, 15);
  if ($msg) {
    if ($hglobal{verbose}) { print $ST{redb}, $msg, $ST{reset}; }
    print {$hglobal{phandle}} $msg;
  }

  $msg = "Clearing configuration uncommit buffer due to commit failure\n";
  if ($hglobal{verbose}) { print $ST{redb}, $msg, $ST{reset}; }
  print {$hglobal{phandle}} $msg;
  run_cmd("clear", 1);
  run_cmd("end", 1);
} # check_commit_failure

# -----------------------------------------------------------------------
# Name         : mod_xr_telnet
# Purpose      : Telnet to router (IOS-XR)
# Returns      : $result
# Notes        : None
# -----------------------------------------------------------------------
sub mod_xr_telnet {
  my ($global, $ftpinfo, $prompts, $htime, $logdir, $mod) = @_;
  my %hglobal = %{$global};
  my %hftpinfo = %{$ftpinfo};
  my %hprompts = %{$prompts};
  my %htime = %{$htime};
  my $session = 0;
  my ($Eastern, $date_time, $date, $time, $current_seconds);
  my $msg;
  my $result = 0;
  my $wait_time = 30;
  my $connection = 1;
  my $prompt = $hprompts{xr_normal};

  while (!$session) {
    ($Eastern, $date_time, $date, $time, $current_seconds) = get_date_time();
    if ($hglobal{verbose}) { print $ST{bold}, "$Eastern\n", $ST{reset}; }
    print {$hglobal{phandle}} "$Eastern\n";

    $msg = "Attempting TELNET (vty) connection, attempt #$connection\n";
    if ($hglobal{verbose}) { print $ST{bold}, $msg, $ST{reset}; }
    print {$hglobal{phandle}} $msg;
 
    # Re-Login to node/router
    $session = mod_node_login(\%hglobal, \%hftpinfo, \%hprompts, $prompt, 1, 7);
    if ($hglobal{verbose} && $hglobal{rdump}) { print "\n"; }
    $connection++;
 
    # If the connection re-attempts goes beyond 30 then quit tool
    if ($connection >= 30) {
      print $ST{redb}, "Router Telnet (vty) connection attempts beyond the default (30).  Exiting Tool\n", $ST{reset};
      if ($session) { $session->close; }
      $result = 1;
      exit;
    }
    if (!$session) {
      $msg = "Tool sleeping $wait_time seconds between re-connect attempts.\n";
      if ($hglobal{verbose}) { print $ST{bold}, $msg, $ST{reset}; }
      print {$hglobal{phandle}} $msg;
      sleep($wait_time);
    }
  }
  # Verify the router connection was successful
  if ($session) {
    $result = 0;
    # Reset prompt
    $session->prompt($prompt);
    # Reset the node timeout to the default:
    $session->timeout($hglobal{node_timeout});
  } else {
    # Failed router login, exit tool!
    $msg = "Failed to login to router. View the router command log file for further details:\n$hglobal{node_cmd_log}\n";
    print $ST{redb}, $msg, $ST{reset};
    $result = 1;
    exit;
  }
  return ($session, $result);
} # mod_xr_telnet

# ----------------------------------------------------------------------------
# Name         : mod_node_login
# Purpose      : Log into router/node
# Returns      : None
# Notes        : None
# ----------------------------------------------------------------------------
sub mod_node_login {
  my ($hglobal, $hftpinfo, $hprompts, $prompt, $verbose, $loops) = @_;
  my %hglobal = %{$hglobal};
  my %hftpinfo = %{$hftpinfo};
  my %hprompts = %{$hprompts};
  my $default_prompt = '/.*(#|>|:|\))\s*$|(#|>|:|\))\s*$/';
  my $session = 0;
  my $errmsg = 0;
  my $eof;
  my $result;
  my $msg;
  my $buffer_mb = 1024 * 1024;
  my $zero_screen = "term len 0";
  my $wide_screen = "term width 512";
  my $number_retries = $loops;

  if ($number_retries >= 1) { $number_retries = $number_retries - 1; }

  if ($verbose) { print $ST{bold}, "Logging into node: $hglobal{node}\n", $ST{reset}; }

  if (!$loops) { $loops = 1; }
  while ($loops) {
    $loops--;

    if ($hglobal{rdump}) {
      # Login to node
      $session = Net::Telnet->new(
            Host           => $hglobal{node},
            Timeout        => 12,
            Prompt         => $prompt,
            Errmode        => 'return',
            Rdump          => 1,
            Input_log      => $hglobal{node_cmd_log});
    } else {
      # Login to node
      $session = Net::Telnet->new(
            Host           => $hglobal{node},
            Timeout        => 12,
            Prompt         => $prompt,
            Errmode        => 'return',
            Input_log      => $hglobal{node_cmd_log});
    }

    if ($session) {
      $errmsg = $session->Net::Telnet::errmsg;
      if ($errmsg) {
        $msg = "Errmsg: $errmsg\n";
        if ($hglobal{verbose}) { print $ST{redb}, $msg, $ST{reset}; }
      }

      # Disabling the auto login via the session->login and placing this into a if statement for 
      # different scenarios with the NOC and Username login prompts
      if ($session->Net::Telnet::waitfor(
       -match =>'/[Nn][Oo][Cc]:\s*|[Nn][Oo][Cc]\s*:\s*|[Nn][Oo][Cc]:$|[Nn][Oo][Cc]\s*:$/',
       -errmode => "return", -Timeout => 2)) {
        # NOC prompt processing
        $session->Net::Telnet::print("$hftpinfo{user}");
        $session->Net::Telnet::waitfor(-match => '/[Pp]assword: ?$/', -Timeout => 2, -errmode => "return");
        $session->Net::Telnet::print("$hftpinfo{user_pass}");
        $session->Net::Telnet::waitfor(-match => '/.*[#|>]\s*$/', -errmode => "return", -Timeout => 7);
      } elsif ($session->Net::Telnet::waitfor(-match => '/[Uu]sername:\s*$|[Uu]sername.*\s*:\s*$/', -errmode => "return",
       -Timeout => 2)) {
        $session->Net::Telnet::print("$hftpinfo{user}");
        $session->Net::Telnet::waitfor(-match => '/[Pp]assword: ?$/', -Timeout => 2, -errmode => "return");
        $session->Net::Telnet::print("$hftpinfo{user_pass}");
        $session->Net::Telnet::waitfor(-match => '/.*[#|>]\s*$/', -errmode => "return", -Timeout => 7);
      }
      $session->max_buffer_length(5 * $buffer_mb);

      $session->print("$wide_screen");
      $session->Net::Telnet::waitfor(-match => $default_prompt, -Timeout => 30, -Errmode => 'return');
      $session->print("$zero_screen");
      my ($pre, $match) = $session->Net::Telnet::waitfor(-match => $default_prompt, -Timeout => 30, -Errmode => 'return');
      if ($match) {
        $match = join(" ", split " ", $match);
        if ($match =~ /^RP/ && $match =~ /\#$/) {
          if ($verbose && $hglobal{rdump}) { print "\n"; }
          $msg = "Initial login to node: $hglobal{node}\n";
          if ($verbose) { print $ST{bold}, $msg, $ST{reset}; }
        }
      }

      $session->print("term exec prompt no-timestamp");
      $session->Net::Telnet::waitfor(-match  => $default_prompt, -Timeout => 2, -Errmode => 'return');
      $eof = $session->eof;
      if ($eof) {
        # Connection to router failed
        $msg = "Failed to login to router: $hglobal{node}\n";
        print $ST{redb}, $msg, $ST{reset};
        $session->close;
        $session = 0;
        return $session;
      }

      $result = verify_clock($session, $hprompts{xr_normal});
      if ($hglobal{verbose} && $hglobal{rdump}) { print "\n"; }
      if ($result) {
        $msg = "Successful login to node: $hglobal{node}\n";
        if ($verbose) { print $ST{bold}, $msg, $ST{reset}; }
        print {$hglobal{phandle}} $msg;

        # Reset prompt
        $session->prompt($hprompts{xr_normal});
        # Reset the node timeout to the default:
        $session->timeout($hglobal{node_timeout});
        return $session;
      } else {
        if (!$loops) {
          $msg = "FAILED LOGIN\n";
          print $ST{redb}, $msg, $ST{reset};
          $session->close;
          $session = 0;
          return $session;
        }
      }
    }
    if ($loops) {
      if (!$session) { return 0; }
      $session = 0;
      $msg = "Login Failed.  Sleeping for 15 seconds.  Then Tool will try to re-login (total $number_retries).\n";
      print $ST{redb}, $msg, $ST{reset};
      sleep(15);
    }
  }
  return $session;
} # mod_node_login

# -----------------------------------------------------------------------
# Name         : verify_clock
# Purpose      : Used to verify router connection still active/inactive
# Returns      : $result
# Notes        : None
# -----------------------------------------------------------------------
sub verify_clock {
  my ($session, $prompt) = @_;
  my $result = 0;
  my @output;

  @output = $session->Net::Telnet::cmd(-String=> "show clock", -Timeout=> 6, -Prompt=> $prompt);
  foreach my $line (@output) {
    chomp($line);
    $line = join(" ", split " ", $line);
    $line =~ s/\*//;
    if ($line =~ /^\d+:\d+:\d+|^\d:\d+/) { $result = 1; }
    if ($line =~ /^\*\d+:\d+:\d+|^\d:\d+/) { $result = 1; }
  }
  return $result;
} # verify_clock

# ----------------------------------------------------------------------------
# Name         : login_to_router
# Purpose      : Routine to login to remote router
# Returns      : $session
# Notes        : None
# ----------------------------------------------------------------------------
sub login_to_router {
  my $msg;
  my $result = 0;

  ######################
  # Login to node/router
  ######################
  $msg  = "\nTelnet to router ($hglobal{node})\n";
  if ($hglobal{verbose}) { print $ST{bold}, $msg, $ST{reset}; }
  print {$hglobal{phandle}} $msg;

  ($session, $result) = mod_xr_telnet(\%hglobal, \%hftpinfo, \%hprompts, \%htime, $hglobal{logdir}, "ConfigCommitTransfer");
  if ($result || !$session) {
    $msg = "Exiting Tool\n";
    print $ST{redb}, $msg, $ST{reset};
    print {$hglobal{phandle}} $msg;
    exit;
  }
  $msg  = "\nSuccessfully connected to router\n";
  if ($hglobal{verbose}) { print $ST{bold}, $msg, $ST{reset}; }
  print {$hglobal{phandle}} $msg;
 
  return ($session, $result);
} # login_to_router

# -----------------------------------------------------------------------
# Name         : process_router_output
# Purpose      : Process the returned $match from the communication to the router
# Returns      : $value
# Notes        : None
# -----------------------------------------------------------------------
sub process_router_output {
  my ($pre, $match) = @_;
  my @output;
  my @output1;
  my @output2;

  if ($pre) { @output1 = split /\n/, $pre; }
  if ($match) { @output2 = split /\n/, $match; }
  if ($pre && $match) {
    @output = (@output1, @output2);
  } elsif ($pre) {
    @output = @output1;
  } elsif ($match) {
    @output = @output2;
  }
  return (@output);
} # process_router_output

# -----------------------------------------------------------------------
# Name         : process_match
# Purpose      : Process the returned $match from the communication to the router
# Returns      : $value
# Notes        : None
# -----------------------------------------------------------------------
sub process_match {
  my ($match, $process, %hglobal) = @_;
  my $value = "\r";
  my $msg;

  if ($match) {
    if ($hglobal{debug}) { print "DEBUG {process_match:$process} MATCH: $match\n"; }
    # Process the $match request:
    if ($match =~ /\(y\/n\)/) {
      # [confirm(y/n)]
      $value = "y";
      $msg = "{$process}  sending 'y'  {in response to MATCH: $match}\n";
      if ($hglobal{debug}) { print "SSEARCH {process_match} match: y] -or- y]:\n"; }
    } elsif ($match =~ /\[confirm\]/) {
      $value = "\r";
      $msg = "{$process}  sending '<CR>'  {in response to MATCH: $match}\n";
      if ($hglobal{debug}) { print "SSEARCH {process_match} match: [confirm]\n"; }
    } elsif ($match =~ /no\]$/i || $match =~ /no\]:$/i) {
      $value = "yes";
      $msg = "{$process}  sending 'yes'  {in response to MATCH: $match}\n";
      if ($hglobal{debug}) { print "SSEARCH {process_match} match: no] -or- no]:\n"; }
    } elsif ($match =~ /\[no\]/ || $match =~ /\[NO\]/) {
      $value = "yes";
      $msg = "{$process}  sending 'yes'  {in response to MATCH: $match}\n";
      if ($hglobal{debug}) { print "SSEARCH {process_match} match: [no] -or- [NO]\n"; }
    } elsif ($match =~ /n\]$/i || $match =~ /n\]:$/i) {
      $value = "yes";
      $msg = "{$process}  sending 'yes'  {in response to MATCH: $match}\n";
      if ($hglobal{debug}) { print "SSEARCH {process_match} match: n] -or- n]:\n"; }
    } elsif ($match =~ /yes\]$/i || $match =~ /yes\]:$/i) {
      $value = "yes";
      $msg = "{$process}  sending 'yes'  {in response to MATCH: $match}\n";
      if ($hglobal{debug}) { print "SSEARCH {process_match} match: yes] -or- yes]:\n"; }
    } elsif ($match =~ /y\]$/i || $match =~ /y\]:$/i) {
      $value = "y";
      $msg = "{$process}  sending 'y'  {in response to MATCH: $match}\n";
      if ($hglobal{debug}) { print "SSEARCH {process_match} match: y] -or- y]:\n"; }
    } elsif ($match =~ /\]$/i || $match =~ /\]:$/i) {
      $value = "y";
      $msg = "{$process}  sending 'y'  {in response to MATCH: $match}\n";
      if ($hglobal{debug}) { print "SSEARCH {process_match} match: ] -or- ]:\n"; }
    } else {
      $value = "\r";
      if ($hglobal{debug}) { print "SSEARCH {process_match} match: ] -or- ]:\n"; }
      # The $match not determined. Instead send a <CR> as default:
      if (defined $hglobal{phandle}) {
        my $mesg = "{$process}  sending <CR>  {\$match:  $match  Value undetermined. Send default <CR>}\n";
        print {$hglobal{phandle}} $mesg;
      }
    }
  } else {
    $value = "\r";
  }
  return $value;
} # process_match

# -----------------------------------------------------------------------
# Name         : run_cmd_extended
# Purpose      : Run system command with extended user input
# Returns      : @output
# Notes        : None
# -----------------------------------------------------------------------
sub run_cmd_extended {
  my ($response, $prompt, $cmd) = @_;
  my @output;
  my @output1;
  my @router_output;
  my $result = 0;
  my $loop_run = 0;
  my $loop = 1;
  my $data;
  my $prompt2 = $hprompts{xr_normal};

  $session->Net::Telnet::print($cmd);

  my ($pre, $match) = $session->Net::Telnet::waitfor(-match => $prompt, Timeout => 60, -Errmode => 'return');
  if ($hglobal{verbose} && $hglobal{rdump}) { print "\n"; }
  @router_output = process_router_output($pre, $match);
  # Process the $match data and determine the appropriate response:
  if (!$response) {
    $response = process_match($match, "run_cmd_extended", %hglobal);
  }

  $data = $session->Net::Telnet::lastline(-Errmode => 'return', -Timeout => 1);
  if ($match) {
    if ($match =~ /RP\/.*CPU0:.*[#]$/) {
      return($result, @router_output);
    }
  }

  while ($loop) {
    splice(@output1,0);
    if ($response ne "\r") {
      $session->Net::Telnet::print($response);
    } else {
      $session->Net::Telnet::print("");
    }
    ($pre, $match) = 
     $session->Net::Telnet::waitfor(-match => $prompt, -Timeout => 60, -Errmode => 'return');
    if ($hglobal{verbose} && $hglobal{rdump}) { print "\n"; }

    @output1 = process_router_output($pre, $match);
    $response = process_match($match, "run_cmd_extended", %hglobal);
    @router_output = (@router_output, @output1);

    $data = $session->Net::Telnet::lastline(-Errmode => 'return', -Timeout => 1);
    if ($match) { if ($match =~ /RP\/.*CPU0:.*[#]$/) { last; } }
    if ($data =~ /RP\/.*CPU0:.*[#]$/) { last; }

    $loop_run++;
    if ($loop_run == 4) { $loop = 0; }
  }
  $session->Net::Telnet::print("");
  $session->Net::Telnet::waitfor(-match => $prompt2, -Errmode => 'return');

  return ($result, @router_output);
} # run_cmd_extended

# -----------------------------------------------------------------------
# Name         : get_users_password
# Purpose      : Routine is only used if a user enters their entered_username
# Returns      : $pass
# Notes        : None
# -----------------------------------------------------------------------
sub get_users_password {
  my $msg = shift;
  my $pass;

  print $ST{bold}, $msg, $ST{reset};
  # Disable terminal output:
  system("stty -echo");

  $| = 1;
  $pass = <STDIN>;
  chomp($pass);
  # Return terminal back to standard mode:
  system("stty echo");
  print "\n";
  return $pass;
} # get_users_password

# ----------------------------------------------------------------------------------------------------------
# Name         : get_ftpinfo
# Purpose      : Parse for the .ftpinfo file to gather the username/passwords
# Returns      : ($ftp_server, $ftp_user, $ftp_pass, $ftp_path, $user, $user_pass, $enable_pass)
# Notes        : None
# ----------------------------------------------------------------------------------------------------------
sub get_ftpinfo {
  my ($DIR, $verbose) = @_;
  my %hash;
  my $size_of_hash;

  my $msg = "Cannot locate the .ftpinfo file to parse the username/password/enablepassword\n";
  $msg .= "in order to run this script in a production router environment. Please create\n";
  $msg .= "the .ftpinfo file in your home directory or the local script directory. File\n";
  $msg .= "format:\n\n";
  $msg .= "set FTP_USER   \"UNIX user_id\" \n";
  $msg .= "set FTP_PASS   \"UNIX passwd\" \n";
  $msg .= "set RTR_USER   \"TACACS user_id\"  \n";
  $msg .= "set RTR_PASS   \"TACACS passwd\"  \n";

  my $home_dir_ftpinfo = $ENV{"HOME"} . "/.ftpinfo";
  my $local_dir_ftpinfo = $DIR . "/.ftpinfo";
  my $home_dir_ftpinfo2 = $ENV{"HOME"} . "/ftpinfo";
  my $local_dir_ftpinfo2 = $DIR . "/ftpinfo";

  if (-e "$home_dir_ftpinfo") {
    if ($verbose) { print $ST{bold}, "Parsing the users HOME directory .ftpinfo\n", $ST{reset}; }
    ($hash{ftp_user}, $hash{ftp_pass}, $hash{user}, $hash{user_pass}) = read_ftpinfo($home_dir_ftpinfo);
  } elsif (-e "$local_dir_ftpinfo") {
    if ($verbose) { print $ST{bold}, "Parsing the local directory .ftpinfo\n", $ST{reset}; }
    ($hash{ftp_user}, $hash{ftp_pass}, $hash{user}, $hash{user_pass}) = read_ftpinfo($local_dir_ftpinfo);
  } elsif (-e "$home_dir_ftpinfo2") {
    if ($verbose) { print $ST{bold}, "Parsing the users HOME directory ftpinfo\n", $ST{reset}; }
    ($hash{ftp_user}, $hash{ftp_pass}, $hash{user}, $hash{user_pass}) = read_ftpinfo($home_dir_ftpinfo2);
  } elsif (-e "$local_dir_ftpinfo2") {
    if ($verbose) { print $ST{bold}, "Parsing the local directory ftpinfo\n", $ST{reset}; }
    ($hash{ftp_user}, $hash{ftp_pass}, $hash{user}, $hash{user_pass}) = read_ftpinfo($local_dir_ftpinfo2);
  }

  if (!$hash{ftp_user} || !$hash{ftp_pass} || !$hash{user} || !$hash{user_pass}) {
    ($hash{ftp_user}, $hash{ftp_pass}, $hash{user}, $hash{user_pass}) = prompt_user_ftpinfo(%hash);
  }

  return (%hash);
} # get_ftpinfo

# -----------------------------------------------------------------------
# Name         : prompt_user_ftpinfo
# Purpose      : Prompt the user for specific values
# Returns      : %hash
# Notes        : None
# -----------------------------------------------------------------------
sub prompt_user_ftpinfo {
  my %hash;
  ($hash{ftp_user}, $hash{ftp_pass}, $hash{user}, $hash{user_pass}) = @_;
  my $msg;

  print $ST{bold};
  print "\nSome of the Login Credentials are missing or not entered in the .ftpinfo file. Please\n";
  print "enter the following:\n\n";
  print $ST{reset};

  if (!$hash{ftp_user}) {
    $msg = "Enter ftp_user id: ";
    $hash{ftp_user} = prompt_user($msg);
  }
  if (!$hash{ftp_pass}) {
    $msg = "Enter ftp_user passord: ";
    $hash{ftp_pass} = get_users_password($msg);
  }
  if (!$hash{user}) {
    $msg = "Enter router user id: ";
    $hash{user} = prompt_user($msg);
  }
  if (!$hash{user_pass}) {
    $msg = "Enter router user id password: ";
    $hash{user_pass} = get_users_password($msg);
  }
  print "\n";

  return ($hash{ftp_user}, $hash{ftp_pass}, $hash{user}, $hash{user_pass});
} # prompt_user_ftpinfo

# -----------------------------------------------------------------------
# Name         : prompt_user
# Purpose      : Prompt user for data
# Returns      : $data
# Notes        : None
# -----------------------------------------------------------------------
sub prompt_user {
  my $msg = shift;
  my $data;

  print $ST{bold}, $msg, $ST{reset};

  $| = 1;
  $data = <STDIN>;
  chomp($data);
  return $data;
} # prompt_user

# ----------------------------------------------------------------------------------------------------------
# Name         : read_ftpinfo
# Purpose      : Gather the username/passwords
# Returns      : $username $password $enablepassword
# Notes        : None
# ----------------------------------------------------------------------------------------------------------
sub read_ftpinfo {
  my ($read_ftpinfo) = @_;
  my ($ftp_user, $ftp_pass, $user, $user_pass);
  my @contents;
  my @words;

  open (FH, "$read_ftpinfo") || die "Cannot read the .ftpinfo file $read_ftpinfo: $!\n";
  @contents = <FH>;
  close (FH);

  foreach my $line (@contents){
    chomp($line);
    splice(@words,0);
    $line =~ s/\"//g;

    # FTP_USER
    if ($line =~ /FTP_USER/) {
      @words = split(/ /, $line);
      $ftp_user = $words[$#words];
    }
    # FTP_PASS
    if ($line =~ /FTP_PASS/) {
      @words = split(/ /, $line);
      $ftp_pass = $words[$#words];
    }
    # RTR_USER
    if ($line =~ /RTR_USER/) {
      @words = split(/ /, $line);
      $user = $words[$#words];
    }
    # RTR_PASS
    if ($line =~ /RTR_PASS/) {
      @words = split(/ /, $line);
      $user_pass = $words[$#words];
    }
  }
  return ($ftp_user, $ftp_pass, $user, $user_pass);
} # read_ftpinfo

# -----------------------------------------------------------------------
# Name         : start_log
# Purpose      : Routine used to start a logging file
# Returns      : Returns the file handle
# Notes        : 0=new file   1=append
# -----------------------------------------------------------------------
sub start_log {
  my ($append, $log_file) = @_;
  my $handle;

  if (!$append) {
    if (-f $log_file) {
      unlink "$log_file" ||
        warn "** WARNING: Unable to remove old log ($log_file). $! **\n";
    }
  }

  if ($append) {
    open ($handle, ">> $log_file") ||
      warn "** WARNING: Cannot open the logging file: $log_file. $! **\n";
    chmod(0777, $log_file);
  } else {
    open ($handle, "> $log_file") ||
      warn "** WARNING: Cannot open the logging file: $log_file. $! **\n";
    chmod(0777, $log_file);
  }
  return $handle;
} # start_log

# -----------------------------------------------------------------------
# Name         : close_log
# Purpose      : Routine used to close a logging file
# Returns      : none
# Notes        : none
# -----------------------------------------------------------------------
sub close_log {
  my ($handle, $log_file) = @_;

  close ($handle) ||
    warn "** WARNING: Cannot close the logging file: $log_file. $! **\n";
} # close_log

# ----------------------------------------------------------------------------
# Name         : step_display
# Purpose      : Display the individual module step
# Returns      : None
# Notes        : None
# ----------------------------------------------------------------------------
sub step_display {
  my ($current_step, $completed_steps, $to_do_steps, %hglobal) = @_;

  if ($hglobal{verbose}) {
    print "\n";
    display_menu($mod_s1, 0, "#  $mod_s2#  $mod_s3#  $mod_s4#  $mod_s5", 0, %hglobal);
    print "\n";
  }
  if ($hglobal{phandle}) {
    display_menu($mod_s1, 0, "#  $mod_s2#  $mod_s3#  $mod_s4#  $mod_s5", $hglobal{phandle}, %hglobal);
  }
} # step_display


#########################
# main
#########################
if ($#ARGV < 0) {
  usage();
} else {
  cl_parse();
}
my $msg;
if ($hglobal{debug}) { print $ST{redb}, "DEBUGGING Enabled\n", $ST{reset}; }

# If the user entered their username then ask the user for their password:
if ($hglobal{entered_username}) {
  my $msg = "Please enter your password: ";
  $hglobal{password} = get_users_password($msg);
  if (!$hglobal{password}) {
    usage();
  } else {
    $hftpinfo{user}      = $hglobal{entered_username};
    $hftpinfo{user_pass} = $hglobal{password};
  }
  if ($hglobal{verbose}) { print "\n"; }
}


#################################################################
#################################################################
#             Configuration Commit Transfer                     #
#################################################################
#################################################################
my $wait_msg;
my $return_msg;
my @output;


#############################################################################
# Step 1: Verify Server Archive Directories and Create New Archive Directory
#############################################################################
step_display($mod_s1, 0, "#  $mod_s2#  $mod_s3#  $mod_s4#  $mod_s5", %hglobal);

# Verify/Create the logdir
$hglobal{logdir} = "$DIR/logs";
if (! -d "$hglobal{logdir}") {
  if ($hglobal{verbose}) { print $ST{bold}, "Making directory: $hglobal{logdir}\n", $ST{reset}; }
  sleep (1);
  system("mkdir -m 0775 $hglobal{logdir}");
  system("chmod -R 775 $hglobal{logdir}");
  if (! -d "$hglobal{logdir}") {
    print $ST{redb}, "**ERROR: Failed to create LOGDIR, exiting tool:\n";
    print "  $hglobal{logdir}\n", $ST{reset};
    exit;
  }
}

# Verify/Create the node logdir
if (! -d "$hglobal{logdir}/$hglobal{node}") {
  if ($hglobal{verbose}) { print $ST{bold}, "Making directory: $hglobal{logdir}/$hglobal{node}\n", $ST{reset}; }
  sleep (1);
  system("mkdir -m 0775 $hglobal{logdir}/$hglobal{node}");
  system("chmod -R 775 $hglobal{logdir}/$hglobal{node}");
  if (! -d "$hglobal{logdir}/$hglobal{node}") {
    print $ST{redb}, "**ERROR: Failed to create node LOGDIR, exiting tool:\n";
    print "  $hglobal{logdir}\n", $ST{reset};
    exit;
  }
}
$hglobal{logdir} = "$hglobal{logdir}/$hglobal{node}";

($Eastern, $date_time, $date, $time, $current_seconds) = get_date_time();
$htime{mod_start_second} = $current_seconds;
$time =~ s/:/./g;
$htime{start_date} = $date;
$htime{start_time} = $time;

# Create the log files
my $logdir = $hglobal{logdir};
$hglobal{MAIN_LOG} = "$logdir/" . $hglobal{node} . "_ConfigCommitTransfer_"
  . $htime{start_date} . "_" . $htime{start_time} . ".log";
$hglobal{node_cmd_log} = "$logdir/ConfigCommitTransfer_cmd_log_" . $hglobal{node}
  . "_" . $date . "_" . $time . ".log";


$hglobal{phandle} = start_log(0, $hglobal{MAIN_LOG});

my $start_msg  = "\nStarting '$0'  Version: $hglobal{sw_ver}\n\n";
   $start_msg .= "Device: $hglobal{device}\n";
   $start_msg .= "LogDir: $hglobal{logdir}\n";
   $start_msg .= "Verbose: $hglobal{verbose}\n";
   $start_msg .= "Rdump: $hglobal{rdump}\n";

$start_msg .= "\n";
if ($hglobal{verbose}) { print $ST{bold}, $start_msg, $ST{reset}; }
print {$hglobal{phandle}} $start_msg;
sleep(2);

$msg  = "Config Commit Transfer Tool - ASSUMES ROUTER IS RUNNING IOS-XR\n";
if ($hglobal{verbose}) { print_box($msg, 0); }
print {$hglobal{phandle}} $msg;

# Set the current step status:
if ($p_s1) {
  $p_s1 = "$ST{redb}-" . $mod_s1 . "$ST{reset}$ST{blueb}";
} else { $p_s1 = "*" . $mod_s1; }


#############################################################################
# Step 2: Router Login
#############################################################################
step_display($mod_s2, "# $p_s1", "#  $mod_s3#  $mod_s4#  $mod_s5", %hglobal);

if (!$hftpinfo{ftp_user} || !$hftpinfo{ftp_pass} || !$hftpinfo{user} || !$hftpinfo{user_pass}) {
  # Gather the login credentials
  (%hftpinfo) = get_ftpinfo($DIR, $hglobal{verbose});

  if (!$hftpinfo{ftp_user} || !$hftpinfo{ftp_pass} || !$hftpinfo{user} || !$hftpinfo{user_pass}) {
    print $ST{redb}, "\n**ERROR: Failed to capture the necessary login credentials.......Exiting Tool!\n\n", $ST{reset};
    exit;
  }
}


# Set the current step status:
if ($p_s2) {
  $p_s2 = "$ST{redb}-" . $mod_s2 . "$ST{reset}$ST{blueb}";
} else { $p_s2 = "*" . $mod_s2; }



#############################################################################
# Step 3: Lock Configuration Mode
#############################################################################
step_display($mod_s3, "# $p_s1# $p_s2", "#  $mod_s4#  $mod_s5", %hglobal);


# Set the current step status:
if ($p_s3) {
  $p_s3 = "$ST{redb}-" . $mod_s3 . "$ST{reset}$ST{blueb}";
} else { $p_s3 = "*" . $mod_s3; }

#############################################################################
# Step 4: Transfer Archives to Server
#############################################################################
step_display($mod_s4, "# $p_s1# $p_s2# $p_s3", "#  $mod_s5", %hglobal);


# Set the current step status:
if ($p_s4) {
  $p_s4 = "$ST{redb}-" . $mod_s4 . "$ST{reset}$ST{blueb}";
} else { $p_s4 = "*" . $mod_s4; }

#############################################################################
# Step 5: Delete Router Archives
#############################################################################
step_display($mod_s5, "# $p_s1# $p_s2# $p_s3# $p_s4", 0, %hglobal);


# Set the current step status:
if ($p_s5) {
  $p_s5 = "$ST{redb}-" . $mod_s5 . "$ST{reset}$ST{blueb}";
} else { $p_s5 = "*" . $mod_s5; }


#################################################################################
#################################################################################
#################################################################################
#################################################################################
#################################################################################




#################################################################################
# Step 3: Connect to Router
#################################################################################
my ($p_s3_1, $p_s3_2);

$p_s3_1 = verify_router_connectivity($hglobal{device});

if ($p_s3_1) {
  $msg  = "**WARN: Unable to (ping) verify connectivity to $hglobal{device}.\n\n";
  print $ST{redb}, $msg, $ST{reset};
  print {$hglobal{phandle}} $msg;
} else {
  $msg  = "Successfully verified connectivity (ping) to router ($hglobal{device})\n";
  print $ST{bold}, $msg, $ST{reset};
  print {$hglobal{phandle}} $msg;
}

if (!$p_s3_1) {
  ($session, $p_s3_2) = login_to_router();
}

if ($p_s3_1 || $p_s3_2) { $p_s3 = 1; }

# Set the current step status:
if ($p_s3) {
  $p_s3 = "$ST{redb}-" . $mod_s3 . "$ST{reset}$ST{blueb}";
} else { $p_s3 = "*" . $mod_s3; }



#################################################################################
# Configuration Commit Transfer Completed
#################################################################################
step_display(0, "# $p_s1# $p_s2# $p_s3# $p_s4# $p_s5", 0, %hglobal);

$msg = "Completed running Configuration Commit Transfer Tool\n";
if ($hglobal{verbose}) { print $ST{bold}, $msg, $ST{reset}; }
print {$hglobal{phandle}} $msg;

# Determine the time taken to run the module:
my $elapsed_time = time - $htime{mod_start_second};
my $total_elapsed_time = convert_seconds($elapsed_time);

$msg = "Configuration Commit Transfer Tool Completed.  Elapsed Time: $total_elapsed_time\n\n";
if ($hglobal{verbose}) { print $ST{bold}, $msg, $ST{reset}; }
print {$hglobal{phandle}} $msg;

close_log($hglobal{phandle}, $hglobal{MAIN_LOG});

exit;
