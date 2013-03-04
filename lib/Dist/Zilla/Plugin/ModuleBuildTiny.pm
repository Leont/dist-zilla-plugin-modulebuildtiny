package Dist::Zilla::Plugin::ModuleBuildTiny;

use Moose;
with qw/Dist::Zilla::Role::BuildPL Dist::Zilla::Role::TextTemplate Dist::Zilla::Role::PrereqSource/;
use Module::Metadata;

use Dist::Zilla::File::InMemory;

use version;
use MooseX::Types::Perl qw(VersionObject);

has version => (
	is  => 'ro',
	isa => VersionObject,
	default => sub {
		return Module::Metadata->new_from_module('Module::Build::Tiny')->version;
	},
	coerce => 1,
);

my $template = "use Module::Build::Tiny {{ \$version }};\nBuild_PL();\n";

sub register_prereqs {
	my ($self) = @_;

	$self->zilla->register_prereqs({ phase => 'configure' }, 'Module::Build::Tiny' => $self->version);

	return;
}

sub setup_installer {
	my ($self, $arg) = @_;

	my $content = $self->fill_in_string($template, { version => $self->version });
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

