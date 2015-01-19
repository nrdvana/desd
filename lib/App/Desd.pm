package App::Desd;
use strict;
use warnings;
use App::Desd::Types;
use Cwd;
use File::Spec::Functions;
use Scalar::Util 'weaken';
use Moo;
use namespace::clean;

# ABSTRACT: Daemonproxy Example Supervisor Daemon

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

has 'base_dir',      is => 'ro', isa => Str, required => 1, default => sub { Cwd::getcwd() };
has 'config_path',   is => 'ro', isa => Str, required => 1, default => sub { './desd.conf.yaml' };
has 'control_path',  is => 'ro', isa => Str, required => 1, default => sub { './desd.control' };

sub config_path_abs {
	my $self= shift;
	rel2abs($self->config_path, $self->base_dir);
}

sub control_path_abs {
	my $self= shift;
	rel2abs($self->control_path, $self->base_dir);
}

=head2 exitcode

AnyEvent asynchronous variable of the exit code of the program.

=cut

has 'exitcode', is => 'lazy', isa => 'CondVar', default => sub { AE::cv };

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
	my @a= ($a =~ /(\d+)/g);
	my @b= ($b =~ /(\d+)/g);
	my $ret;
	while (@a || @b)
		$ret= ((shift @a)||0) <=> ((shift @b)||0)
			and last;
	}
	return $ret;
}

sub exec_daemonproxy {
	my $self= shift;
	
	my $desd_path= rel2abs($0, getcwd());
	# TODO: make daemonproxy_path configurable
	my $daemonproxy_path= `which daemonproxy`;
	
	# chdir to the base_dir, to make sure all our paths work from there
	chdir($self->base_dir)
		or die "chdir(".$self->base_dir."): $!";
	
	# Make sure we can re-exec ourselves and end up back in the same script
	my $desd_ver= `"$desd_path" --version`;
	$? == 0 and ($desd_ver =~ /desd version (\d+\.\d+)/) and $1 eq $self->VERSION
		or die "Can't re-exec desd\n";
	
	# Make sure we can find a valid daemonproxy
	my $version= `"$daemonproxy_path" --version`;
	$? == 0 and ($version =~ /^daemonproxy version (\d+\.\d+\.\d+)/)
		or die "Unrecognized daemonproxy version string from $daemonproxy_path\n";
	_version_compare($1, $self->required_daemonproxy_version) >= 0
		or die "Require daemonproxy version ".$self->required_daemonproxy_version."\n";
	
	# build daemonproxy config
	my @desd_args= '--inner';
	push @desd_args, '--base-dir', $self->base_dir;
	push @desd_args, '--config', $self->config_path
		if $self->config_path ne './desd.conf.yaml';
	push @desd_args, '--socket', $self->control_path
		if $self->control_path ne './desd.control';
	my $config= join('', map { join("\t", @$_)."\n" }
		[ 'service.args',    'desd', $desd_path, @desd_args ],
		[ 'service.fds',     'desd', 'control.event', 'control.cmd', 'stderr' ],
		[ 'service.auto_up', 'desd', 1, 'always' ]
	);
	
	# This is slightly wrong... we just assume the pipe has a large enough buffer
	# to hold our config (which should be less than a page anyway, so no real-world
	# architecture should ever deadlock here)
	my ($pipe_r, $pipe_w)= pipe;
	$pipe_w->print($config);
	close($pipe_w);
	POSIX::dup2(fileno $pipe_r, 0) or die "dup2(stdin)";
	close($pipe_r);
	# exec daemonproxy
	exec($daemonproxy_path, '-c', '-')
		# if that failed, abort
		or die "Failed to exec daemonproxy: $!\n";
}

=head2 run

  $exitcode= $desd->run;

Install signal handlers, and blocks (using AnyEvent) until the program should
terminate.  Performs all startup and shutdown sequences.

=cut

sub run {
	my $self= shift;
	weaken($self);
	local $SIG{TERM}= sub { $self->exitcode->send(0); };
	# TODO: install other signal handlers
	...;
	$self->exitcode->recv;
}

1;
