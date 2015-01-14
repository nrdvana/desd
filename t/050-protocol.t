use strict;
use warnings;
use Test::More;
use AE;
use AnyEvent::Util 'portable_socketpair';
use Scalar::Util 'weaken';
use FindBin;
use Log::Any '$log';
use Log::Any::Adapter 'TAP';
use lib "$FindBin::Bin/lib";
use MockDesd;

use_ok( 'App::Desd::Protocol' );

sub protocol_pair {
	my ($server_sock, $client_sock)= portable_socketpair();
	#send($client_sock, "foo", Socket::MSG_DONTWAIT());
	#recv($server_sock, my $buf, 100, Socket::MSG_DONTWAIT());
	#is( $buf, 'foo', 'can send without sigpipe' );
	my ($server, $client);
	my $mock_desd= MockDesd->new;

	isa_ok( ($server= App::Desd::Protocol->new_server($server_sock, $mock_desd)), 'App::Desd::Protocol', 'create server' );
	isa_ok( ($client= App::Desd::Protocol->new_client($client_sock)), 'App::Desd::Protocol', 'create client' );
	#send($client_sock, "foo", Socket::MSG_DONTWAIT());
	#recv($server_sock, my $buf, 100, Socket::MSG_DONTWAIT());
	#is( $buf, 'foo', 'can send without sigpipe' );
	#$client->handle_ae->push_write("foo");
	#$server->handle_ae->on_read(sub { $log->debug("got on_read") });
	#AE::cv->recv;
	return $server, $client;
}

sub undefine_freed_ok {
	my (undef, $things_get_freed, $message)= @_;
		use DDP;
		p $things_get_freed;
	$message ||= 'freed '.join(', ', keys %$things_get_freed);
	ref $_ && weaken($_) for values %$things_get_freed;
	$_[0]= undef; # this should cause everything weakly-ref'd in the set to get garbage collected
	my @not_freed= grep { defined $things_get_freed->{$_} } keys %$things_get_freed;
	if (@not_freed) {
		fail($message);
		diag("Not freed: ".join(', ', @not_freed));
	} else {
		pass($message);
	}
}

subtest echo => sub {
	my ($server, $client)= protocol_pair;
	my @msg_args;
	my $cv= AE::cv;
	my $echo= App::Desd::Protocol->can('handle_msg_echo');
	local *App::Desd::Protocol::handle_msg_echo= sub { my ($self, $id, $msg)= @_; (undef, @msg_args)= @$msg; $cv->send; $echo->(@_) };
	$log->trace('sending echo');
	$client->async_echo('foo');
	$log->trace('sent echo');
	$client->flush;
	$log->trace('flushed');
	$cv->recv;
	is_deeply( \@msg_args, ['foo'], 'echo arguments delivered' );
	
	undefine_freed_ok($server, { server => $server, handle_ae => $server->handle_ae, handle => $server->handle });
	undefine_freed_ok($client, { client => $client, handle_ae => $client->handle_ae, handle => $client->handle });
};

done_testing;
