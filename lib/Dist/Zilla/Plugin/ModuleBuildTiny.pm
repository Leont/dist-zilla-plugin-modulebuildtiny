package Dist::Zilla::Plugin::ModuleBuildTiny;

use Moose;
with qw/Dist::Zilla::Role::BuildPL Dist::Zilla::Role::TextTemplate Dist::Zilla::Role::PrereqSource/;

use Dist::Zilla::File::InMemory;
use Module::Metadata;
use MooseX::Types::Moose qw/Str/;
use List::MoreUtils qw/any/;

has version => (
	is      => 'ro',
	isa     => Str,
	default => sub {
		return Module::Metadata->new_from_module('Module::Build::Tiny')->version->stringify;
	},
);

has minimum_perl => (
	is      => 'ro',
	isa     => Str,
	lazy    => 1,
	default => sub {
		my $self = shift;
		return $self->zilla->prereqs->requirements_for('runtime', 'requires')->requirements_for_module('perl') || '5.006'
	},
);

my $template = "use {{ \$minimum_perl }};\nuse Module::Build::Tiny {{ \$version }};\nBuild_PL();\n";

sub register_prereqs {
	my ($self) = @_;

	$self->zilla->register_prereqs({ phase => 'configure' }, 'Module::Build::Tiny' => $self->version);

	return;
}

sub setup_installer {
	my ($self, $arg) = @_;

	confess "Module::Build::Tiny is currently incompatible with dynamic_config" if $self->zilla->distmeta->{dynamic_config};

  $self->log_fatal('unsupported use of a sharedir') if any {
    my $share_dir_map = $_->share_dir_map;
    exists $share_dir_map->{module} or
			(defined $share_dir_map->{dist} and $share_dir_map->{dist} ne 'share')
  } @{$self->zilla->plugins_with(-ShareDir)};

	my $content = $self->fill_in_string($template, { version => $self->version, minimum_perl => $self->minimum_perl });
	my $file = Dist::Zilla::File::InMemory->new({ name => 'Build.PL', content => $content });
	$self->add_file($file);

	return;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;

# ABSTRACT: Build a Build.PL that uses Module::Build::Tiny

=head1 DESCRIPTION

This plugin will create a F<Build.PL> for installing the dist using L<Module::Build::Tiny>.

=cut

=attr version

B<Optional:> Specify the minimum version of L<Module::Build::Tiny> to depend on.

Defaults to the version installed on the author's perl installation

=attr minimum_perl

B<Optional:> Specify the minimum version of perl to require in the F<Build.PL>.

This is normally taken from dzils prereq metadata.

# vim: set ts=2 sw=2 noet nolist :
