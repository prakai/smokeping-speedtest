# smokeping-speedtest
Smokeping::probes::Speedtest

This tool has been modified according to Adrian Popa Smokeping::probes::speedtest (https://github.com/mad-ady/smokeping-speedtest)

Integrates Ookla speedtest command line (https://www.speedtest.net/apps/cli) as a probe into smokeping. The variable "binary" must
point to your copy of the speedtest program. If it is not installed on
your system yet, you should install the latest version from https://www.speedtest.net/apps/cli. 
Note that tested version of speedtest is 1.0.0.2.

The Probe asks for the given resource one time, ignoring the pings config variable (because pings can't be lower than 3).

You can ask for a specific server (via the server parameter) and record a specific output (via the measurement parameter).

To prevent from multiple speedtest forks process: We using caching technique to cache the latest result to file. The expiration time of the results caching depends on the step parameter.

Parameters:

* binary => The location of your speedtest binary (/usr/bin/speedtest).
* server => The server id you want to test against (optional). If unspecified, speedtest.net will select the closest server to you. The value has to be an id reported by the command speedtest --servers
* measurement => What output do you want graphed? Supported values are: latency, download, and upload
* extraargs => Extra arguments to send to speedtest: --interface=ARG --ip=ARG

Installation:

The Speedtest.pm should be copied into your smokeping installation directory - for instance here: /usr/share/perl5/Smokeping/probes/

Logging:

You can get logs of what goes on inside the plugin either by running smokeping with --debug, or by changing this line:
```
  #set to LOG_ERR to disable debugging, LOG_DEBUG to enable it
  setlogmask(LOG_MASK(LOG_ERR));
```
  
  to
  
```
  #set to LOG_ERR to disable debugging, LOG_DEBUG to enable it
  setlogmask(LOG_MASK(LOG_DEBUG));
```
  
After doing this (and restarting smokeping), the plugin's logs will go to syslog, local0.debug. You will need something like 
```
  local0.*     /var/log/speedtest.log
```
in your syslog configuration, and restart syslog service.


Example probe configuration (poll every hour):
```

### Add this to your Probes file in conf.d folder

+ Speedtest
binary = /usr/bin/speedtest
timeout = 300
step = 3600
offset = random
pings = 3

++ Speedtest-download
measurement = download

++ Speedtest-upload
measurement = upload

### Add these to your Targets file.

++++ download_from_cat_telecom_thailand
menu = Download speed from CAT Telecom Public Company Limited
title = Download speed from CAT Telecom Public Company Limited
probe = Speedtest-download
server = 13871
measurement = download
host = Any word (or host fqdn/not necessary) 

++++ upload_to_cat_telecom_thailand
menu = Upload speed to CAT Telecom Public Company Limited
title = Upload speed to CAT Telecom Public Company Limited
probe = Speedtest-upload
server = 13871
measurement = upload
host = Any word (or host fqdn/not necessary) 
```
