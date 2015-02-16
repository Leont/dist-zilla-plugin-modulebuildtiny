package Dist::Zilla::Plugin::ModuleBuildTiny;

use Moose;
with qw/
	Dist::Zilla::Role::BuildPL
	Dist::Zilla::Role::TextTemplate
	Dist::Zilla::Role::PrereqSource
	Dist::Zilla::Role::FileGatherer
/;

use Module::Metadata;
use MooseX::Types::Perl qw/StrictVersionStr/;
use List::Util qw/first/;

has version => (
	is      => 'ro',
	isa     => StrictVersionStr,
	default => sub {
		return Module::Metadata->new_from_module('Module::Build::Tiny')->version->stringify;
	},
);

has minimum_perl => (
	is      => 'ro',
	isa     => StrictVersionStr,
	lazy    => 1,
	default => sub {
		my $self = shift;
		my $prereqs = $self->zilla->prereqs;
		my $perl_prereq = $prereqs->requirements_for(qw(runtime requires))
			->clone
			->add_requirements($prereqs->requirements_for(qw(configure requires)))
			->add_requirements($prereqs->requirements_for(qw(build requires)))
			->add_requirements($prereqs->requirements_for(qw(test requires)))
			->as_string_hash->{perl};
		$perl_prereq || '5.006';
	},
);

my $template = <<'BUILD_PL';
# This Build.PL for {{ $dist_name }} was generated by {{ $plugin_title }}.
use strict;
use warnings;

use {{ $minimum_perl }};
use Module::Build::Tiny {{ $version }};
Build_PL();
BUILD_PL

sub register_prereqs {
	my ($self) = @_;

	$self->zilla->register_prereqs({ phase => 'configure' }, 'Module::Build::Tiny' => $self->version);

	return;
}

sub gather_files {
	my ($self) = @_;

	if (my $file = first { $_->name eq 'Build.PL' } @{$self->zilla->files})
	{
		# if it's another type, some other plugin added it, so it's better to
		# error out and let the developer sort out what went wrong.
		if ($file->isa('Dist::Zilla::File::OnDisk'))
		{
			$self->log('replacing existing Build.PL found in repository');
			$self->zilla->prune_file($file);
		}
	}

	require Dist::Zilla::File::InMemory;
	my $file = Dist::Zilla::File::InMemory->new({
		name => 'Build.PL',
		content => $template,	# template evaluated later
	});

	$self->add_file($file);
	return;
}

sub setup_installer {
	my ($self, $arg) = @_;

	confess "Module::Build::Tiny is currently incompatible with dynamic_config" if $self->zilla->distmeta->{dynamic_config};

	for my $map (map { $_->share_dir_map } @{$self->zilla->plugins_with(-ShareDir)}) {
		$self->log_fatal('Unsupported use of a module sharedir') if exists $map->{module};
		$self->log_fatal('Sharedir location must be share/') if defined $map->{dist} and $map->{dist} ne 'share';
	}

	my $file = first { $_->name eq 'Build.PL' } @{$self->zilla->files};
	my $content = $file->content;

	$content = $self->fill_in_string($content, {
			version      => $self->version,
			minimum_perl => $self->minimum_perl,
			dist_name    => $self->zilla->name,
			plugin_title => ref($self) . ' ' . ($self->VERSION || '<self>'),
		});

	$self->log_debug([ 'updating contents of Build.PL in memory' ]);
	$file->content($content);

	return;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;

# ABSTRACT: Build a Build.PL that uses Module::Build::Tiny

=head1 DESCRIPTION

This plugin will create a F<Build.PL> for installing the dist using L<Module::Build::Tiny>.

=attr version

B<Optional:> Specify the minimum version of L<Module::Build::Tiny> to depend on.

Defaults to the version installed on the author's perl installation

=attr minimum_perl

B<Optional:> Specify the minimum version of perl to require in the F<Build.PL>.

This is normally taken from dzil's prereq metadata.

=cut

# vim: set ts=4 sw=4 noet nolist :
