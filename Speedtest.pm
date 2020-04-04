package Smokeping::probes::Speedtest;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::Speedtest>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::Speedtest>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use IPC::Open3;
use Symbol;
use Carp;
use Sys::Syslog qw(:standard :macros);;
use Fcntl qw(:flock SEEK_END);

sub pod_hash {
    return {
        name => <<DOC,
Smokeping::probes::Speedtest - Execute tests via Speedtest.net
DOC
        description => <<DOC,
This tool has been modified according to Adrian Popa Smokeping::probes::speedtest L<https://github.com/mad-ady/smokeping-speedtest>.

Integrates L<speedtest|https://www.speedtest.net/apps/cli> as a probe into smokeping. The variable B<binary> must
point to your copy of the speedtest program. If it is not installed on
your system yet, you should install the latest version from L<https://github.com/sivel/speedtest-cli>.

You can ask for a specific server (via the server parameter) and record a specific output (via the measurement parameter).

DOC
        authors => <<'DOC',
Prakai Nadee <prakai.na@gmail.com>
DOC
    };
}

#Set up syslog to write to local0
openlog("speedtest", "nofatal, pid", "local0");
#set to LOG_ERR to disable debugging, LOG_DEBUG to enable debugging
setlogmask(LOG_MASK(LOG_ERR));
 
sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
        
        #check for dependencies
        my $call = "$self->{properties}{binary} --version";
        my $return = `$call 2>&1`;
        if ($return =~ /([0-9\.]+)/){
            syslog("debug", "[Speedtest] Init: version $1");
        } else {
            croak "ERROR: output of '$call' does not return a meaningful version number. Is Ookla speedtest installed?\n";
        }
    };

    return $self;
}

sub ProbeDesc($) {
    return "Bandwidth testing using speedtest.net CLI tool";
}

sub probevars {
    my $class = shift;
    return $class->_makevars($class->SUPER::probevars, {
        _mandatory => [ 'binary' ],
        binary => { 
            _doc => "The location of your Ookla speedtest binary.",
            _example => '/usr/bin/speedtest',
            _sub => sub { 
                my $val = shift;
                    return "ERROR: Ookla speedtest 'binary' does not point to an executable"
                            unless -f $val and -x _;
                return undef;
            },
        },
    });
}

sub targetvars {
    my $class = shift;
    return $class->_makevars($class->SUPER::targetvars, {
        server => { _doc => "The server id you want to test against (optional). If unspecified, speedtest.net will select the closest server to you. The value has to be an id reported by the command speedtest --servers",
                _example => "1234",
        },
        measurement => { _doc => "What output do you want graphed? Supported values are: latency, download, upload",
                    _example => "download",
        },
    extraargs => { _doc => "Append extra arguments to the speedtest comand line",
                    _example => "--interface=ARG --ip=ARG",
        },
    });
}

sub ProbeDesc($){
    my $self = shift;
    return "speedtest.net download/upload speeds";
}

sub ProbeUnit($){
    my $self = shift;
    #TODO: We need to know if we are measuring bps or seconds - depending on measurement (or maybe on probe name).
    return "bps";
}

sub lock {
    my ($fh) = @_;
    flock($fh, LOCK_EX);
    seek($fh, 0, SEEK_END);
}

sub unlock {
    my ($fh) = @_;
    flock($fh, LOCK_UN);
}

sub pingone ($){
    my $self = shift;
    my $target = shift;

    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;

    my $step = $target->{vars}{step} || (60*5); # default result cache time is 5 minutes
    my $server = $target->{vars}{server} || undef; #if server is not provided, use the default one recommended by speedtest.
    my $measurement = $target->{vars}{measurement} || "download"; #record download speeds if nothing is returned
    my $extra = $target->{vars}{extraargs} || ""; #append extra arguments if neded
    my $query = "$self->{properties}{binary} --accept-license --progress=no ".((defined($server))?"--server-id $server":"")." $extra 2>&1";

    my @times;

    $self->do_debug("query=$query\n");
    syslog("debug", "[Speedtest] query=$query");

    my $lockfile = "/tmp/smokeping-speedtest-lock";
    open(my $lfh, ">>", $lockfile);
    lock($lfh);

    my $text = '';
    my $tmpfile = "/tmp/smokeping-speedtest-$server.txt";
    my $tmpexists = 0;

    if (-e $tmpfile) {
        $tmpexists = 1;
    }
    if ($tmpexists != 0) {
        my $mt = (stat($tmpfile))[9];
        my $t = time;
        $self->do_debug("current time=$t, cache modify time=$mt, diff=".($t-$mt)."\n");
        syslog("debug", "[Speedtest] current time=$t, cache modify time=$mt, diff=".($t-$mt));
        if ((time - $mt) > ($step - 30)) {
            $tmpexists = 0;
        }
    }
    if ($tmpexists != 0) {
        $self->do_debug("The cache file is fresh\n");
        syslog("debug", "[Speedtest] The cache file is fresh");
        open(my $fh, '<', $tmpfile);
        while (my $line = <$fh>) {
           $text = $text.$line;
        }
        close $fh;
    }
    if ($tmpexists == 0) {
        $self->do_debug("The cache file has expired\n");
        syslog("debug", "[Speedtest] The cache file has expired");
        my $pid = open3($inh,$outh,$errh, $query);
        while (<$outh>) {
            $self->do_debug("output: ".$_);
            syslog("debug", "[Speedtest] output: ".$_);
            $text = $text.$_;
        }
        waitpid $pid,0;
        close $errh;
        close $inh;
        close $outh;
    }
    my @text = split /[\r\n]/, $text;
    my ($w, $value, $unit);
    while (@text) {
        my $line = shift @text;

        #sample output:
        #   Latency:     3.74 ms   (0.02 ms jitter)
        #   Download:   931.01 Mbps (data used: 1.3 GB)                               
        #     Upload:   939.59 Mbps (data used: 422.2 MB)

        if ($line =~ m/Latency/) {
            if ($line =~ m/$measurement/i) {
                ($w, $value, $unit) = split /([0-9\.]+) ([A-Za-z]+) /, $line;
            }
            ($w, $value, $unit) = split /([0-9\.]+) ([A-Za-z]+) /, $line;
            if ($tmpexists == 0) {
                open(my $fh, '>', $tmpfile);
                print $fh "$line\n";
                close $fh;
            }
        }
        if ($line =~ m/Download/) {
            if ($line =~ m/$measurement/i) {
                ($w, $value, $unit) = split /([0-9\.]+) ([A-Za-z]+) /, $line;
            }
            if ($tmpexists == 0) {
                open(my $fh, '>', $tmpfile);
                print $fh "$line\n";
                close $fh;
            }
        }
        if ($line =~ m/Upload/) {
            if ($line =~ m/$measurement/i) {
                ($w, $value, $unit) = split /([0-9\.]+) ([A-Za-z]+) /, $line;
            }
            if ($tmpexists == 0) {
                open(my $fh, '>>', $tmpfile);
                print $fh "$line\n";
                close $fh;
            }
        }
    }

    unlock($lfh);
    close $lfh;
    unlink $lockfile;

    #sample output:
    #   Latency:     3.74 ms   (0.02 ms jitter)
    #   Download:   931.01 Mbps (data used: 1.3 GB)                               
    #     Upload:   939.59 Mbps (data used: 422.2 MB)
            
    #normalize the units to be in the same base.
    my $factor = 1; 
    $factor = 0.001 if($unit eq 'ms');
    $factor = 1_000 if($unit eq 'Kbps' || $unit eq 'Kibps' || $unit eq 'kbps');
    $factor = 1_000_000 if($unit eq 'Mbps' || $unit eq 'Mibps' || $unit eq 'mbps');
    $factor = 1_000_000_000 if($unit eq 'Gbps' || $unit eq 'Gibps' || $unit eq 'gbps');
            
    my $normalizedvalue = $value * $factor;
    $self->do_debug("Got value: $value, unit: $unit -> $normalizedvalue\n");
    syslog("debug","[Speedtest] Got value: $value, unit: $unit -> $normalizedvalue\n");
            
    push @times, $normalizedvalue;

    #we run only one test (in order not to get banned too soon), so we ignore pings and have to return the correct number of values. Uncomment the above for loop if you want the actual testing to be done $ping times.
    my $value = $times[0];
    @times = ();
    for(my $run = 0; $run < $self->pings($target); $run++) {
        push @times, $value;
    }
    
    @times = map {sprintf "%.10e", $_ } sort {$a <=> $b} grep {$_ ne "-"} @times;

    $self->do_debug("time=@times\n");
    syslog("debug", "[Speedtest] time=@times");
    return @times;
}
1;
