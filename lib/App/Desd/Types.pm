package App::Desd::Types;
use strict;
use warnings;
use Carp;
use Try::Tiny;

use Type::Library -base;
use Type::Utils -all;
use Types::Standard -types;

declare 'ServiceName',   where { ($_//'') =~ /^[\w.-]+$/ };
declare 'ServiceAction', where { ($_//'') =~ /^[\w.-]+$/ };
declare 'KillScript',    where { ($_//'') =~ /^(SIG[A-Z0-9]+)|([0-9]+(\.[0-9]+))$/ };

1;