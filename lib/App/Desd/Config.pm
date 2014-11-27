package App::Desd::Config;
use Moo;

=head1 SYNOPSIS

  $config= App::Desd::Config->deserialize(file => $path);
  $config= App::Desd::Config->new(\%data);
  
  print $config->service('foo')->args;
  
  $config->serialize(file => $path);
  $config->serialize(data => \my $data);
  $yaml= $config->serialize(yaml => 1);

=head1 CONFIGURATION STRUCTURE

The config file for Desd is YAML-encoded structured data:

=over

=item service NAME:

Defines a service named NAME.

=over

=item env:

A key/value map of environment variables that will be applied for any program
or script that is executed in relation to this service.

Using a value of NULL ("~" in YAML) will remove the variable from the environment.
This can be used to suppress the automatic DESD_* variables.

Desd sets the following variables automatically per-service:

=over

=item DESD_SV_NAME

The NAME of the current service.

=item DESD_SV_PID

The PID of the current service.

=item DESD_COMM_FD

(If enabled) The FD number to use to communicate with Desd.

=item DESD_BASEDIR

The path to the base directory of this Desd instance.

=back

=item action NAME:

Actions describe a thing that you want to do to a service.  Think of them like
methods.  Typical actions are "start", "stop", "restart".  Other common actions
are "reload" or "check".  These are the names you use from desctl to manipulate
the service from the commandline.

An action can be a single string (described below) or a key/value set of the
following:

=over

=item run:

The program to execute.  If you specify a string and it contains shell meta
characters it will be passed off to the shell.  If it contains whitspace it
will be split directly and passed to exec(), with automatic argv0.  If you
specify an array it will be pased to exec() with automatic argv0.

=item argv0:

If you need to override argv[0] in the call to run, specify this parameter.

=item io:

The array of file descriptors to pass to the program.  These are named handles,
as defined in the rest of your desd configuration.  The default is to use the
handles defined for the service, which default to [ null, log, log, desd_comm ],
where log is the logger for this service and desd_comm is the control socket
for this service to make API requests to desd.

=item env:

Like the service's env, this alters the environment of any script executed
by this action.

=item set-mode:

Change the mode of the service at the start of this action.  Modes are
'up', 'down', 'once', or "cycle".  (more might be added later)

=back

Some actions have special defaults:

=over

=item start

This action has a default 'io' of [null, log, log].
(the "desd_comm" handle on FD 3 is not present.)  This is because most start
scripts probably don't need it, and it would be a waste to leave that socket
open for the entire duration of the service.

It also has a default "set-mode" of "up", so that the service gets restarted
if it dies.

=item stop

This action has a default "set-mode" of "down", so that the service no longer
gets restarted.

It has a default "killscript" of "SIGTERM SIGCONT 30 SIGTERM 20 SIGQUIT 5 SIGKILL".
Note that if you don't want the killscript, you need to set it to null in
addition to adding your "run" parameters.

=item restart

This action has "set-mode" of "cycle".  This has the effect of running the stop
action if it was running, and then running the start action.

=back

=back

=back

=head1 METHODS

=head2 new

Standard Moo constructor.  Warns about unknown arguments.

=head2 deserialize

  $config= App::Desd::Config->deserialize(file => $path);
  $config= App::Desd::Config->deserialize(yaml => $yaml);

Load a config from some serialized form.  If loading from file,
the format will be auto-detected.  The only format right now
is YAML.

Calls L<new> and returns an object.

=head2 serialize

  my $result= $config->serialize( %options )

  $config->serialize(file => $path);
  my $data= $config->serialize(data => 1);
  my $yaml= $config->serialize(yaml => 1);
  $config->serialize(yaml => \my $yaml);

Serialize the configuration, either to yaml, to raw data, or
to a file (in yaml format).  Options can be:

=over

=item data

The value of this key is either 1 (meaning return the data) or a scalar ref
which receives the data.  The data returned is an un-blessed perl data
structure, which could be passed to 'new' to clone this config.

=item yaml

The value of this key is either 1 (meaning return the yaml) or a scalar ref
which receives the yaml.  The yaml text can be passed to L<deserialize> to
clone this config.

=item file

The value of this key is a file name, which will be overwritten with the YAML
serialization of the config.

=back

=head2 service

  $svc= $config->service("Foo");

Return the configuration for the named service, or undef if it doesn't exist.

See L<App::Desd::Config::Service>

=head2 events

Arrayref of L<App::Desd::Config::Event>

=head2 control

  for (@{ $config->control }) {
    create_socket($_->socket) if defined $_->socket;
  }

Array of L<App::Desd::Config::Control> which holds details about how clients
can connect to Desd and control services.

=cut