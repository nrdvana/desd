package App::Desd::Config::RunSpec;
use App::Desd::Types '-types';
use Moo;

# ABSTRACT: Access configuration parameters of a service

=head1 DESCRIPTION

This object normalizes all the short-hand notations that can be used to specify
a service.

=cut

has 'internal', is => 'ro';
has 'exec',     is => 'ro';

sub _coerce_run {
	my $thing= shift;
	defined $thing or die "Run specification cannot be empty\n";
	if (!ref $thing) {
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
			return { exec => [ \'SHELL', \'SHELL', '-c', $thing ] };
		}
		# Else split on whitespace and make it the args to exec()
		my @argv= split /\s+/, $thing;
		@argv > 0 or die "Must have at least one argument\n";
		return { exec => [ $argv[0], @argv ] };
	}
	# If run is an array, then treat it as argv
	if (ref $thing eq 'ARRAY') {
		NonemptyArrayOfScalar->check($thing)
			or die "run must be non-empty array of argument strings\n";
		return { exec => [ $thing->[0], @$thing ] };
	}
	if (ref $thing eq 'HASH') {
		if (defined $thing->{args}) {
			NonemptyArrayOfScalar->check($thing->{args})
				or die "args must be non-empty array of argument strings\n";
			$thing->{exec}= [ $thing->{args}[0], @{$thing->{args}} ];
		}
		defined($thing->{internal}) + defined($thing->{exec}) == 1
			or die "Run must specify 'internal:' xor 'exec:'\n";
		if (defined $thing->{exec}) {
			NonemptyArrayOfScalar->check($thing->{exec})
				or die "exec must be non-empty array of argument strings\n";
			return { exec => $thing->{exec} };
		}
		else {
			return { internal => $thing->{internal} };
		}
	}
	die "Don't know how to convert ".ref($thing)." to run specification\n";
}

1;