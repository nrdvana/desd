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
constructor.

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
