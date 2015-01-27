package App::Desd::Config;
use Moo;

=head1 SYNOPSIS

  $config= App::Desd::Config->deserialize(file => $path);
  $config= App::Desd::Config->new(\%data);
  
  print $config->service('foo')->args;
  
  $yaml= $config->serialize();
  $config->serialize_to_file($path_or_handle);

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

=head2 get_ctor_args

Return perl data which could be used to reconstruct a config object.

=head2 deserialize

  $config= App::Desd::Config->deserialize(file => $path);
  $config= App::Desd::Config->deserialize(yaml => $yaml);

Load a config from some serialized form.  If loading from file,
the format will be auto-detected.  The only format right now
is YAML.

Calls L<new> and returns an object.

=head2 serialize

  my $result= $config->serialize( %options )

  my $yaml= $config->serialize(yaml => 1);
  my $data= $config->serialize(new_args => 1);
  $config->serialize(file => $path);

Serialize the configuration, either to a yaml string or to a file
(in yaml format).

=over

=item new_args

Return un-blessed perl data, which could be passed to 'new' to
clone this config.

=item yaml

The value of this key is either 1 (meaning return the yaml) or a scalar ref
which receives the yaml.  The yaml text can be passed to L<deserialize> to
clone this config.

=item file

The value of this key is a file name, which will be overwritten with the YAML
serialization of the config, or a file handle which will be written directly.

=back

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
