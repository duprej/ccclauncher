=pod
	CCClauncher Perl script for Linux (init/systemd and others)
	Developped for Pioneer CAC Autochangers application CCCpivot.
	A simple Perl script to launch & manage Node.js CCCpivot processes.
	2018-2021 Jonathan DUPRE <http://www.jonathandupre.fr>
	Licenced under GPLv3
=cut
use constant SCRIPTVERSION => '1.1.2';
use strict;
use warnings;
use v5.10;
use Config::Simple;
use DBI;
use Proc::Simple;
use String::Util qw(trim);
use Switch;
use Sys::Hostname;
use Text::CSV qw(csv);

# ------------------------ GLOBAL VARS ------------------------ 
my $confFileName="/etc/ccclauncher.cfg";
my $pidPivotsFile="/var/run/cccpivot.pids";
my $cfgObj;					#Config simple object (from .cfg file)
my %autochangers;			#Hashtable Datasource (autochangers configuration from CSV or Postgres)
my %processes;				#Hashtable PID file (processes launched)
my $ignoredAutochangers=0;	#Count of ignored (no hostname matching) autochangers from Datasource configuration
my $disabledAutochangers=0;	#Count of disabled autochangers from Datasource configuration
my $counter = 0;			#Generic counter var used in various places


# ------------------------ FUNCTIONS ------------------------ 
# Print script usage if bad parameters given
sub printUsage() {
	print "This script needs a single parameter : [start|restart|status|stop|clean|kill].\n";
	print "Usage : $0 [start|restart|status|stop|clean|kill].\n";
}

# Return false or true if a process number exists.
sub checkPIDExists($) {
	my ($pid)=@_;
	return (-e "/proc/$pid/stat");
}

# Load configuration form local CSV file Datasource
sub loadCsvDs($) {
	my $host = shift;
	my $csvObj = Text::CSV->new();
	$csvObj->sep(';');
	# Open, parse and load CSV File in a row
	my $ref = csv (in => $cfgObj->param('files.csv'), key => "id", headers => "auto", encoding => "UTF-8", sep_char=> ";");
	%autochangers = %$ref;
	# Remove those are not matching the hostname or disabled
	foreach my $key (keys %autochangers) {
		my $jukebox = $autochangers{$key};
		my %jukebox = %$jukebox;
		if ($jukebox{'hostname'} ne $host) {
			delete($autochangers{$key});
			$ignoredAutochangers++; # Counter of ignored lines
		}
		if ($jukebox{'enabled'} ne 'true') {
			delete($autochangers{$key});
			$disabledAutochangers++; # Counter of disabled lines
		}
	}
}

# Load configuration form Postgres DB Datasource
sub loadPgDbDs($) {
	my $return = undef;
	my $host = shift;
	my $dsString = "DBI:Pg:dbname=".trim($cfgObj->param('database.name')).';host='.trim($cfgObj->param('database.host')).';port='.trim($cfgObj->param('database.port'));
	my $dbHandle = DBI->connect($dsString, trim($cfgObj->param('database.user')), trim($cfgObj->param('database.password')),{ RaiseError => 1, AutoCommit => 0 });
	if (defined $dbHandle) {
		$dbHandle->do("SET search_path TO ccc, public");
		my $stHandle = $dbHandle->prepare("SELECT * FROM autochanger ac, autochangermodel acm WHERE ac.model = acm.id ORDER BY ac.id;");
		my $returnValue = $stHandle->execute();
		if ($returnValue < 0) {
			print "ERROR : Problem with the SQL query.\n";
			print "ERROR : ".$DBI::errstr;
		} else {
			my $row;
			while($row = $stHandle->fetchrow_hashref()) {
				if ($row->{'hostname'} ne $host) {
					$ignoredAutochangers++; # Counter of ignored lines
					last;
				}
				if ($row->{'enabled'} ne '1') {
					$disabledAutochangers++; # Counter of disabled lines
					last;
				}
				my %newJB;
				$newJB{'id'} = 'jb'.$row->{'id'};
				$newJB{'desc'} = $row->{'description'};
				$newJB{'tcpPort'} = $row->{'tcpport'};
				$newJB{'serialPort'} = $row->{'serialport'};
				$newJB{'bauds'} = $row->{'bauds'};
				$newJB{'timeout'} = $row->{'timeout'};
				$newJB{'password'} = $row->{'password'};
				$newJB{'model'} = $row->{'type'};
				$newJB{'leftPlayerID'} = $row->{'leftplayerid'};
				$newJB{'useTLS'} = $row->{'usetls'};
				$newJB{'powerGpio'} = $row->{'powergpio'};	# Add power management
				$newJB{'powerOn'} = $row->{'poweron'};
				$newJB{'powerOff'} = $row->{'poweroff'};
				$autochangers{$newJB{'id'}} = \%newJB;
			}
		}
		$return = 1;
		undef $stHandle;
		$dbHandle->disconnect();
	} else {
		print "ERROR : Enable to connect to database.\n";
		print "ERROR : ".$DBI::errstr;
	}
	return $return;
}

# Load current launched processes from PID file
sub loadPidFile() {
	my $csvObj = Text::CSV->new();
	$csvObj->sep(';');
	if (!-e $pidPivotsFile || !-f _ || !-r _ ) {
		print "INFO : No PID file.\n";
			%processes = ();
	} else {
		my $ref = csv (in => $pidPivotsFile, key => "key", headers => "auto", encoding => "UTF-8", sep_char=> ";");
		if (defined $ref) {
			%processes = %$ref;
		}
	}
}

sub execStop() {
	# Get info from PIDs file and stop processes
	loadPidFile();
	if (keys %processes == 0) {
		print "INFO : There is no running process in the PID file. Nothing to stop.\n";
	} else {
		# Stopping processes
		$counter = 0;
		foreach my $key (sort(keys %processes)) {
			my $process = $processes{$key};
			my %process = %$process;
			my $pid = $process{'pid'};
			if (!checkPIDExists($pid)) {
				# Dead process
				printf("ERROR : CCCpivot script for %s : KO, process n°%s is dead.\n",$key,$pid);
				$counter++;
			} else {
				printf("INFO : Stopping CCCpivot script for %s... : ",$key);
				# Existing process, let's try to terminate it
				system("kill -SIGTERM $pid");
				sleep 1; # Wait a little bit.
				# Re-check
				if (checkPIDExists($pid)) {
					printf("KO, process n°%s can't be stopped. Bad user? Try kill method.\n",$pid);
				} else {
					printf("OK, process n°%s has been stopped properly.\n",$pid);
					$counter++;
					# If terminated properly, power off the autochanger if auto-poweroff is set
					if ($process{'powerGpio'} ne "0") {
						printf("INFO : Auto power-off for %s ...\n", $key);
						system("echo \"0\" > /sys/class/gpio/gpio$process{'powerGpio'}/value 2>/dev/null");
					}
				}
			}
		}
		if ($counter == keys %processes) {
			# If all processus terminated, remove PID file.
			system("rm $pidPivotsFile");
		}
	}
}

sub execKill() {
	# Get info from PIDs file and stop processes
	loadPidFile();
	if (keys %processes == 0) {
		print "INFO : There is no running process in the PID file. Nothing to kill.\n";
	} else {
		# Killing processes
		$counter = 0;
		foreach my $key (sort(keys %processes)) {
			my $process = $processes{$key};
			my %process = %$process;
			my $pid = $process{'pid'};
			if (!checkPIDExists($pid)) {
				# Dead process
				printf("ERROR : CCCpivot script for %s : KO, process n°%s is dead.\n",$key,$pid);
				$counter++;
			} else {
				printf("INFO : Killing CCCpivot script for %s... : ",$key);
				# Existing process, let's try to terminate it
				system("kill -SIGKILL $pid");
				sleep 1; # Wait a little bit.
				# Re-check
				if (checkPIDExists($pid)) {
					printf("KO, process n°%s can't be killed. Bad user?\n",$pid);
				} else {
					printf("OK, process n°%s as been killed properly.\n",$pid);
					$counter++;
				}
			}
		}
		if ($counter == keys %processes) {
			# If all processus terminated, remove PID file.
			system("rm $pidPivotsFile");
		}
	}
}

sub execStart() {
	# Determine hostname for filtering
	my $host=(trim($cfgObj->param("general.hostname"))) ? trim($cfgObj->param("general.hostname")) : hostname();
	printf "The hostname is %s.\n", $host;
	# Determine datasource and get data
	switch(my $ds = trim($cfgObj->param('general.datasource'))) {
		case "db" {
			print "Datasource is Postgres database.\n";
			if (loadPgDbDs($host)) {
					print "INFO : Postgres datasource OK.\n";
				} else {
					print "ERROR : Problem with Postgres datasource.\n";
					exit 11;
				}
		}
		case "csv" {
			print "Datasource is CSV file.\n";
			if (!-e $cfgObj->param('files.csv') || !-f _ || !-r _ ) {
				printf "ERROR : Datasource file %s not found or not readable.\n", $cfgObj->param('files.csv');
				exit 2;
			}
			loadCsvDs($host);
		}
		else {
			printf "ERROR : Datasource method '%s' is not valid.\n", $ds;
			exit 5;
		}
	}
	# Check there is something to do
	printf("INFO : %d autochangers loaded, %d disabled, %d ignored.\n", scalar(keys %autochangers),$disabledAutochangers,$ignoredAutochangers);
	if (keys %autochangers == 0) {
		printf "ERROR : There is no jukebox for this host in the datasource.\n";
		exit 6;
	} else {
		# Check if there is no other CCCpivot running...
		loadPidFile();
		if (keys %processes != 0) {
			printf "ERROR : There is still processes lauched in the PID file $pidPivotsFile.\n";
			printf "ERROR : Can't start now. Stop, kill or purge processes before continue.\n";
			exit 9;
		} else {
			open(my $pidFH, '>', $pidPivotsFile) or die "Could not open file '$pidPivotsFile' $!";
			print $pidFH "key;pid;powerGpio\n";
			# Launch one by one.
			foreach my $key (sort(keys %autochangers)) {
				my $jukebox = $autochangers{$key};
				my %jukebox = %$jukebox;
				# Set environment before launching the new process
				$ENV{'CCCID'} = $jukebox{'id'};
				$ENV{'CCCDESC'} = $jukebox{'desc'};
				$ENV{'CCCWSSPORT'} = $jukebox{'tcpPort'};
				$ENV{'CCCSERIAL'} = $jukebox{'serialPort'};
				$ENV{'CCCBAUDS'} = $jukebox{'bauds'};
				$ENV{'CCCDEBUG'} = (trim($cfgObj->param('logs.debug')) eq 'true') ? 1 : 0;
				$ENV{'CCCTIMEOUT'} = $jukebox{'timeout'};
				$ENV{'CCCPASS'} = $jukebox{'password'};
				$ENV{'CCCMODEL'} = $jukebox{'model'};
				$ENV{'CCCLPID'} = $jukebox{'leftPlayerID'};
				 # powerGpio is zero if no power management
				$jukebox{'powerGpio'} //= 0;
				$jukebox{'powerOn'} //= 'false'; 
				$jukebox{'powerOff'} //= 'false';
				$ENV{'CCCPOWERGPIO'} = $jukebox{'powerGpio'};
				if ((trim($jukebox{'useTLS'}) eq 'true')) {
					$ENV{'CCCSSL'} = 1;
					$ENV{'CCCSSLCERT'} = trim($cfgObj->param('ssl.certfile'));
					$ENV{'CCCSSLDIR'} = trim($cfgObj->param('ssl.directory'));
					$ENV{'CCCSSLKEY'} = trim($cfgObj->param('ssl.keyfile'));
					$ENV{'CCCPASSPHR'} = trim($cfgObj->param('ssl.cccpivot'));
				} 
				# Power management
				if ($jukebox{'powerGpio'} ne "0") {
					# If the pin number is positive
					printf("INFO : Configuring GPIO pin %s for %s - %s...\n", $jukebox{'powerGpio'}, $jukebox{'id'}, $jukebox{'desc'});
					# Step 1 - Export
					system("echo $jukebox{'powerGpio'} > /sys/class/gpio/export 2>/dev/null");
					sleep 1; # Wait a little bit.
					# Step 2 - Set direction to output
					system("echo \"out\" > /sys/class/gpio/gpio$jukebox{'powerGpio'}/direction 2>/dev/null");
					if ((exists $jukebox{'powerOn'}) && ($jukebox{'powerOn'} eq 'true')) {
						printf("INFO : Auto power-on for %s - %s...\n", $jukebox{'id'}, $jukebox{'desc'});
						system("echo \"1\" > /sys/class/gpio/gpio$jukebox{'powerGpio'}/value 2>/dev/null");
					}
				} 
				printf("INFO : Starting CCCpivot script for %s - %s...", $jukebox{'id'}, $jukebox{'desc'});
				# Start new Node.js process
				my $proc = Proc::Simple->new();
				my $logFile = $cfgObj->param('logs.directory').'cccpivot_'.$key.'.log';
				$proc->redirect_output($logFile,$logFile);
				$proc->start("node", $cfgObj->param('files.pivot'), $jukebox{'id'}, "> $logFile 2>&1");
				my $pid = $proc->pid;
				printf(" on PID n°%s.\n",$pid);
				if ($jukebox{'powerOff'} eq 'true') {
					# Fill the PIDs CSV-like file, each row = a Node.js process + powerGpio
					print $pidFH "$key;$pid;".$jukebox{'powerGpio'}."\n";
				} else {
					# Do not write the powerGpio (set to 0) if powerOff is disabled
					print $pidFH "$key;$pid;0\n";
				}
			}
			close $pidFH;
		}
	}
}

# ------------------------ PROGRAM ------------------------ 
if ($#ARGV + 1 != 1) {
	printUsage();
	exit 1;
}
switch ($ARGV[0]) {
	case "start" {
		printf "CCClauncher %s is starting...\n", SCRIPTVERSION;
	}
	case "restart" {
		printf "CCClauncher %s is restarting...\n", SCRIPTVERSION;
	}
	case "status" {
		printf "CCClauncher %s is displaying status...\n", SCRIPTVERSION;
	}
	case "stop" {
		printf "CCClauncher %s is stopping...\n", SCRIPTVERSION;
	}
	case "clean" {
		printf "CCClauncher %s is cleaning $pidPivotsFile...\n", SCRIPTVERSION;
	}
	case "kill" {
		printf "CCClauncher %s is killing...\n", SCRIPTVERSION;
	}
	else {
		printf "ERROR : Parameter %s unknown. Check input.\n", $ARGV[0];
		printUsage();
		exit 1
	}
}
# Let's open the configuration file
if (!-e $confFileName || !-f _ || !-r _ ) {
	printf "ERROR : Configuration file %s not found or not readable.\n", $confFileName;
	exit 2;
}
$cfgObj=new Config::Simple();
if (!$cfgObj->read($confFileName)) {
	printf "ERROR : Configuration file %s can't be opened by Config::Simple module.\n", $confFileName;
	print $cfgObj->error();
	exit 3;
}
# Check if some crucial parameters are not missing
foreach (qw/general.datasource logs.debug logs.directory files.pivot files.pid/) {
	if (!trim($cfgObj->param("$_"))) {
		printf "ERROR : The value of '%s' can't be empty in the configuration file %s.\n", $_, $confFileName;
		exit 4;
	}
}
# Apply some new parameters from config file
$pidPivotsFile=$cfgObj->param('files.pid');
# Do some actions according to the first parameter
switch ($ARGV[0]) {
	case "start" {
		execStart();
	}
	case "status" {
		# Get info from PIDs file and check processes
		loadPidFile();
		# Display informations
		if (keys %processes == 0) {
			printf "INFO : There is no running process in the PID file. Nothing to display.\n";
			exit 10;
		} else {
			# Display informations
			foreach my $key (sort(keys %processes)) {
				my $process = $processes{$key};
				my %process = %$process;
				my $pid = $process{'pid'};
				if (checkPIDExists($pid)) {
					printf("INFO : CCCpivot script for %s : OK, process is running with PID n°%s.\n",$key,$pid);
				} else {
					printf("INFO : CCCpivot script for %s : KO, process is dead with PID n°%s.\n",$key,$pid);
				}
			}
		}
	}
	case "stop" {
		execStop();
	}
	case "restart" {
		execStop();
		execStart();
	}
	case "clean" {
		system("rm $pidPivotsFile");
		print "$pidPivotsFile removed.\n";
	}
	case "kill" {
		execKill();
	}
}
exit 0;