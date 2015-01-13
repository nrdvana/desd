package App::Desd::Protocol {
use AnyEvent;
use Try::Tiny;
use App::Desd::Types -types;
use Carp;
use Module::Runtime;
use Sub::Name;
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
has 'handle_ae', is => 'rw';

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
		->new( handle => $socket, handle_ae => $handle_ae, %opts );
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
	$self->flush;
	io_retry:
	my $wrote= CORE::send($self->handle_fd, $text, 0)
		or croak "send: $!";
	if ($wrote < length($text)) {
		substr($text, 0, $wrote)= '';
		goto io_retry;
	}
	1;
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
}

=head2 flush

  $proto->flush

Block until all pending data is written

=cut

sub flush {
	my $self= shift;
	return unless defined $self->{handle_ae};
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

my $install_method= sub {
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
	$install_method->($class, $msg         => sub { shift->send_msg([$msg, @_]); });
	$install_method->($class, "async_$msg" => sub { shift->async_send_msg([$msg, @_]); });
	$install_method->($class, "validate_msg_$msg" => sub {1});
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
		my $res= shift;
		# check that the result is formed the way we expect.
		exists $res->{$_} or croak for qw( success reaped exit_type exit_value timeout );
		if ($res->{success}) {
			return 'ok', $res->{reaped}? ('reaped', $res->{exit_type}, $res->{exit_value}) : 'not_running';
		} else {
			return 'error', $res->{timeout}? 'still_running' : 'failed';
		}
	});
}

sub _server_handle_input_line {
	my ($self, $input)= @_;
	# get message id and message name
	chomp($input);
	my ($msg_id, @msg)= split /\t/, $input;
	# if id is in use, kill the previous invocation and complain loudly
	...;
	# validate message name and validate payload
	...;
	# dispatch to the handle_msg_ method
	$self->_server_run_handler($msg_id, ..., [ $msg_id, $msg ]);
	
		my @result= ...;
		$self->_server_handle_handler_result($id, @result);
	}
	catch {
	};
}

sub _server_run_handler {
	my ($self, $msg_id, $coderef, $args)= @_;
	try {
		if (ref $args and $args->can('recv')) {
			# If arguments are a promise, receive the value now
			$args= [ $args->recv ];
		}
		# Run the handler
		my @result= $coderef->(@args);
		# Handler must return the message response (list of protocol fields),
		#  or a promise and callback method for asynchronous completion
		@result > 0 or die 'Handler returned empty result';
		unless (ref $result[0] && $result[0]->can('recv')) {
			# if it returns the response, queue the response to go to the client
			$self->send($id, @result);
			# and clean up the message handling state
			...;
		}
		else {
			ref $result[1] eq 'CODE' or die 'Promise must be accompanied by coderef';
			# if it returns a promise, store the promise in pending_commands
			$self->_pending_commands->{$msg_id}{continue}= \@result;
			# If there wasn't a callback on the promise, set one, which calls back through this
			# handler logic.
			unless ($result[0]->cb) {
				weaken($self);
				my $callback= $result[1];
				$result[0]->cb(sub { $self->_server_run_handler($msg_id, $callback, $_[0]) });
			}
		}
	}
	catch {
		# send a 'failed' result
		$self->send($id, 'error', $_ =~ /denied/? 'denied' : 'failed');
		# and clean up the message handling state
		...;
	};
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

=head2 send_msg

  $response= $proto->send_msg( \@message );

Sends a message and waits for the response, returning the response as an arrayref.

The first element of the response array is always 'ok' or 'error'.

=cut

sub send_msg {
	my ($self, $msg)= @_;
	$self->can('validate_msg_'.$msg->[0])->($self, $msg);
	$self->send(0, @$msg);
	return $self->recv_result(0);
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
	return $promise;
}

};

package App::Desd::Protocol::ServerRole {
use Try::Tiny;
use Carp;
use Moo::Role;

=head1 SERVER ATTRIBUTES / METHODS

These are available when the protocol object is used for the server side:

=cut

has 'app',               is => 'rw', required => 1;
has '_pending_commands', is => 'rw', init_arg => undef, default => sub {{}};

sub BUILD {}

after 'BUILD' => subname after_BUILD => sub {
	# set up server events on $self->handle_ae
};

};
1;
