package App::Desd;
use strict;
use warnings;

# ABSTRACT: Daemonproxy Example Supervisor Daemon

=head1 SYNOPSIS

  use App::Desd;
  App::Desd->new(%args)->run;

=head1 DESCRIPTION

Daemonproxy is a platform for building supervision tools.  This supervisor
is primarily an example of how to write a supervision tool using daemonproxy.
However, it is also a very handy little tool.  And since it's perl, you can
subclass it easily!

desd is event-driven, using AnyEvent, and accepts requests on a unix socket.
Future enhancements might add an HTTP protocol handler that lets you control
jobs as a sort of web service.

=head1 CONSTRUCTION

Desd is built with Moo, and accepts a hash of attribute names for its
constructor.  It also has a BUILDARGS which detects a single arrayref and
parses that arrayref as an ARGV list, using mthod L<parse_argv>.

=head1 METHODS

=head2 parse_argv

  my %args= $class->parse_argv( \@argv )

Convert unix-style argument list into named key/value pairs.

=head2 

=cut

