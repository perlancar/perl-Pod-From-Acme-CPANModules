package Pod::From::Acme::CPANModules;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(gen_pod_from_acme_cpanmodules);

our %SPEC;

sub _markdown_to_pod {
    require Markdown::To::POD;
    Markdown::To::POD::markdown_to_pod(shift);
}

$SPEC{gen_pod_from_acme_cpanmodules} = {
    v => 1.1,
    summary => 'Create "INCLUDED MODULES" POD sections from $LIST',
    args_rels => {
        req_one => [qw/module author_lists/],
        choose_all => [qw/author_lists module_lists/],
    },
    args => {
        module => {
            name => 'Module name, e.g. Acme::CPANLists::PERLANCAR',
            schema => 'str*',
        },
        list => {
            summary => 'As an alternative to `module`, you can directly supply $LIST here',
            schema => 'hash*',
        },
    },
    result_naked => 1,
};
sub gen_pod_from_acme_cpanmodules {
    my %args = @_;

    my $res = {};

    my $list = $args{list};
    if (my $mod = $args{module}) {
        no strict 'refs';
        my $mod_pm = $mod; $mod_pm =~ s!::!/!g; $mod_pm .= ".pm";
        require $mod_pm;
        $list = ${"$mod\::LIST"};
        ref($list) eq 'HASH' or die "Module $mod doesn't defined \$LIST";
    }

    $res->{raw} = $list;

    if ($list) {
        $res->{pod} = {};

        {
            my $pod = '';
            $pod .= _markdown_to_pod($list->{description})."\n\n"
                if $list->{description} && $list->{description} =~ /\S/;
            $res->{pod}{DESCRIPTION} = $pod if $pod;
        }

        {
            my $pod = '';
            $pod .= "=over\n\n";
            for my $ent (@{ $list->{entries} }) {
                $pod .= "=item * L<$ent->{module}>".($ent->{summary} ? " - $ent->{summary}" : "")."\n\n";
                $pod .= _markdown_to_pod($ent->{description})."\n\n"
                    if $ent->{description} && $ent->{description} =~ /\S/;
                $pod .= "Rating: $ent->{rating}/10\n\n"
                    if $ent->{rating} && $ent->{rating} =~ /\A[1-9]\z/;
                $pod .= "Related modules: ".join(", ", map {"L<$_>"} @{ $ent->{related_modules} })."\n\n"
                    if $ent->{related_modules} && @{ $ent->{related_modules} };
                $pod .= "Alternate modules: ".join(", ", map {"L<$_>"} @{ $ent->{alternate_modules} })."\n\n"
                    if $ent->{alternate_modules} && @{ $ent->{alternate_modules} };
            }
            $pod .= "=back\n\n";
            $res->{pod}{'INCLUDED MODULES'} .= $pod;
        }

        {
            require Acme::CPANModulesUtil::FeatureMatrix;
            my $fres = Acme::CPANModulesUtil::FeatureMatrix::draw_feature_matrix(_list => $list);
            last if $fres->[0] != 200;
            $res->{pod}{'FEATURE COMPARISON MATRIX'} = $fres->[2];
        }

    }

    $res;
}

1;
# ABSTRACT:

=head1 SYNOPSIS

 use Pod::From::Acme::CPANModules qw(gen_pod_from_acme_cpanmodules);

 my $res = gen_pod_from_acme_cpanmodules(module => 'Acme::CPANModules::PERLANCAR::Favorites');

=cut
