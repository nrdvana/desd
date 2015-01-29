package App::Desd::Config;
use Moo;

=head1 SYNOPSIS

  $config= App::Desd::Config->deserialize(file => $path);
  $config= App::Desd::Config->new(\%data);
  
  print $config->service('foo')->args;
  
=head1 DESCRIPTION

App::Desd::Config is a class that handles the details of reading the config
file, normalizing the things the user wrote, supplying default values implied
by the configuration, and providing convenient accessor objects to work with
the configuration entities.

=head1 CONFIGURATION DATA

The structure and semantics of the configuration are described in
L<App::Desd::Manual::ConfigFile>.

=head1 METHODS

=head2 new

Standard Moo constructor.  Warns about unknown arguments.

=head2 service

  $svc= $config->service("Foo");

Return the configuration for the named service, or undef if it doesn't exist.

See L<App::Desd::Config::Service>

=head2 events

Arrayref of L<App::Desd::Config::Event>

=head2 auth_tokens

Arrayref of L<App::Desd::Config::AuthToken>

=head2 controls

Arrayref of L<App::Desd::Config::Control> which holds details about how clients
can connect to Desd and control services.

=head2 log_target

=cut
