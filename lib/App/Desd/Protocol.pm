package App::Desd::Protocol;
use AnyEvent;
use Try::Tiny;
use App::Desd::Types -types;
use Carp;
use Moo;
use namespace::clean;

=head1 SYNOPSIS

  # client connecting to server
  my $proto= App::Desd::Protocol->connect('/path/to/socket');
  -or-
  my $proto= App::Desd::Protocol->new(server => $socket);
  
  # use synchronous API:
  my $success= $proto->$command( \@args, \@optional_result_out );
  
  # optionally, use event-driven API:
  $proto->set_async_event_cb( \&callback );
  $proto->async_$command( \@args, \&callback );


  # this class also implements the server side, which is always asynchronous
  $socket= accept(...);
  my $proto= App::Desd::Protocol->new(client => $socket, app => $app);
  
  # the $proto holds a ref to the socket, so you just need to hold a ref
  # to the proto object to keep it open.

=head1 DESCRIPTION

Desd has a command/response and optionally event-based protocol.  This protocol
is used both for the connections to the main desd socket, and for the pipes
it opens to the child processes.

=head1 PROTOCOL

=head2 Basic Structure

All protocol messages are lines of text in UTF-8, tab-delimited.

  field1 <TAB> field2 <TAB> field3 ... <LF>

There is no protocol-wide escaping mechanism, and fields may never contain <TAB>
or <LF> characters.  No cases are anticipated where a field would need to contain
these characters, but if it became necessary for a command or event, then that
command or event would document the escaping used.

The first field is always an identifier to correlate commands, responses, and
events.  If it is a command, the client uses 0 to ask for synchronous communication,
or any positive 64-bit numeric identifier to request events in response to the
command.  In synchronous mode, the server will return all responses for a command
before sending any responses for any other command.  In asynchronous mode, the
server will possibly interleave responses to commands, which the client can tell
apart by seeing its ID at the start of the event.

For commands, the second field is the command name, and remaining fields are the
arguments.

For events, the second field is the event type, and remaining fields depend on
the type of the event.  Every command will generate at least one event of either
"ok" or "error", with following fields that depend on the command.  The "ok" or
"error" event always come at the completion of the command.

=head2 Commands

=cut

our %commands;

sub _register_msg {
	$_[0] =~ /::/ or unshift @_, scalar caller;
	my ($class, $cmd, $opts)= @_;
	$class->can('assemble_msg_'.$cmd) or croak "Missing assemble_msg for $cmd";
	$class->can('handle_msg_'.$cmd) or croak "Missing handle_msg for $cmd";
	my $assemble= "assemble_msg_$cmd";
	my $synch= sub { my $self= shift; my @msg= $self->$assemble(@_); return $self->synch_msg(\@msg) };
	my $async= sub { my $self= shift; my @msg= $self->$assemble(@_); return $self->async_msg(\@msg) };
	
	no strict 'refs';
	${$class.'::commands'}{$cmd}= $opts;
	*{$class.'::'.$cmd}= $synch;
	*{$class.'::async_'.$cmd}= $async;
}

sub synch_msg {
	my ($self, $msg)= @_;
	$self->send(0, $msg);
	return $self->recv_result(0);
}

sub async_msg {
	my ($self, $msg)= @_;
	my $promise= AnyEvent->condvar;
	my $cmd_id= $self->send(undef, $msg);
	$self->{_pending_commands}{$cmd_id}= { msg => $msg, promise => $promise };
	return $promise;
}

=head2 service_action

  service_action SERVICE_NAME ACTION_NAME

Perform one of the actions (defined in the config file) for the given service.

Each service has default actions like 'start' and 'stop', but might also
have custom actions like 'check' or 'graceful_reload'.  This command starts
any of the actions, and returns when the action is complete.  HOWEVER, some
actions may only perform a state change, and don't wait for the consequences
to occur, so you might need to listen to other events instead of just waiting
for the completion of the action.  There can be only one action occurring on
a service at any moment.  If the action you request is already in progress,
then this will simply notify you when that action-in-progress completes.  If
you have requested a different action, then this one will be queued and start
immediately after the other one completes.

The command will return one of the following responses:

=over

=item ok complete

the action you specified has completed on this service

=item error invalid

the service does not exist or the action isn't defined

=item error denied

the caller doesn't have permission to perform this action on this service

=back

=cut

_register_msg('service_action');

sub assemble_msg_service_action {
	my ($self, $svname, $act)= @_;
	ServiceName->assert_valid($svname);
	ServiceAction->assert_valid($act);
	return 'service_action', $svname, $act;
}
sub handle_msg_service_action {
	my ($self, $cmd_id, $svname, $act, $callback)= @_;
	try {
		ServiceName->assert_valid($svname);
		ServiceAction->assert_valid($act);
		$self->{app}->assert_permission($self->{session}{keys}, 'service_action', $svname, $act);
		$self->{app}->service_action($svname, $act, sub {
			my %args= @_;
			$self->send($cmd_id, 'ok', 'complete');
		});
	} catch {
		$self->send($cmd_id, 'error', ($_ =~ /denied/)? 'denied' : 'invalid');
	};
}

=head3 killscript

  killscript SERVICE_NAME SCRIPT

This command asks Desd to kill the named service with a specified sequence of
kill() and wait().

The script is a space-separated list of signal names and decimal wait-for-exit numbers.

Example:
  SIGTERM 20 SIGTERM 5.5 SIGKILL 10

The numbers indicate a time in seconds (and may be fractional) to wait for the
service to exit before sending the next signal.

Available signals will depend on the system's perl.

The command will complete with one of the following responses:

=over

=item ok reaped EXIT_REASON EXIT_VALUE

successful termination of the job

EXIT_REASON is either "exit" (with a numeric EXIT_VALUE) or "signal" (with a signal name for EXIT_VALUE)

=item ok not_running

the job wasn't running in the first place

=item error still_running

the job has not terminated by the end of the script

=item error invalid

the killscript was invalid, or the job isn't defined

=item error denied

the caller doesn't have permission to send signals to the job

=back

=cut

_register_msg('killscript');

sub assemble_msg_killscript {
	my ($self, $svcname, $script)= @_;
	ServiceName->assert_valid($svcname);
	KillScript->assert_valid($script);
	return 'killscript', $svcname, $script;
}
sub handle_msg_killscript {
	my ($self, $cmd_id, $svcname, $script)= @_;
	try {
		ServiceName->assert_valid($svcname);
		KillScript->assert_valid($script);
		$self->{app}->assert_permission($self->{session}{keys}, 'kill_service', $svcname);
		$self->{app}->killscript($svcname, $script, sub {
			my %args= @_;
			if ($args{success}) {
				$self->send($cmd_id, 'ok', $args{reaped}? ('reaped', $args{exit_type}, $args{exit_value}) : 'not_running');
			} else {
				$self->send($cmd_id, 'error', $args{timeout}? 'still_running' : 'failed');
			}
		});
	}
	catch {
		$self->send($cmd_id, 'error', ($_ =~ /denied/)? 'denied' : 'invalid');
	};
}

1;
