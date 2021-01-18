# CCClauncher

Introduction
----------------------------------------------------------------
[CCC = CAC Control Center](https://github.com/duprej/ccc). CAC is an accronym for dedicated Pioneer CD Autochangers.
CCClauncher module is a friendly complement that helps you to use [CCCpivot](https://github.com/duprej/cccpivot) easily.

It's basicaly a single Perl5 script to launch and manage all CCCpivot Node.js processes. This script reads a classical configuration file and needs a datasource.
The datasource can be a CSV file or the CCCweb "autochanger" PostgreSQL table. The datasource describes all changers associated with their hostnames (of a computer).

CCClauncher automaticaly scan the given datasource, filter it with the current hostname and startup all CCCpivot instances associated with this hostname.

This allowing a central configuration of all autochangers shared by many computers accross a company (with file links / NFS).
This Perl script can start, status and stop all your CCCpivot Node.js processes like a standard Linux deamon does (like via systemd).

Files
----------------------------------------------------------------

| File | Description
--- | ---
| /opt/ccclauncher/ | Application directory
| /opt/ccclauncher/launcher.pl | Perl script (managing Node.js processes)
| /opt/ccclauncher/conf/ccclauncher.cfg | Example configuration (INI-like file)
| /opt/ccclauncher/conf/cccchangers.csv | Example CSV Datasource (local list of autochangers to manage)
| /opt/ccclauncher/ccclauncher.service |  systemd unit

Temporary Files
----------------------------------------------------------------
Managed process list is stored in a CSV pid file : /var/run/cccpivot.pids.
```console
root@dellpioneer:/opt/cccpivot# cat /var/run/cccpivot.pids
key;pid;powerGpio
jb1;2942;0
jb2;2943;0
```
Power management
----------------------------------------------------------------
This new feature was added in the 1.1.0 version of this script.
This version add 3 more fields (columns) in the CSV file : powerGpio, powerOn & powerOff.
By assignating a pin number (>0) you can make your Raspberry Pi power on and off the changer via a GPIO pin and a relay. This GPIO number is given to the CCCpivot Node.js process. By this way, is it possible to remotely power-on and power-off the changer directly in the application for saving power when not used.

CCClauncher configuration
----------------------------------------------------------------
Once installed, edit the configuration file /etc/ccclauncher.cfg (INI file).
Then edit the datasource file /etc/cccchangers.csv (CSV file).
Each row of the CSV file is an changer entry :

id;desc;enabled;serialPort;hostname;tcpPort;password;model;bauds;timeout;leftPlayerID;useTLS;powerGpio;powerOn;powerOff

| Entry | description
--- | ---
| id | Changer ID string (few chars), must be unique! 
| desc| Changer description (please avoid special chars).
| enabled | true/false (false = autochanger ignored, no instance launched).
| hostname | Computer hostname string (used to filter between many computers).
| tcpPort | Port number for websocket listening (8000 and more).
| password | Password string. Optional, leave it empty for easy operation.
| model | Changer model string ['v180m','v3000','v3200','v5000'].
| bauds | Serial connection speed.  Can be 4800/9600 on V3000/3200/5000 (check front switches). Must be set at 4800 for V180M (fixed on this model).
| timeout | Serial timeout in seconds, maximum reaction time, advised values : 2 seconds for V3000/3200/5000. 12 seconds for V180M.
| leftPlayerID | Left player ID number (for V3000/3200/5000 - see manual), put 0 for V180M.
| useTLS | Enable TLS (use HTTPS certificate).
| powerGpio | GPIO number on the Raspberry Pi to drive a relay for power on/off the changer. Put 0 if not used.
| powerOn | Put 'true' to auto power on changer when starting instance. Put 'false' if not used.
| powerOff | Put 'true' to auto power off changer when stopping instance. Put 'false' if not used.

Example :

> id;desc;enabled;serialPort;hostname;tcpPort;password;model;bauds;timeout;leftPlayerID;useTLS;powerGpio;powerOn;powerOff
> ac1;Changeur 1 V3000 (Gauche);true;/dev/ttyUSB1;dellpioneer;8000;;v3000;9600;2;1;true;0;false;false
> ac2;Changeur 2 V3000 (Droite);true;/dev/ttyUSB2;dellpioneer;8001;;v3000;9600;2;1;true;0;false;false 
> ac3;Changeur 3 V180M;true;/dev/ttyUSB0;dellpioneer;8002;;v180m;4800;12;0;true;0;false;false

CCClauncher Perl script usage
----------------------------------------------------------------
```console
root@dellpioneer:/opt/ccclauncher# perl launcher.pl toto
ERROR : Parameter toto is unknown.
This script needs a single parameter : [start|status|stop|restart|clean].
Usage : launcher.pl [start|status|stop|restart|clean].
```

```console
root@dellpioneer:/opt/ccclauncher# perl launcher.pl start
CCClauncher 1.0 is starting...
The hostname is dellpioneer.
Datasource is CSV file.
INFO : 2 jukeboxes loaded, 1 ignored.
INFO : No PID file.
INFO : Starting CCCpivot script for ac1 - Changeur 1 (Gauche)... on PID n°2942.
INFO : Starting CCCpivot script for ac2 - Changeur 2 (Droite)... on PID n°2943.
```

```console
root@dellpioneer:/opt/ccclauncher# perl launcher.pl status
CCClauncher 1.0 is displaying status...
INFO : CCCpivot script for ac1 : OK, process is running with PID n°2942.
INFO : CCCpivot script for ac2 : OK, process is running with PID n°2943.
```

```console
root@dellpioneer:/opt/ccclauncher# perl launcher.pl stop
CCClauncher 1.0 is stopping...
INFO : Stopping CCCpivot script for ac1... : OK, process n°2942 as been stopped properly.
INFO : Stopping CCCpivot script for ac2... : OK, process n°2943 as been stopped properly.
```

Installation on Linux (in terminal)
----------------------------------------------------------------
All CCC modules are located in /opt directory by default.

Check you have Perl & CPAN:

```console
perl -v
cpan -v
```

Download the latest version to opt directory:

```console
sudo -- bash  -c 'cd /opt;git clone https://github.com/duprej/ccclauncher'
```

Check :

```console
sudo ls -R /opt/ccclauncher/
```

Install Perl modules:

If you are using a Raspberry Pi or Debian/Ubuntu:

```console
sudo apt-get install -y libconfig-simple-perl libdbi-perl libproc-simple-perl libswitch-perl libtext-csv-perl
sudo cpan -iT String::Util
```
Or install all via CPAN:

```console
sudo cpan -i Config::Simple DBI Proc::Simple String::Util Sys::Hostname Text::CSV Switch
```
Copy the systemd unit file & enable at startup:

```console
sudo cp /opt/ccclauncher/ccclauncher.service /etc/systemd/system/ccclauncher.service
sudo systemctl daemon-reload
sudo systemctl enable ccclauncher
```

Install basic config files:

```console
sudo cp /opt/ccclauncher/conf/* /etc/
```

Create the default log dir:

```console
sudo mkdir /var/log/cccpivot
```

Configure/Personalize theses files:

```console
sudo vi /etc/ccclauncher.cfg
sudo vi /etc/cccchangers.csv
```

Start your CCCpivot processes:

```console
sudo perl /opt/ccclauncher/launcher.pl start
```

Check if your CCCpivot processes are alive:

```console
ps -ef|grep node
```
```console
sudo perl /opt/ccclauncher/launcher.pl status
```

Now you are ready to install or use other modules.