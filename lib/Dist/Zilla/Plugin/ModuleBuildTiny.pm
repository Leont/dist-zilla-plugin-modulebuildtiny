package Dist::Zilla::Plugin::ModuleBuildTiny;

use 5.020;

use Moose;
with qw/
	Dist::Zilla::Role::BuildPL
	Dist::Zilla::Role::TextTemplate
	Dist::Zilla::Role::PrereqSource
	Dist::Zilla::Role::FileGatherer
	Dist::Zilla::Role::MetaProvider
/;

use experimental qw/signatures postderef/;

use Dist::Zilla 4.300039;
use Module::Metadata;
use Moose::Util::TypeConstraints 'enum';
use MooseX::Types::Perl qw/StrictVersionStr/;
use MooseX::Types::Moose qw/Bool Str ArrayRef/;
use List::Util 1.33 qw/first any/;

sub mvp_multivalue_args { qw(header_strs footer_strs) }

sub mvp_aliases {
    +{
        header => 'header_strs',
        footer => 'footer_strs',
    }
}

around BUILDARGS => sub($orig, $class, @args) {
    my $args = $class->$orig(@args);

    my $delimiter = delete $args->{delimiter};
    if (defined $delimiter and length($delimiter)) {
        foreach my $arg (grep exists $args->{$_}, qw(header_strs footer_strs)) {
            s/^\Q$delimiter\E// foreach $args->{$arg}->@*;
        }
    }

    return $args;
};

has version_method => (
	is      => 'ro',
	isa     => enum(['installed', 'conservative']),
	default => 'conservative',
);

has has_pl => (
	is      => 'ro',
	isa     => Bool,
	lazy    => 1,
	default => sub($self) {
		return any { $_->name =~ /^lib\/.*\.PL$/ } $self->zilla->files->@*;
	},
);

has has_xs => (
	is      => 'ro',
	isa     => Bool,
	lazy    => 1,
	default => sub($self) {
		return any { $_->name =~ /^lib\/.*\.xs$/ } $self->zilla->files->@*;
	},
);

has static => (
	is      => 'ro',
	isa     => enum([qw/no yes auto/]),
	default => 'no',
);

has version => (
	is      => 'ro',
	lazy    => 1,
	isa     => StrictVersionStr,
	default => sub($self) {
		if ($self->version_method eq 'installed') {
			return Module::Metadata->new_from_module('Module::Build::Tiny')->version->stringify;
		}
		elsif (-e 'include/' or any { $_->name =~ /^src\/.*\.c$/} $self->zilla->files->@*) {
			return '0.044';
		}
		elsif ($self->has_pl) {
			return '0.039';
		}
		elsif ($self->has_xs) {
			return '0.036';
		}
		return '0.034'; # _build_params format
	},
);

has minimum_perl => (
	is      => 'ro',
	isa     => StrictVersionStr,
	lazy    => 1,
	default => sub($self) {
		my $prereqs = $self->zilla->prereqs->cpan_meta_prereqs;
		my $reqs = $prereqs->merged_requirements([ qw/configure build test runtime/ ], ['requires']);
		return $reqs->requirements_for_module('perl') || '5.006';
	},
);

has header_strs => (
	is => 'ro',
	isa => ArrayRef[Str],
	traits => ['Array'],
	lazy => 1,
	default => sub { [] },
	documentation => "Additional code lines to include at the beginning of Makefile.PL",
);

has header_file => (
	is => 'ro', isa => Str,
	documentation => 'Additional header content to include from a file',
);

has header => (
	is            => 'ro',
	isa           => Str,
	lazy          => 1,
	builder       => '_build_header',
	documentation => "A string included at the beginning of Makefile.PL",
);

sub _build_header($self) {
	join "\n",
		$self->header_strs->@*,
		( $self->header_file
			? do {
				my $abs_file = path($self->zilla->root, $self->header_file);
				$self->log_fatal([ 'header_file %s does not exist!', $self->header_file ])
					if not $abs_file->exists;
				$abs_file->slurp_utf8
			}
			: () );
}

has footer_strs => (
	is => 'ro',
	isa => ArrayRef[Str],
	traits => ['Array'],
	lazy => 1,
	default => sub { [] },
	documentation => "Additional code lines to include at the end of Makefile.PL",
);

has footer_file => (
	is => 'ro', isa => Str,
	documentation => 'Additional footer content to include from a file',
);

has footer => (
	is			=> 'ro',
	isa		   => Str,
	lazy		  => 1,
	builder	   => '_build_footer',
	documentation => "A string included at the end of Makefile.PL",
);

sub _build_footer($self) {
	join "\n",
		$self->footer_strs->@*,
		( $self->footer_file
			? do {
				my $abs_file = path($self->zilla->root, $self->footer_file);
				$self->log_fatal([ 'footer_file %s does not exist!', $self->footer_file ])
					if not $abs_file->exists;
				$abs_file->slurp_utf8
			}
			: () );
}

has auto_configure_requires => (
	is => 'ro',
	isa => Bool,
	default => 1,
);

my $template = <<'BUILD_PL';
# This Build.PL for {{ $dist_name }} was generated by {{ $plugin_title }}.
use strict;
use warnings;

{{ $header }}
use {{ $minimum_perl }};
use Module::Build::Tiny{{ $version ne 0 && " $version" }};
Build_PL();
{{ $footer }}
BUILD_PL

sub register_prereqs($self) {
	if ($self->auto_configure_requires) {
		$self->zilla->register_prereqs({ phase => 'configure' }, 'Module::Build::Tiny' => $self->version);
	}

	return;
}

sub can_static($self) {
	return !$self->has_pl && !$self->has_xs;
}

sub metadata($self) {
	my $static = $self->static eq 'yes' || $self->static eq 'auto' && $self->can_static;
	return $static ? { x_static_install => 1 } : ();
}

sub gather_files($self) {
	if (my $file = first { $_->name eq 'Build.PL' } $self->zilla->files->@*)
	{
		# if it's another type, some other plugin added it, so it's better to
		# error out and let the developer sort out what went wrong.
		if ($file->isa('Dist::Zilla::File::OnDisk')) {
			$self->log('replacing existing Build.PL found in repository');
			$self->zilla->prune_file($file);
		}
	}

	require Dist::Zilla::File::InMemory;
	my $file = Dist::Zilla::File::InMemory->new({
		name => 'Build.PL',
		content => $template,    # template evaluated later
	});

	$self->add_file($file);
	return;
}

sub setup_installer($self) {
	confess 'Module::Build::Tiny is currently incompatible with dynamic_config' if $self->zilla->distmeta->{dynamic_config};

	for my $map (map { $_->share_dir_map } $self->zilla->plugins_with(-ShareDir)->@*) {
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
			header       => $self->header,
			footer       => $self->footer,
		});

	$self->log_debug([ 'updating contents of Build.PL in memory' ]);
	$file->content($content);

	return;
}

__PACKAGE__->meta->make_immutable;
no Moose::Util::TypeConstraints;
no Moose;
1;

# ABSTRACT: Build a Build.PL that uses Module::Build::Tiny

=head1 DESCRIPTION

This plugin will create a F<Build.PL> for installing the dist using L<Module::Build::Tiny|Module::Build::Tiny>.

=attr version

B<Optional:> Specify the minimum version of L<Module::Build::Tiny|Module::Build::Tiny> to depend on.

Defaults to the version determined by C<version_method>.

=attr version_method

This attribute determines how the default minimum perl is detected. It has two possible values:

=over 4

=item * installed

This will give the version installed on the author's perl installation.

=item * conservative

This will return a heuristically determined minimum version of MBT.

=back

=attr minimum_perl

B<Optional:> Specify the minimum version of perl to require in the F<Build.PL>.

This is normally taken from dzil's prereq metadata.

=attr static

This is an option to set the B<HIGHLY EXPERIMENTAL> C<x_static_install>
metadata field. B<DO NOT USE THIS OPTION> if you are not involved in its
testing with the Perl Toolchain Gang.

It has three possible values:

=over 4

=item * no

No extra metadata is added. This is the default setting.

=item * yes

Sets C<x_static_install = 1> in metadata.

=item * auto

Sets C<x_static_install = 1> in metadata if the distribution appears to be
compatible - presently only the existence of F<.PL> and F<.xs> files are
checked.

=back

=attr header

A line of code which is included near the top of F<Build.PL>.  Can be used more than once.

=attr footer

A line of code which is included at the bottom of F<Build.PL>.  Can be used more than once.

=attr delimiter

A string, usually a single character, which is stripped from the beginning of
all C<header>, and C<footer> lines. This is because the
INI file format strips all leading whitespace from option values, so including
this character at the front allows you to use leading whitespace in an option
string.  This is helpful for the formatting of F<Build.PL>s, but a nice thing
to have when inserting any block of code.

=cut

# vim: set ts=4 sw=4 noet nolist :
