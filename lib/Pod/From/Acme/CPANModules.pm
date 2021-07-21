package Pod::From::Acme::CPANModules;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Exporter qw(import);
our @EXPORT_OK = qw(gen_pod_from_acme_cpanmodules);

our %SPEC;

sub _markdown_to_pod {
    require Markdown::To::POD;
    Markdown::To::POD::markdown_to_pod(shift);
}

$SPEC{gen_pod_from_acme_cpanmodules} = {
    v => 1.1,
    summary => 'Generate POD from an Acme::CPANModules::* module',
    description => <<'_',

Currently what this routine does:

* Fill the Description section from the CPANModules' list description

* Add an "Acme::CPANModules Entries" section, containing the CPANModules' list entries

* Add an "Acme::CPANModules Feature Comparison Matrix" section, if one or more entries have 'features'

_
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
        entry_description_code => {
            schema => 'code*',
        },
    },
    result_naked => 1,
};
sub gen_pod_from_acme_cpanmodules {
    my %args = @_;

    my $res = {};
    if ($args{entry_description_code}) {
        if (ref $args{entry_description_code} ne 'CODE') {
            $args{entry_description_code} = eval "sub { $args{entry_description_code} }";
            die "Can't compile Perl code in entry_description_code argument: $@" if $@;
        }
    }

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

        my @mods;
        for my $ent (@{ $list->{entries} }) {
            push @mods, $ent->{module};
        }

        my %mod_abstracts; # key: module name, value: abstract
      GET_MODULE_ABSTRACTS: {
            last unless @mods;
            require App::lcpan::Call;
            my $res = App::lcpan::Call::check_lcpan();
            unless ($res->[0] == 200) {
                log_info "lcpan database is not available (%s), skipping retrieving module abstracts", $res;
                last;
            }
            $res = App::lcpan::Call::call_lcpan_script(argv=>["mods", "-l", "-x", "--or", @mods]);
            unless ($res->[0] == 200) {
                log_info "Can't lcpan mods: %s, skipping retrieving module abstracts", $res;
                last;
            }
            for (@{$res->[2]}) {
                $mod_abstracts{ $_->{module} } = $_->{abstract} if defined $_->{abstract} && length $_->{abstract};
            }
        }

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
                my $summary = $ent->{summary} //
                    (defined $mod_abstracts{$ent->{module}} ?
                     #"$mod_abstracts{$ent->{module}} (from module's Abstract)" :
                     "$mod_abstracts{$ent->{module}}" :
                     undef);
                $pod .= "=item * L<$ent->{module}>".($summary ? " - $summary" : "")."\n\n";
                if ($args{entry_description_code}) {
                    my $res;
                    {
                        local $_ = $ent;
                        $res = $args{entry_description_code}->($ent);
                    }
                    $pod .= $res;
                } else {
                    $pod .= _markdown_to_pod($ent->{description})."\n\n"
                        if $ent->{description} && $ent->{description} =~ /\S/;
                    $pod .= "Rating: $ent->{rating}/10\n\n"
                        if $ent->{rating} && $ent->{rating} =~ /\A[1-9]\z/;
                    $pod .= "Related modules: ".join(", ", map {"L<$_>"} @{ $ent->{related_modules} })."\n\n"
                        if $ent->{related_modules} && @{ $ent->{related_modules} };
                    $pod .= "Alternate modules: ".join(", ", map {"L<$_>"} @{ $ent->{alternate_modules} })."\n\n"
                        if $ent->{alternate_modules} && @{ $ent->{alternate_modules} };

                    my @scripts;
                    for ("script", "scripts") {
                        push @scripts, (ref $ent->{$_} eq 'ARRAY' ? @{$ent->{$_}} : $ent->{$_}) if defined $ent->{$_};
                    }
                    if (@scripts) {
                        $pod .= "Script".(@scripts > 1 ? "s":"").": ".join(", ", map {"L<$_>"} @scripts)."\n\n";
                    }
                }
            }
            $pod .= "=back\n\n";
            $res->{pod}{'ACME::CPANMODULES ENTRIES'} .= $pod;
        }

        {
            require Acme::CPANModulesUtil::FeatureMatrix;
            my $fres = Acme::CPANModulesUtil::FeatureMatrix::draw_feature_matrix(_list => $list);
            last if $fres->[0] != 200;
            $res->{pod}{'ACME::CPANMODULES FEATURE COMPARISON MATRIX'} = $fres->[2];
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
