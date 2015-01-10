package App::Desd::Protocol;
use Moo;

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

my @commands;

=head3 killscript

  killscript SERVICE_NAME ACTION(s) ...

This command asks Desd to kill the named service with a specified sequence of
kill() and wait().

The list of actions are given as separate protocol fields.

An action is either a decimal number of seconds to wait, or one of these signal
names: SIGCONT, SIGTERM, SIGHUP, SIGQUIT, SIGINT, SIGUSR1, SIGUSR2, SIGKILL.
Other signal names may be available.

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

sub _validate_killscript_args {
	@_ > 1 or die "Require service name and script";
	($_[0]//'') =~ /^[\w.-]+$/ or die "Invalid service name";
	($_//'') =~ /^(SIG[A-Z0-9]+)|([0-9]+(\.[0-9]+))$/ or die "Invalid script element '$_'"
		for @_[1..$#_];
	1;
}

sub killscript {
	my ($self, @args)= @_;
	_validate_killscript_args(@args);
	$self->send(0, 'killscript', @args);
	return $self->recv_result(0);
}
sub async_killscript {
	my ($self, $args, $callback)= @_;
	_validate_killscript_args(@$args);
	my $cmd_id= $self->send(undef, 'killscript', @$args);
	$self->{_response_callback}{$cmd_id}= $callback;
	1;
}
sub handle_killscript {
	my ($self, $cmd_id, $svcname, @script)= @_;
	try {
		_validate_killscript_args($svcname, @script);
		$self->{app}->assert_permission($self->{session}{keys}, 'kill_service', $svcname);
		$self->{app}->killscript($svcname, \@script, sub {
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