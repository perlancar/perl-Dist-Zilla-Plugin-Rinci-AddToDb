package Dist::Zilla::Plugin::Rinci::AddToDb;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Moose;
with (
    'Dist::Zilla::Role::FileFinderUser' => {
        default_finders => [':InstallModules', ':ExecFiles'],
    },
    'Dist::Zilla::Role::AfterBuild',
    'Dist::Zilla::Role::DumpPerinciCmdLineScript',
    'Dist::Zilla::Role::Rinci::CheckDefinesMeta',
);

use App::rimetadb;
use Data::Clean::JSON;
use Perinci::Sub::Normalize qw(normalize_function_metadata);

has dsn      => (is => 'rw');
has username => (is => 'rw');
has password => (is => 'rw');

my $cleanser = Data::Clean::JSON->get_cleanser;

sub after_build {
    my $self = shift;

    return unless $self->check_dist_defines_rinci_meta;
    $self->process_file($_) for @{ $self->found_files };
}

sub _add_metas {
    my ($self, $pkg, $spec, $normalize, $extra) = @_;

    my %updargs = (
        (dsn => $self->dsn          ) x !!(defined $self->dsn),
        (username => $self->username) x !!(defined $self->username),
        (password => $self->password) x !!(defined $self->password),
        (extra => $extra)             x !!(defined $extra),
        dist => $self->zilla->name,
    );

    for my $k (sort keys %$spec) {
        my $is_package = $k =~ /\A:package/;
        my $meta = $spec->{$k};
        $meta = normalize_function_metadata($meta) if $normalize && !$is_package;
        $meta = $cleanser->clone_and_clean($meta);

        if ($is_package) {
            $self->log_debug("Adding Rinci package metadata $pkg");
            App::rimetadb::update(
                %updargs,
                package=>$pkg,
                metadata=>$meta,
            );
        } elsif ($k =~ /\A\w+\z/) {
            $self->log_debug("Adding Rinci function metadata $pkg\::$k");
            App::rimetadb::update(
                %updargs,
                package=>$pkg,
                function=>$k,
                metadata=>$meta,
            );
        } else {
            $self->log_debug("Skipped Rinci metadata $pkg\::$k (not a function or package)");
            next;
        }
    }
}

sub process_file {
    no strict 'refs';

    my ($self, $file) = @_;

    local @INC = ('lib', @INC);

    if (my ($pkg_pm, $pkg) = $file->name =~ m!^lib/((.+)\.pm)$!) {
        $pkg =~ s!/!::!g;
        require $pkg_pm;
        $self->_add_metas($pkg, \%{"$pkg\::SPEC"});
    } else {
        my $res = $self->dump_perinci_cmdline_script($file);
        if ($res->[0] == 412) {
            $self->log_debug(["Skipped %s: %s", $file->name, $res->[1]]);
            return;
        }
        $self->log_fatal(["Can't dump Perinci::CmdLine script '%s': %s - %s",
                          $file->name, $res->[0], $res->[1]]) unless $res->[0] == 200;
        return unless $res->[3]{'func.meta'};
        $self->_add_metas("main", $res->[3]{'func.meta'}, 1, 'script='.$file->name);
    }
}

__PACKAGE__->meta->make_immutable;
1;
# ABSTRACT: Add Rinci metadata to database

=for Pod::Coverage .+

=head1 SYNOPSIS

In F<dist.ini>:

 [Rinci::AddToDb]
 ;dsn=...
 ;username=...
 ;password=...


=head1 DESCRIPTION

This plugin will search Rinci metadata in all modules and scripts, and add them
to database using L<rimetadb>. Later, you can gather various statistics from the
database, e.g. average number of arguments per function, top argument types,
etc.


=head1 SEE ALSO

L<Rinci>

L<App::rimetadb>
