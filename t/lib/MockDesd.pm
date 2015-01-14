package MockDesd;
use strict;
use warnings;
use Log::Any '$log';

# This class is a dummy object that simply logs when methods are called
# The intended use for testing is to localize its methods with appropriate
# testing code:
#
# local *MockDesd::killscript= sub { is( $_[0], 'foo', 'got correct arguments' ); };

sub new { bless { calls => {} }, shift }

for (qw( service_action killscript )) {
	eval 'package '.__PACKAGE__.'; sub '.$_.' { $log->debug("'.$_.' called"); $_[0]{calls}{'.$_.'}++; }; 1'
		== 1 or die $@;
}

1;