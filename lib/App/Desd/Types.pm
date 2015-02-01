package App::Desd::Types;
use strict;
use warnings;
use Carp;
use Try::Tiny;
use Scalar::Util 'blessed';

use Type::Library -base, -declare => qw( HandleName );
use Type::Utils -all;
use Types::Standard -types;

declare 'NonemptyArrayOfLazyScalar', where {
	# non-empty arrayref
	defined($_) and (ref($_)||'') eq 'ARRAY' and @$_ >= 1
		# and every element is a plain scalar or a coderef
		and 0 == grep { !defined $_ or ref $_ && ref $_ ne 'CODE' } @$_;
};

declare 'ServiceName',   where { ($_//'') =~ /^\w[\w.-]*$/ };

declare 'HandleName',    where { ($_//'') =~ /^(-|\w[\w.-]*)$/ };

declare 'ServiceAction', where { ($_//'') =~ /^\w[\w.-]*$/ };

my %service_goals= map { $_ => 1 } qw( up down once cycle );
declare 'ServiceGoal',   where { $service_goals{$_//''} }

declare 'ServiceIoList', where { (ref($_||'')||'') eq 'ARRAY' and HandleName->check($_) for @$_ }

declare 'KillScript',    where { ($_//'') =~
	/^
	  (
	    (SIG[A-Z0-9]+) | ([0-9]+(\.[0-9]+)) # signal name, or positive whole or fractional number
	  )
	  ( [ ] ( # any number of space-delimited repeat of above
	    (SIG[A-Z0-9]+) | ([0-9]+(\.[0-9]+))
	  ))*
	$/x
};

declare 'MessageInstance', where { defined $_ and $_ =~ /^[0-9]+$/ };
declare 'MessageField',    where { defined $_ and !($_ =~ /[\t\n]/) };
declare 'MessageName',     where { defined $_ and $_ =~ /^[a-z0-9_]+$/ };
declare 'CondVar',         where { defined $_ and blessed($_) and $_->can('recv') and $_->can('cb') };

1;