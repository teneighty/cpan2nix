use strict;
use warnings;

package QuietShell;

sub myprint { }
sub myexit { }
sub mywarn { }
sub mydie { }
sub mysleep { }

package MAIN;

use Getopt::Long;
use Pod::Usage;
use CPAN;
use Cwd;
use YAML;

my ($help) = (0, 0);
my $cpan_base = "http://search.cpan.org/CPAN/authors/id/";
my $nix_exprs = {};

sub split_cpan_name {
    return ($1, $2) if ($_[0] =~ m/(.*)\/(.*?).tar.gz/);
}

sub trim {
    return $1 if $_[0] =~ m/^\s*(.*?)\s*$/;
}

sub nix_prefetch_url {
    my ($url) = @_;

    print STDERR "$cpan_base$url\n";
    my $sha = `nix-prefetch-url $cpan_base$url`;
    chomp $sha;
    return (split /\n/, $sha)[-1];
}

sub name_to_nix {
    my ($name) = @_;
    $name =~ s/-?(\d|\.)+$//g; # remove version
    $name =~ s/-//g;           # remove dashes
    return $name;
}

sub find_prereqs {
    my ($pack) = @_;

    $pack->get;
    my $yaml = $pack->parse_meta_yml();
    my $config = $yaml->{requires};
    my $reqs = "";
    for my $p (sort (keys %$config)) {
        my $bid = load_expression($p);
        if ($bid && $nix_exprs->{$bid} && $nix_exprs->{$bid}->{name}) {
            $reqs .= $nix_exprs->{$bid}->{name} . " ";
        }
    }
    return "\n    buildInput = [" . trim($reqs) . "];" if $reqs;
}

sub load_expression {
    my ($mod) = @_;

    my @ms = CPAN::Shell->expand("Module", $mod);
    $CPAN::Config->{keep_source_where} = File::Spec->catfile(cwd(), "sources");
    for my $m (@ms) {
        my $pack = $CPAN::META->instance('CPAN::Distribution', $m->cpan_file);
        my $base_id = $pack->base_id;

        # perl-.* should already be installed
        return if $base_id =~ m/^perl.*/;

        # prevent infinite recursion
        next if $nix_exprs->{$base_id};
        print STDERR "Loading $mod\n";
        $nix_exprs->{$base_id} = {};

        my ($path, $name) = split_cpan_name($m->cpan_file);
        my $exp_name = name_to_nix($name);
        my $exp_preqs = find_prereqs($pack);
        my $sha = nix_prefetch_url($m->cpan_file);

        $nix_exprs->{$base_id}->{name} = $exp_name;
        $nix_exprs->{$base_id}->{expr} = <<EOF
  $exp_name = buildPerlPackage rec {
    name = "$name";
    src = fetchurl {
      url = "mirror://cpan/authors/id/$path/\${name}.tar.gz";
      sha256 = "$sha";
    }; $exp_preqs
  };
EOF
        ;
        return $base_id;
    }
}

GetOptions('help' => \$help) or pod2usage(2);
pod2usage(1) if $help;

CPAN::HandleConfig->load unless $CPAN::Config_loaded++;

# Overwrite user's config
$CPAN::Be_Silent = 1;
$CPAN::Config->{keep_source_where} = "sources";
$CPAN::Config->{prerequisites_policy} = "follow";
$CPAN::Frontend = "QuietShell";

for my $a (@ARGV) {
    load_expression($a);
}

for my $k (sort (keys %$nix_exprs)) {
    print $nix_exprs->{$k}->{expr}, "\n";
}

__END__

=head1 NAME

cpan2nix.pl

=head1 SYNOPSIS

B<cpan2nix.pl> S<[ B<-h> ]> 

=head1 DESCRIPTION

Creates the nix expressions for a cpan module. cpan2nix attempts to resolve
build nix expressions for dependencies.

=head1 OPTIONS

=over 4

=item B<-h>, B<--help>

Help: Print the usage.

=back

=head1 AUTHOR

Tim Horton

=cut

