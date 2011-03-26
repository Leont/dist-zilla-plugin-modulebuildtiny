package Dist::Zilla::Plugin::ModuleBuildTiny;

use Moose;
with qw/Dist::Zilla::Role::BuildPL Dist::Zilla::Role::TextTemplate/;

use Dist::Zilla::File::InMemory;

has version => (
	isa => 'Str',
	is  => 'rw',
	default => '0.006',
);

my $template = "use Module::Build::Tiny {{ \$version }};\nBuild_PL(\@ARGV);\n";

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
