use strict;
use warnings;
use Test::More;
use AnyEvent;
use AnyEvent::Util 'portable_socketpair';
use Scalar::Util 'weaken';
use FindBin;
use Log::Any '$log';
use Log::Any::Adapter 'TAP';
use lib "$FindBin::Bin/lib";
use DDP use_prototypes => 0;
use Devel::Peek 'SvREFCNT', 'Dump';
use MockDesd;

use_ok( 'App::Desd::Protocol' );

sub protocol_pair {
	my ($server_sock, $client_sock)= portable_socketpair();
	my ($server, $client);
	my $mock_desd= MockDesd->new;

	isa_ok( ($server= App::Desd::Protocol->new_server($server_sock, $mock_desd)), 'App::Desd::Protocol', 'create server' );
	isa_ok( ($client= App::Desd::Protocol->new_client($client_sock)), 'App::Desd::Protocol', 'create client' );
	
	return $server, $client;
}

sub undefine_freed_ok {
	my (undef, $things_get_freed, $message)= @_;
	
	# default message
	$message ||= 'freed '.join(', ', sort keys %$things_get_freed);
	
	# weaken all the references to the things we're watching
	defined $_ && ref($_) && weaken($_)
		for values %$things_get_freed;
	
	$_[0]= undef; # this should cause everything weakly-ref'd in the set to get garbage collected
	
	# Look for refs which are not null
	my @not_freed= grep { defined $things_get_freed->{$_} and ref $things_get_freed->{$_} } keys %$things_get_freed;
	if (@not_freed) {
		fail($message);
		diag("Not freed: ".join(', ', @not_freed));
		#diag("  $_ => " . p($things_get_freed->{$_})) for @not_freed;
	} else {
		pass($message);
	}
}

subtest free_objects => sub {
	my ($server, $client)= protocol_pair();
	undefine_freed_ok($client, { client => $client, socket => $client->{socket} });
	undefine_freed_ok($server, { server => $server, socket => $server->{socket} });
};

subtest echo => sub {
	my ($server, $client)= protocol_pair;
	my @msg_args;
	$log->trace('sending echo');
	my $async_result= $client->async_echo('foo');
	$log->trace('sent echo');
	$client->flush;
	$log->trace('flushed');
	my $result= $async_result->recv;
	is_deeply( $result, ['foo'], 'echo completed' );
	
	undefine_freed_ok($client, { client => $client, socket => $client->{socket} });
	undefine_freed_ok($server, { server => $server, socket => $server->{socket} });
};

done_testing;
