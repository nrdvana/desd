package App::Desd;
use strict;
use warnings;
use AnyEvent;
use App::Desd::Types -types;
use IO::Handle;
use Cwd 'getcwd';
use File::Spec::Functions 'rel2abs', 'file_name_is_absolute';
use Scalar::Util 'weaken';
use Moo;
use namespace::clean;

# ABSTRACT: Daemonproxy Example Supervisor Daemon

our $VERSION= '0.000000';

=head1 SYNOPSIS

  use App::Desd;
  exit App::Desd->new(%attrs)->run;
  # -or-
  exit App::Desd->new(\@ARGV)->run;

=head1 DESCRIPTION

Daemonproxy is a platform for building supervision tools.  This supervisor
is primarily an example of how to write a supervision tool using daemonproxy.
However, it is also a very handy little tool.  And since it's perl, you can
subclass it easily!

desd is event-driven, using AnyEvent, and accepts requests on a unix socket.
Future enhancements might add an HTTP protocol handler that lets you control
jobs as a sort of web service.

=head1 CONSTRUCTION

Desd is built with Moo, and accepts a hash of attribute names for its
constructor.  Most of desd is meant to be run behind an instance of daemonproxy.
However you can also construct an App::Desd object to start daemonproxy for you
via the L</exec_daemonproxy> method.

=head1 ATTRIBUTES

=head2 base_dir

The root directory for Desd to run in.  Will chdir to this path at start of
run() and when re-loading config file.

=head2 config_path

The config file to read on startup.  Defaults to "./desd.conf.yaml".

=head2 control_path

The control socket for desd.  Defaults to "./desd.control".  This path will be
overwritten, and cannot be occupied by anything other than a socket owned by the
same uid/gid of desd, for security reasons.

If the value is the empty string, it means desd won't create any admin
control socket.  (and requests must be through signals or changes to the config file)

=cut

sub required_daemonproxy_version { '1.1.0' }
sub config_path_default { './desd.conf.yaml' }
sub control_path_default { './desd.control' }

has 'base_dir',      is => 'ro', required => 1, default => sub { getcwd() };
has 'config_path',   is => 'ro', required => 1, default => sub { shift->config_path_default };
has 'control_path',  is => 'ro', required => 1, default => sub { shift->control_path_default };

sub config_path_abs {
	my $self= shift;
	rel2abs($self->config_path, $self->base_dir);
}

sub control_path_abs {
	my $self= shift;
	rel2abs($self->control_path, $self->base_dir);
}

has 'desd_path',        is => 'rw', default => sub { rel2abs($0) };
has 'daemonproxy_path', is => 'rw', default => sub { chomp(my $f= `which daemonproxy`) };

=head2 daemonproxy

Protocol object for communicating with Daemonproxy.

=cut

has 'daemonproxy', is => 'rw';

=head2 exitcode

AnyEvent asynchronous variable of the exit code of the program.

=cut

has 'exitcode', is => 'lazy', isa => CondVar, default => sub { AE::cv };

sub BUILD {
	my $self= shift;
	file_name_is_absolute($self->base_dir) and -d $self->base_dir
		or die "base_dir must be an absolute path to an existing directory\n";
	my $cfg_path= $self->config_path_abs;
	-f $cfg_path
		or die "config file '$cfg_path' does not exist\n";
}

=head1 METHODS

=head2 exec_daemonproxy

  $desd->exec_daemonproxy # never returns

Execs into an instance of daemonproxy, which in turn re-calls the desd script.
Fails if it can't find a high enough version of daemonproxy.

=cut

sub _version_compare {
	my @a= ($_[0] =~ /(\d+)/g);
	my @b= ($_[1] =~ /(\d+)/g);
	my $ret;
	while (@a || @b) {
		$ret= ((shift @a)||0) <=> ((shift @b)||0)
			and last;
	}
	return $ret;
}

sub exec_daemonproxy {
	my $self= shift;
	
	# Get absolute paths to programs before changing directories
	my $desd_path= $self->desd_path;
	-x $desd_path or die "Can't locate 'desd' (not executable: '$desd_path')\n";
	my $daemonproxy_path= $self->daemonproxy_path;
	-x $daemonproxy_path or die "Can't locate 'daemonproxy' (not executable: '$daemonproxy_path')\n";
	chomp(my $env_path= `which env`);
	-x $env_path or die "Can't locate 'env' (not executable: '$env_path')\n";
	
	# chdir to the base_dir, to make sure all our paths work from there
	chdir($self->base_dir)
		or die "chdir(".$self->base_dir."): $!";
	
	# Make sure we can re-exec ourselves and end up back in the same script
	my $desd_ver= `"$desd_path" --version`;
	($desd_ver =~ /desd version (\d+\.\d+)/)
		or die "Can't re-exec desd ('$desd_path')\n";
	$1 eq $self->VERSION
		or die "'$desd_path' seems to be different version\n";
	
	# Make sure we can find a valid daemonproxy
	my $version= `"$daemonproxy_path" --version`;
	($version =~ /^daemonproxy version (\d+\.\d+\.\d+)/)
		or die "Unrecognized daemonproxy version string from $daemonproxy_path\n";
	_version_compare($1, $self->required_daemonproxy_version) >= 0
		or die "Require daemonproxy version ".$self->required_daemonproxy_version."\n";
	
	# determine args to re-exec desd.  Only include values which are not the default
	my @desd_args= ('--control=3');
	push @desd_args, '--base-dir', $self->base_dir;
	push @desd_args, '--config', $self->config_path
		if $self->config_path ne $self->config_path_default;
	push @desd_args, '--socket', $self->control_path
		if $self->control_path ne $self->control_path_default;
	
	# Build configuration commands for daemonproxy
	my $config= join('', map { join("\t", @$_)."\n" }
		[ 'service.args',    'desd', $desd_path, @desd_args ],
		[ 'service.fds',     'desd', 'null', 'stdout', 'stderr', 'control.socket' ],
		[ 'service.auto_up', 'desd', 1, 'always' ]
	);
	
	# This is slightly wrong... we just assume the pipe has a large enough kernel buffer
	# to hold our config (which should be less than a page anyway, so no real-world
	# architecture should ever deadlock here)
	# Then we set this pipe to be daemonproxy's stdin
	pipe(my ($pipe_r, $pipe_w)) or die "pipe: $!";
	$pipe_w->print($config);
	close($pipe_w);
	require POSIX;
	POSIX::dup2(fileno $pipe_r, 0) or die "dup2(stdin): $!";
	close($pipe_r);
	
	# exec daemonproxy
	exec($daemonproxy_path, '-c', '-')
		# if that failed, abort
		or die "Failed to exec daemonproxy: $!";
}

=head2 run_as_controller

  $exitcode= $desd->run;

Install signal handlers, and blocks (using AnyEvent) until the program should
terminate.  Performs all startup and shutdown sequences.

Assumes STDIN is the daemonproxy communication socket.

=cut

sub run_as_controller {
	my $self= shift;

	# Install signal handlers
	weaken($self);
	local $SIG{TERM}= sub { $self->exitcode->send(0); };
	
	# Create Daemonproxy protocol object
	require AnyEvent::Handle;
	my $dp_handle= AnyEvent::Handle->new(fh => \*STDIN);
	my $dp= Daemonproxy::Protocol->new(handle => $dp_handle);
	$self->daemonproxy($dp);
	
	# Begin a statedump and start running
	# This will suspend all callbacks and then resume them once the statedump
	#  is complete, which will also initialize the callbacks for us.
	$self->begin_resync;
	
	# Run the AnyEvent main loop for the rest of the program
	$self->exitcode->recv;
}

sub begin_resync {
	my ($self)= @_;
	
	# remove triggers from daemonproxy protocol object
	...;
	# wipe the daemonproxy state
	$self->daemonproxy->reset();
	
	# then start a satatedump
	weaken($self);
	$self->daemonproxy->on_event(sub { $self->continue_resync if $_[0][0] eq 'statedump_complete' });
	$self->daemonproxy->async_send('statedump');
	$self->daemonproxy->async_send('echo', 'statedump_complete');
}

sub continue_resync {
	my $self= shift;
	weaken $self;
	
	# Restore normal event handler
	$self->daemonproxy->on_event(sub { $self->handle_event($_[0]) });

	# Queue processing for any pending signals
	for ($self->daemonproxy->pending_signals) {
		my $signal= $_;
		$self->queue_coderef(sub { $self->reconcile_signal($sig); });
	}
	
	# Queue processing for every service, configured or persistent
	# It shouldn't actually hurt to reconcile a service twice, but the list will
	# be almost entirely redundant if this controller gets restarted.
	my %seen;
	for (grep { !$seen{$_}++ } ($self->config->service_name_list, $self->daemonproxy->service_name_list)) {
		my $svname= $_;
		$self->queue_coderef(sub { $self->reconcile_service($svname) });
	}
}

sub reconcile_signal {
	my ($self, $signame)= @_;
	# clear signal
	# perform configured action for signal
}

sub reconcile_service {
	my ($self, $svname)= @_;
	my $cfg= $self->config->service($svname)->action('start');
	my $sv= $self->daemonproxy->service($svname);
	if ($cfg) {
		# If configured and doesn't exist, create it
		# Change args/fds if they don't match
		$sv->set_arguments(@{ $cfg->run });
		$sv->set_handles(@{ $cfg->io });
		$sv->set_tag_values(want => 'up') if $cfg->want_up;
		$sv->start if $cfg->want_up and !$sv->is_running;
	}
	else if ($sv->exists) {
		# if exists and not configured, remove it unless it is running
		$sv->delete unless $sv->is_running;
	}
	# start it if it is tagged as up and isn't
	# stop it if it is tagged as down and isn't
}

sub queue_coderef {
	my ($self, $todo)= @_;
	push @{$self->{coderef_queue}}, $todo;
	weaken($self);
	$self->{_next_coderef_callback} ||= AE::idle sub {
		my $coderef_queue= $self->{coderef_queue};
		(shift @$coderef_queue)->()
			if @$coderef_queue;
		delete $self->{_next_coderef_callback}
			unless @$coderef_queue;
	};
}

1;
