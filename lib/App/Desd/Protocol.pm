package App::Desd::Protocol {
use AnyEvent;
use AnyEvent::Handle;
use Try::Tiny;
use App::Desd::Types -types;
use Carp;
use Module::Runtime;
use Sub::Name;
use Scalar::Util 'blessed', 'weaken';
use Log::Any '$log';
use mro 'c3';
use Moo;
use namespace::clean;

=head1 SYNOPSIS

  # client connecting to server
  my $proto= App::Desd::Protocol->new_client($socket);
  
  # use synchronous API:
  my $result= $proto->$command( @args );
  
  # optionally, use event-driven API:
  my $promise= $proto->async_$command( @args );
  my $result= $promise->recv;


  # this class also implements the server side, which is always asynchronous
  $socket= accept(...);
  my $proto= App::Desd::Protocol->new_server($socket, $app);
  
  # the $proto holds a ref to the socket, so you just need to hold a ref
  # to the proto object to keep it open.

=head1 DESCRIPTION

Desd has a command/response and optionally event-based protocol.  This protocol
is used both for the connections to the main desd socket, and for the pipes
it opens to the child processes.

=head1 ATTRIBUTES

=head2 handle

The socket connection on which to communicate

=head2 handle_ae

The AnyEvent::Handle used for asynchronous queueing of read/write operations.

=cut

has 'handle',    is => 'rw', required => 1;

has 'handle_ae', is => 'lazy', predicate => 1;

sub _build_handle_ae {
	require AnyEvent::Handle;
	AnyEvent::Handle->new(fh => $_[0]->handle, linger => 0);
}

=head2 

=head1 METHODS

=head2 new

Creates an instance of the protocol with no designated client/server role.
You probably want new_client or new_server.

=head2 new_client

  my $proto= App::Desd::Protocol->new_client($socket, %opts);

Combines this protocol class with the client role, giving you convenient
access to the messages defined in the protocol as methods, and with automatic
tracking of server responses to messages, for easy remote method calls.

=cut

sub new_client {
	@_ >= 2 && (@_ & 1) == 0 or croak "Wrong number of arguments";
	my ($class, $socket, %opts)= @_;
	
	# if socket is a path, connect to it
	unless (ref $socket) {
		my $path= $socket;
		$socket= undef;
		require Socket;
		socket($socket, Socket::AF_UNIX(), Socket::SOCK_STREAM(), 0)
			or croak "Can't create socket: $!";
		connect($socket, Socket::sockaddr_un($path))
			or croak "Can't connect to $path: $!";
	}
	
	my $handle_ae= $socket->can('push_write')? $socket : undef;
	$socket= $handle_ae->fh if defined $handle_ae;
	
	return $class
		->_with_client_role
		->new( handle => $socket, (defined $handle_ae? (handle_ae => $handle_ae) : ()), %opts );
}

sub _with_client_role {
	my $class= shift;
	return Moo::Role->create_class_with_roles($class, 'App::Desd::Protocol::ClientRole');
}

=head2 new_server

  my $proto= App::Desd::Protocol->new_server($socket, $desd_instance, %opts);

Combines this protocol class with the server role, giving you automatic
linkage between client requests and an instance of the desd application.

=cut

sub new_server {
	@_ >= 3 && (@_ & 1) == 1 or croak "Wrong number of arguments";
	my ($class, $socket, $app, %opts)= @_;
	
	my $handle_ae= $socket->can('push_write')? $socket : undef;
	$socket= $handle_ae->fh if defined $handle_ae;
	$handle_ae //= AnyEvent::Handle->new(fh => $socket);
	
	return $class
		->_with_server_role
		->new( handle => $socket, handle_ae => $handle_ae, app => $app, %opts );
}

sub _with_server_role {
	my $class= shift;
	return Moo::Role->create_class_with_roles($class, 'App::Desd::Protocol::ServerRole');
}

=head2 send

  $proto->send( @fields )

Joins the fields into a line of text and sends it over the socket, blocking until it has
all been written.  The first field must always be a number (the message-id).

=cut

sub send {
	my $self= shift;
	MessageInstance->assert_valid($_[0]);
	MessageField->assert_valid($_) for @_;
	my $text= join("\t", @_)."\n";
	
	if ($self->has_handle_ae) {
		$self->handle_ae->push_write($text);
		$self->flush;
	}
	else {
		while (1) {
			my $wrote= CORE::send($self->handle, $text, 0)
				// croak "send: $!";
			$log->trace("wrote $wrote '".substr($text,0,$wrote)."'")
				if $log->is_trace;
			last if $wrote >= length($text);
			substr($text, 0, $wrote)= '';
		}
	}
	1;
}

=head2 recv

  $field_arrayref= $proto->recv;

Blocks until it has read the entire next line (but running the event loop
if AnyEvent is being used), splits it into fields, and validates them.

Returns an arrayref, where the first element is the message id.

=cut

sub recv {
	my $self= shift;
	my $line;
	if ($self->has_handle_ae) {
		my $line_cv= AnyEvent->condvar;
		$self->handle_ae->push_read(line => sub { $line_cv->send($_[1]) });
		$line= $line_cv->recv;
	}
	else {
		my $fh= $self->handle;
		$line= <$fh>;
	}
	my @fields= split /\t/, $line;
	MessageInstance->assert_valid($fields[0]);
	MessageField->assert_valid($_) for @fields;
	\@fields;
}

=head2 async_send

  $proto->async_send( @fields )

Like send, but pushes the data into an AnyEvent queue.

=cut

sub async_send {
	my $self= shift;
	MessageInstance->assert_valid($_[0]);
	MessageField->assert_valid($_) for @_;
	my $text= join("\t", @_)."\n";
	$self->handle_ae->push_write($text);
	$log->trace("queued write ".length($text)." '$text'") if $log->is_trace;
}

=head2 flush

  $proto->flush

Block until all pending data is written

=cut

sub flush {
	my $self= shift;
	return unless $self->has_handle_ae;
	my $flushed= AnyEvent->condvar;
	$self->handle_ae->on_drain(sub { $flushed->send(1) });
	$flushed->recv;
}

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

# "message_defs" is a package variable whose keys can be auto-overlaid by subclasses.
my %message_defs;
sub _get_linear_message_defs {
	($_[1]= __PACKAGE__),pop @_ if @_ > 1;
	return \%message_defs;
}

my $install_missing_method= sub {
	my ($class, $name, $coderef)= @_;
	return if $class->can($name);
	no strict 'refs';
	*{$class.'::'.$name}= subname $class.'::'.$name, $coderef;
};
sub _register_message {
	my $class= (defined $_[0] && ($_[0] =~ /::/))? shift : scalar caller;
	@_ & 1 or croak 'Wrong number of arguments to _register_message($name, %opts)';
	my ($msg, %opts)= @_;
	$opts{message}= $msg;

	my @stack= $class->_get_linear_message_defs(my $pkg);
	if ($pkg ne $class) {
		Module::Runtime::check_module_name($class); # caution, since we're using eval
		mro::set_mro($class, 'c3'); # any class using this needs to be c3
		eval 'package '.$class.'; my %message_defs; sub _get_linear_message_defs { ($_[1]= __PACKAGE__),pop @_ if @_ > 1; return \%message_defs, shift->maybe::next::method }; 1'
			== 1 or die $@;
		@stack= $class->_get_linear_message_defs;
	}

	$stack[0]{$msg}= \%opts;

	# install convenience and default methods for this message
	$install_missing_method->($class, $msg         => sub { shift->send_msg([$msg, @_]); });
	$install_missing_method->($class, "async_$msg" => sub { shift->async_send_msg([$msg, @_]); });
	$install_missing_method->($class, "validate_msg_$msg" => sub {1});
}

sub get_message_defs {
	my $class= shift;
	return { map { %$_ } reverse $class->_get_linear_message_defs };
}

sub get_message_info {
	my ($class, $msg)= @_;
	defined $_->{$msg} and return $_->{$msg}
		for $class->_get_linear_message_defs;
	return;
}

=head2 echo

  echo FIELD1 FIELD2 ...

Send a list of fields to desd.  Desd will always reply 'ok' followed by the
same fields.  This is a simple way to test communication.

=cut

_register_message('echo');

sub handle_msg_echo {
	my ($self, $cmd_id, $msg)= @_;
	return 'ok', @{$msg}[1..$#$msg];
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

_register_message('service_action');

sub validate_msg_service_action {
	my ($self, $msg)= @_;
	ServiceName->assert_valid($msg->[1]);
	ServiceAction->assert_valid($msg->[2]);
}

sub handle_msg_service_action {
	my ($self, $cmd_id, $msg)= @_;
	my (undef, $svname, $act)= @$msg;
	my $promise= $self->app->service_action($svname, $act);
	return $promise, subname 'handle_msg_service_action(2)' => sub {
		return 'ok', 'complete';
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

_register_message('killscript');

sub validate_msg_killscript {
	my ($self, $msg)= @_;
	ServiceName->assert_valid($msg->[1]);
	KillScript->assert_valid($msg->[2]);
}

sub handle_msg_killscript {
	my ($self, $cmd_id, $msg)= @_;
	my (undef, $svcname, $script)= @$msg;
	my $promise= $self->app->killscript($svcname, $script);
	return $promise, subname 'handle_msg_killscript(2)' => sub {
		my ($self, $res)= @_;
		# check that the result is formed the way we expect.
		exists $res->{$_} or croak for qw( success reaped exit_type exit_value timeout );
		if ($res->{success}) {
			return 'ok', $res->{reaped}? ('reaped', $res->{exit_type}, $res->{exit_value}) : 'not_running';
		} else {
			return 'error', $res->{timeout}? 'still_running' : 'failed';
		}
	};
}

sub close {
	$_[0]->handle->close if defined $_[0]->handle;
	$_[0]->handle_ae->destroy if $_[0]->has_handle_ae;
}

sub DESTROY {
	$_[0]->close;
}

};

package App::Desd::Protocol::ClientRole {
use Try::Tiny;
use Carp;
use Moo::Role;

=head1 CLIENT ATTRIBUTES / METHODS

These are available when the protocol object is used for the client side:

=cut

has '_pending_commands', is => 'rw', init_arg => undef, default => sub {{}};
sub _next_cmd_id { $_[0]{_next_cmd_id}++ || 0 }

sub _start_async_readline {
	my $self= shift;
	return if $self->{listening};
	weaken($self);
	$self->{listening}= 1;
	$self->handle_ae->push_read(line => sub {
		$self->{listening}= 0;
		$self->_handle_input_line($_[1]);
	});
}

sub _handle_input_line {
	my ($self, $input)= @_;
	# get message id this line is responding to
	$log->debug('handle input "'.$input.'"');
	my ($msg_id, @msg)= split /\t/, $input;
	if (defined $self->_pending_commands->{$msg_id}
		&& ($msg[1] =~ /^ok|error$/)
	) {
		my $command= delete $self->_pending_commands->{$msg_id};
		$log->debug('got reply for '.$command->{msg}[0]) if $log->is_debug;
		$command->{promise}->send(\@msg);
	}
	# re-queue the listener if more commands to listen for
	$self->_start_async_readline if %{$self->_pending_commands};
}

=head2 send_msg

  $response= $proto->send_msg( \@message );

Sends a message and waits for the response, returning the response as an arrayref.

The first element of the response array is always 'ok' or 'error'.

=cut

sub send_msg {
	my ($self, $msg)= @_;
	$self->can('validate_msg_'.$msg->[0])->($self, $msg);
	$self->send(0, @$msg);
	while (my $result= $self->recv) {
		return $result if shift @$result == 0;
	}
}

=head2 async_send_msg

  $promise= $proto->async_msg( \@message );

Like synch_msg, but returns a promise (AnyEvent cont var) for the result.

=cut

sub async_send_msg {
	my ($self, $msg)= @_;
	$self->can('validate_msg_'.$msg->[0])->($self, $msg);
	my $promise= AnyEvent->condvar;
	my $cmd_id= $self->_next_cmd_id;
	$self->async_send($cmd_id, @$msg);
	$self->_pending_commands->{$cmd_id}= { msg => $msg, promise => $promise };
	$self->_start_async_readline;
	return $promise;
}

};

package App::Desd::Protocol::ServerRole {
use Try::Tiny;
use Carp;
use Log::Any '$log';
use Scalar::Util 'weaken', 'blessed';
use App::Desd::Types -types;
use Sub::Name;
use Moo::Role;

=head1 SERVER ATTRIBUTES / METHODS

These are available when the protocol object is used for the server side:

=cut

has 'app',            is => 'rw', required => 1;
has '_command_state', is => 'rw', init_arg => undef, default => sub {{}};

sub BUILD {}

after 'BUILD' => subname 'after(BUILD)' => sub {
	my $self= shift;
	weaken($self);
	$self->handle_ae->on_read(sub {
		$log->trace('on_read: '.length($_[0]{rbuf}).' in buffer') if $log->is_trace;
		my $p= index($_[0]{rbuf}, "\n");
		if ($p >= 0) {
			my $line= substr($_[0]{rbuf}, 0, $p);
			substr($_[0]{rbuf}, 0, $p+1)= '';
			$self->_handle_input_line($line);
		}
	});
	$self->handle_ae->on_error(sub {
		$self->close();
	});
	$self->handle_ae->on_eof(sub {
		$self->close();
	});
	$log->debug('set server event handlers');
};

sub _handle_input_line {
	my ($self, $input)= @_;
	# get message id and message name
	$log->debug('handle input "'.$input.'"');
	my ($msg_id, @msg)= split /\t/, $input;
	my $msgname= $msg[0];
	
	unless (MessageInstance->check($msg_id)) {
		# TODO: this is erious enough the server might want to disconnect the client.
		# make a callback to receive this condition
		$log->warn('received line with invalid message id');
		return $self->send(0, 'error', 'invalid protocol formatting');
	}
	
	# if id is in use, kill the previous invocation and complain loudly
	if (defined $self->_command_state->{$msg_id}) {
		$log->warn("received duplicate message id $msg_id");
		...;
	}
	
	# ensure validate and handle are defined for this message
	my ($validate, $handler);
	unless (MessageName->check($msgname)
	  and ($validate= $self->can("validate_msg_$msgname"))
	  and ($handler= $self->can("handle_msg_$msgname"))
	) {
		$log->warn("received unknown message $msgname");
		return $self->send($msg_id, 'error', 'invalid', "unknown message $msgname");
	}
	
	# validate message payload
	if (!try { $validate->($self, \@msg); 1; } catch { 0 }) {
		$log->warn("received invalid message arguments");
		return $self->send($msg_id, 'error', 'invalid', "bad message arguments");
	}
	
	# dispatch to the handle_msg_ method
	$self->_command_state->{$msg_id}= { message => \@msg, start_ts => time };
	$self->_run_handler($msg_id, $handler, [ $msg_id, \@msg ]);
}

sub _run_handler {
	my ($self, $msg_id, $handler, $args)= @_;
	try {
		if (blessed($args) and $args->can('recv')) {
			# If arguments are a promise, receive the value now
			# this could also croak() us down to the catch block.
			$args= [ $args->recv ];
		}
		$log->debug('handling message '.$self->_command_state->{$msg_id}{message}[0])
			if $log->is_debug;
		# Run the handler
		my @result= $handler->($self, @$args);
		# Handler must return the message response (list of protocol fields),
		#  or a promise and callback method for asynchronous completion
		@result > 0 or die 'Handler returned empty result';
		unless (ref $result[0] && $result[0]->can('recv')) {
			# if it returns the response, queue the response to go to the client
			$self->send($msg_id, @result);
			# and clean up the message handling state
			$self->_end_command($msg_id);
		}
		else {
			ref $result[1] eq 'CODE' or die 'Promise must be accompanied by coderef';
			# if it returns a promise, store the promise in pending_commands
			$self->_command_state->{$msg_id}{continue}= \@result;
			# If there wasn't a callback on the promise, set one, which calls back through this
			# handler logic.
			unless ($result[0]->cb) {
				my $callback= $result[1];
				my $anon_name= '_run_handler(continue-'.++$self->_command_state->{$msg_id}{continue_count}.')';
				weaken($self);
				$result[0]->cb(subname $anon_name => sub {
					delete $self->_command_state->{$msg_id}{continue};
					$self->_run_handler($msg_id, $callback, $_[0]);
				});
			}
		}
	}
	catch {
		# send a 'failed' result
		$self->send($msg_id, 'error', $_ =~ /denied/? 'denied' : 'failed');
		# and clean up the message handling state
		$self->_end_command($msg_id);
	};
}

sub _end_command {
	my ($self, $id)= @_;
	my $state= delete $self->_command_state->{$id};
	return unless $state;
	if ($state->{continue}) {
		$state->{continue}[0]->cb(undef);
		$state->{continue}[0]->croak('canceled')
			unless $state->{continue}[0]->ready;
	}
}

};
1;
