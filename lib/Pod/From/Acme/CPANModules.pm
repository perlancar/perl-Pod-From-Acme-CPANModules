package Pod::From::Acme::CPANModules;

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Exporter qw(import);

# AUTHORITY
# DATE
# DIST
# VERSION

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
            description => <<'_',

This lets you completely customize the description POD for each entry, using Perl
code. The Perl code will receive the entry hashref as its argument and is expected to produce
a POD string.

See also the `additional_props` option.

_
        },
        additional_props => {
            schema => ['array*', of=>'str*'],
            description => <<'_',

This lets you include additional properties (or attributes) from the entry
defhash to the POD. This option will not be used if you completely customize the
entry POD output using the `entry_description_code` option. This option is an
alternative when you want to display some additional properties/attributes in
the entry as POD but does not want to completely customize the POD yourself.

The element of this option is property/attribute name, optionally followed by
":..." suffix to set the caption to show it with, then optionally followed by
formatting suffix:

- ":url" to render it as a link (`L<...>`)
- ":mono" suffix to render it in monospace characters (`C<...>`)
- ":quoted" (the default) to render it normally but quote it first using
  <pm:String::PodQuote>
- ":perl:..." to let a Perl code format it.

Example:

    # option
    additional_props => [
        q(ruby_package:Ruby project's gem:perl:"https://rubygems.org/gems/$_[0]"),
        "ruby_website_url:Ruby project's website:url",
    ],

with this entry:

    {
        module => "Valiant",
        ruby_package => "rails",
        ruby_website_url => "https://rubyonrails.org",
    }

the additional POD produced will be something like:

    Ruby project's gem: L<https://rubygems.org/gems/rails>

    Ruby project's website: L<https://rubyonrails.org>

See also the `entry_description_code` option.

_
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
        my %mod_authors; # key: module name, value: author
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
                $mod_authors{ $_->{module} } = $_->{author};
            }
        }

        {
            my $pod = '';
            $pod .= _markdown_to_pod($list->{description})."\n\n"
                if $list->{description} && $list->{description} =~ /\S/;
            $res->{pod}{DESCRIPTION} = $pod if $pod;
        }

        {
            require String::PodQuote;

            my $pod = '';
            $pod .= "=over\n\n";
            my $i = -1;
            for my $ent (@{ $list->{entries} }) {
                $i++;
                my $summary = $ent->{summary} //
                    (defined $mod_abstracts{$ent->{module}} ?
                     #"$mod_abstracts{$ent->{module}} (from module's Abstract)" :
                     "$mod_abstracts{$ent->{module}}" :
                     undef);
                $pod .= "=item L<$ent->{module}>\n\n";
                if (defined $ent->{summary}) {
                    $pod .= String::PodQuote::pod_quote($ent->{summary}) . ".\n\n";
                }
                if ($args{entry_description_code}) {
                    my $res;
                    {
                        local $_ = $ent;
                        $res = $args{entry_description_code}->($ent);
                    }
                    $pod .= $res;
                } else {
                    my $author = $mod_authors{$ent->{module}};
                    if ($author) {
                        $pod .= "Author: L<$author|https://metacpan.org/author/$author>\n\n";
                    }
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

                    if ($args{additional_props}) {
                      PROP:
                        for my $prop0 (@{ $args{additional_props} }) {
                            my $prop = $prop0;
                            my $title;
                            $prop =~ s/\A(.+?)\:([^:]*)/$1/ and $title = $2;
                            $title //= $prop;
                            my $format;
                            $prop =~ s/\:(.+)\z// and $format = $1;
                            $format //= "quoted";
                            unless (exists $ent->{$prop}) {
                                log_trace "Entry does not have '%s' property/attribute, not adding it to POD output";
                                next PROP;
                            }
                            $pod .= "$title: ";
                            if ($format eq 'quoted') {
                                $pod .= String::PodQuote::pod_quote($ent->{$prop});
                            } elsif ($format eq 'url') {
                                $pod .= "L<$ent->{$prop}>";
                            } elsif ($format eq 'mono') {
                                $pod .= "C<$ent->{$prop}>";
                            } elsif ($format =~ /\Aperl:(.+)/) {
                                # XXX perl code is re-eval()-ed for each entry
                                my $code0 = "package main; no strict; no warnings; sub { $1 }";
                                my $code = eval $code0;
                                die "Cannot eval '$code0' for property '$prop' in entry[$i] (module $ent->{module}): $@" if $@;
                                $pod .= $code->($ent->{$prop});
                            } else {
                                die "Unknown format '$format' for property '$prop' in entry[$i] (module $ent->{module})";
                            }
                            $pod .= "\n\n";
                        }
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
