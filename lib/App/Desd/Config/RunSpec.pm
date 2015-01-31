package App::Desd::Config::RunSpec;
use App::Desd::Types '-types';
use Moo;

# ABSTRACT: Access configuration parameters of a service

=head1 DESCRIPTION

This object normalizes all the short-hand notations that can be used to specify
a service.

=cut

has 'internal', is => 'ro';
has 'exec',     is => 'ro', isa => NonemptyArrayOfLazyScalar, is => 'ro';

sub BUILD {
	my $self= shift;
	defined($self->internal) + defined($self->exec) == 1
		or die "Run must specify 'internal:' xor 'exec:'\n";
}

sub _coerce_run {
	my $thing= shift;
	defined $thing or die "Run specification cannot be empty\n";
	if (!ref $thing) {
		# Process any special interpretation for the string
		$thing= _interpret_run_string($thing);
	}
	elsif (ref $thing eq 'ARRAY') {
		# If run is an array, then treat it as argv
		$thing= { args => $thing };
	}
	elsif (ref $thing ne 'HASH') {
		# ensure hashref
		die "Don't know how to convert ".ref($thing)." to run specification\n";
	}
	# convert 'args' to 'exec'
	if (defined my $args= delete $thing->{args}) {
		$thing->{exec}= [ $args->[0], @$args ];
	}
	return __PACKAGE__->new($thing);
}

sub _interpret_run_string {
	my $thing= shift;
	# If run is a string, and starts with SIG\w+, it's a killscript
	if ($thing =~ /^SIG[A-Z0-9]+/) {
		return { internal => [ 'killscript', split(/\s+/, $thing) ] };
	}
	# If run is a string, and starts with *WORD,
	#  split on whitespace and make it an internal call
	if ($thing =~ /^\*(\w+.*)/) {
		return { internal => [ split(/\s+/, $1) ] };
	}
	# If run is a string, and contains shell characters,
	#   convert it to call to $SHELL
	if ($thing =~ /[^\w\s_=\/.:,-]/) {
		return { exec => [ sub{$ENV{SHELL}}, sub{$ENV{SHELL}}, '-c', $thing ] };
	}
	# Else split on whitespace and make it the args to exec()
	my @argv= split /\s+/, $thing;
	@argv > 0 or die "Must have at least one argument\n";
	return { exec => [ $argv[0], @argv ] };
}

1;