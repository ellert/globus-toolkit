use Globus::GRAM::Error;
use Globus::GRAM::JobState;
use Globus::GRAM::JobManager;

use File::stat;
use Fcntl;

package Globus::GRAM::JobManager::fork;

@ISA = qw(Globus::GRAM::JobManager);

my ($mpirun);

BEGIN
{
    $mpirun = '';
}

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);
    
    bless $self, $class;
    return $self;
}

sub submit
{
    my $self = shift;
    my $cmd;
    my $pid;
    my @job_id;
    my $count;
    my $multi_output = 0;
    my $tag = $ENV{GLOBUS_GRAM_JOB_CONTACT};
    my $format = "x-gass-cache://$tag/dev/std\%s/\%03d";
    my $cache_pgm = "$ENV{GLOBUS_LOCATION}/bin/globus-gass-cache";
    my $description = $self->{JobDescription};
    my $merge_urlname = "x-gass-cache://$tag/dev/stdio_merge";
    my $merge_file = undef;
    my $merge_filename;
    
    chdir $description->directory() or
        return Globus::GRAM::Error::INVALID_DIRECTORY;

    foreach $tuple ($description->environment())
    {
	$CHILD_ENV{@{$tuple}[0]} = @{$tuple}[1];
    }

    if($description->jobtype() eq 'multiple')
    {
	$count = $description->count();
	$multi_output = 1 if $count > 1;
    }
    elsif($description->jobtype() eq 'single')
    {
	$count = 1;
    }
    else
    {
        return Globus::GRAM::Error::JOBTYPE_NOT_SUPPORTED;
    }

    if($multi_output)
    {
	if($description->stdout() eq '/dev/null' &&
           $description->stderr() eq '/dev/null')
	{
            # Don't bother merging to /dev/null
	    $multi_output = 0;
	}
	else
	{
	    system("$cache_pgm -add -n $merge_urlname -t $tag file:/dev/null");

	    chomp($merge_filename = `$cache_pgm -query $merge_urlname`);

	    $merge_file = new IO::File(">$merge_filename");
	}
    }

    for(my $i = 0; $i < $count; $i++)
    {
	if($multi_output)
	{
	    my $out_name = sprintf($format, 'out', $i);
	    my $err_name = sprintf($format, 'err', $i);

	    system("$cache_pgm -add -n $out_name -t $tag file:/dev/null");
	    system("$cache_pgm -add -n $err_name -t $tag file:/dev/null");

	    chomp($job_stdout = `$cache_pgm -query $out_name`);
	    chomp($job_stderr = `$cache_pgm -query $err_name`);

	    $merge_file->print("stdout \"$job_stdout\" 0\n".
	                       "stderr \"$job_stderr\" 0\n");

	}
	else
	{
	    $job_stdout = $description->stdout();
	    $job_stderr = $description->stderr();
	}

	$pid = fork();

	if($pid == 0)
	{
            # forked child
	    %ENV = %CHILD_ENV;

	    close(STDIN);
	    close(STDOUT);
	    close(STDERR);

	    open(STDIN, "<" . $description->stdin());
	    open(STDOUT, ">>$job_stdout");
	    open(STDERR, ">>$job_stderr");

	    if(defined($description->arguments()))
	    {
		exec ($description->executable(),
		      $description->arguments())
		    || die "Error starting program";
	    }
	    else
	    {
		exec ($description->executable())
		    || die "Error starting program";
	    }
	}
	else
	{
	    push(@job_id, $pid);
	}
    }
    $merge_file->close() if defined($merge_file);

    $description->add('jobid', join(',', @job_id));
    return {(job_state => Globus::GRAM::JobState::ACTIVE,
            JOB_ID => join(',', @job_id))};
}

sub poll
{
    my $self = shift;
    my $description = $self->{JobDescription};
    my $state;

    $self->log("polling job " . $description->jobid());
    $_ = kill(0, split(/,/, $description->jobid()));

    if($_ > 0)
    {
	$state = Globus::GRAM::JobState::ACTIVE;
    }
    else
    {
	$state = Globus::GRAM::JobState::DONE;
    }

    $self->_merge_multi_output($state);


    return {(job_state => $state)};
}

sub rm
{
    my $self = shift;
    my $description = $self->{JobDescription};

    $self->log("rm job " . $description->jobid());

    kill(SIGTERM, split(/,/, $description->jobid()));

    sleep(5);
    
    kill(SIGKILL, split(/,/, $description->jobid()));

    return 0;
}

sub _merge_multi_output
{
    my $self = shift;
    my $state = shift;
    my $description = $self->{JobDescription};
    my $tag = $ENV{GLOBUS_GRAM_JOB_CONTACT};
    my $cache_pgm = "$ENV{GLOBUS_LOCATION}/bin/globus-gass-cache";
    my $merge_urlname = "x-gass-cache://$tag/dev/stdio_merge";
    my $merge_filename = `$cache_pgm -query $merge_urlname`;
    my $merge_file;
    my $tmp_merge_file;
    my $stdout;
    my $stderr;
    my ($type, $local_filename, $offset, $stat);
    my $tmpfile;

    if($merge_filename)
    {
	chomp($merge_filename);

	$stdout = new IO::File('>>'.$description->stdout());
	$stderr = new IO::File('>>'.$description->stderr());

	$self->log("mergine stdio");
	$merge_file = new IO::File("<$merge_filename");
	$tmp_merge_file = new IO::File(">$merge_filename.tmp");

	while(<$merge_file>)
	{
	    m/^(stdout|stderr)\s+"([^"]+)"\s+([0-9]+)$/;

	    ($type, $local_filename, $offset) = ($1, $2, $3);

	    $self->log("mergine data from $local_filename");

	    $stat = File::stat::stat($local_filename) or next;
	    $tmpfile = new IO::File("<$local_filename");

            # We want to merge up to the last newline... but if
	    # we're in the DONE state, then we want to poll until
	    # EOF
            do
	    {
		if($stat->size > $offset)
		{
		    my($buffer, $buffersize, $writable);
		    $self->log("$local_filename has grown");

		    # File has grown... merge in new data
		    $buffersize = $stat->size - $offset;
		    $buffersize = 4096 if $buffersize > 4096;

		    $self->log("going to process $buffersize bytes");

		    $tmpfile->seek($offset, SEEK_SET);
		    $tmpfile->read($buffer, $buffersize);

		    $writable = $buffer;

		    # we want to do line buffering, so we'll just
		    # strip off all data after the last newline
		    if($state != Globus::GRAM::JobState::DONE)
		    {
			my (@writable);

			@writable = split(//, $writable);
			while (@writable)
			{
			    $_ = pop(@writable);
			    if($_ eq "\n")
			    {
				push(@writable, "\n");
				last;
			    }
			}
			$writable = join('', @writable);
		    }
		    $self->log("after truncating to last newline, ".
		               "going to process " . length($writable) .
			       " bytes");
		    $offset += length($writable);

		    if($type eq 'stdout')
		    {
			$stdout->print($writable);
		    }
		    else
		    {
			$stderr->print($writable);
		    }
		}
	    }
	    while($state == Globus::GRAM::JobState::DONE &&
		  $offset < $stat->size);
	    $tmpfile->close();
	    $tmp_merge_file->print("$type \"$local_filename\" $offset\n");
	}

	$tmp_merge_file->close();
	$merge_file->close();
	rename("$merge_filename.tmp", $merge_filename);
    }
}

1;
