package App::Desd::Manual::ConfigFile;

# ABSTRACT: Config file YAML structure documentation

=head1 DESCRIPTION

The config file for Desd is YAML-encoded structured data.  The top level must always
be a map.  The following keys are recognized:

=head2 service NAME

Defines a service named NAME.  A service is always defined as a map.  The following
keys are recognized:

=head3 env

  env:
    SHELL: /bin/bash
	PATH: /usr/bin:/usr/local/bin

A map of environment variables that will be applied for any program
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

=head3 goal

  goal: up

Specifies the initial goal for the service.  Each service has a goal which is one of:

=over

=item up

If the service is not running, keep executing the start action until it is.

=item down

If the service is running, keep executing the stop action until it exits.

=item once

If the service is not running, start it.  When it stops for any reason, change the
goal to 'down'.

=item cycle

If the service is running, run the stop action until it exits.  Once it stops
(or if it was initially down) change the goal to 'up', and proceed normally.

=back

=head3 run

  run: "command"
  run: "command && command"
  run: [ 'command', '--arg1', 'option with spaces' ]
  run: { exec: [ 'busybox', 'args' ], argv0: 'ls' }

Specifies the program to execute.  Can be specified as a map, an array, or a
string.  If you specify a string and it contains shell meta characters it will
be passed to '-c' of $SHELL (or /bin/sh if $SHELL is unset).

If you specify an array it is interpreted as arguments to exec(), though argv0
is implied.  If you need to change argv0, use the map form where you can specify
argv0.

=head3 io

  io: null stderr stderr
  io: null null null
  io: [ desd_comm, log, log ]
  io: null stderr stderr port80 port443 ssl_key

The array of file descriptors to pass to the program.  These are named handles,
as defined in the rest of your desd configuration.  The default is to use the
handles defined for the service, which default to [ null, log, log ],
where log is the logger for this service.  (If the service does not define a logger
then it is the desd logger, and if desd doesn't define a logger it is desd's STDERR.)

Another common handle alias is 'desd_comm' which gives the script a socket to
communicate with desd to make API calls.

More exoting options include setting up pipes between services, or binding TCP
ports to persistent sockets which are handed to the service, or open handles
to files that the service couldn't otherwise read.

Can be specified as a whitespace-delimited string, or as an actual list.
Handle names cannot contain whitespace anyway, so the first is preferred.

=head3 action NAME

  action start:
    run: ...
	env: ...

Actions describe a thing that you want to do to a service.  Think of them like
methods called on a service.  Some actions are built-in, but you can define any
verb that makes sense for your service.

Each action can have the following attributes:

=over

=item run

Same as for a service.  In addition, you can call desd's internal functionality
with the notation

  { internal: ['method','arg1','arg2',...] }

=item env

Like the service's env, this alters the environment of any script executed
by this action.  Defaults to the same env as the service itself.

=item goal

When this action is invoked directly by a user, the goal of the service will be
changed to this value.

=item parallel

By default, only one action may run on a service at a time.  If you want an action
to be able to run in parallel with another action, list those actions in this
attribute.

=item access

Specify an array of access tokens which this action is given permission to use.
The permission system has not been fully specified yet, so this is a place holder
for now.

=back

The built-in actions are:

=over

=item start

The default "goal" is "up", so that the service gets restarted if it dies.

The default "run" is the internal method "exec_unless_running", which execs the
service unless it is running.

=item stop

The default "goal" is "down", so that the service no longer gets restarted.

The default "run" is the internal method "killscript" with arguments

  SIGTERM SIGCONT 30 SIGTERM 20 SIGQUIT 5 SIGKILL 20

=item restart

The default "goal" is "cycle".  This has the effect of running the stop
action if the service was running, and then running the start action.

The default "run" is the internal method "stop_start", which directly calls stop
and then calls "start", returning true if both those direct commands succeed.
(if they fail, the restart fails, but desd will still try to restart the service
due to the goal of "cycle").

=item check

This should be overridden with some test script that verifies the service is
performing the duties it is supposed to.

The default "parallel" is "*" meaning this action may run at any time.

The default "run" is the internal method "wait_for_uptime 3".

=back

=head2 handle NAME

  handle port80: 'tcp:80'
  handle port80:
    type: socket_tcp
	bind: 'any:80'
  handle ssl_key: *</root/ssl/key.pem
  handle ssl_key:
    type: file_read
	path: /root/ssl/key.pem
	alloc: each
  handle pipe_1_r:
	type: pipe_read
	peer: pipe_1_w

Declare a named filehandle (or socket, pipe, etc).  There are a variety of
convenient short forms, or the longer map for where you can spell out the
options.

=head2 event NAME

(not yet specified)

=head2 auth TOKEN

Specify a set of permissions that are awarded to any client/service with TOKEN.

(not yet specified)

=head2 listen PATH

(not yet specified)

=head2 log

(not yet specified)

=cut