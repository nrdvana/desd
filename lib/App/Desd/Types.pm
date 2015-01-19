package App::Desd::Types;
use strict;
use warnings;
use Carp;
use Try::Tiny;
use Scalar::Util 'blessed';

use Type::Library -base;
use Type::Utils -all;
use Types::Standard -types;

declare 'ServiceName',   where { ($_//'') =~ /^[\w.-]+$/ };
declare 'ServiceAction', where { ($_//'') =~ /^[\w.-]+$/ };
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