use Test::More;
BEGIN { SKIP: { eval { require Test::Warnings; 1; } or skip($@, 1); } }
BEGIN { eval { require 'ddclient'; } or BAIL_OUT($@); }
use re qw(is_regexp);

my %variable_collections = (
    map({ ($_ => $ddclient::cfgvars{$_}) } grep($_ ne 'merged', keys(%ddclient::cfgvars))),
    map({ ("protocol=$_" => $ddclient::protocols{$_}{cfgvars}); } keys(%ddclient::protocols)),
);
my %seen;
my @test_cases = (
    map({
        my $vcn = $_;
        my $vc = $variable_collections{$_};
        map({
            my $def = $vc->{$_};
            my $seen = exists($seen{$def});
            $seen{$def} = undef;
            ({desc => "$vcn $_", def => $vc->{$_}}) x !$seen;
        } sort(keys(%$vc)));
    } sort(keys(%variable_collections))),
);
for my $tc (@test_cases) {
    if ($tc->{def}{required}) {
        is($tc->{def}{default}, undef, "'$tc->{desc}' (required) has no default");
    } else {
        # Preserve all existing variables in $cfgvars{merged} so that variables with dynamic
        # defaults can reference them.
        local %ddclient::cfgvars = (merged => {
            %{$ddclient::cfgvars{merged}},
            'var for test' => $tc->{def},
        });
        # Variables with dynamic defaults will need their own unit tests, but we can still check the
        # clean-slate hostless default.
        local %ddclient::config;
        local %ddclient::opt;
        local %ddclient::globals;
        my $norm;
        my $default = ddclient::default('var for test');
        diag("'$tc->{desc}' default: " . ($default // '<undefined>'));
        is($default, $tc->{def}{default}, "'$tc->{desc}' default() return value matches default")
            if ref($tc->{def}{default}) ne 'CODE';
        my $valid = eval { $norm = ddclient::check_value($default, $tc->{def}); 1; } or diag($@);
        ok($valid, "'$tc->{desc}' (optional) has a valid default");
        is($norm, $default, "'$tc->{desc}' default normalizes to itself") if $valid;
    }
}

my @use_test_cases = (
    {
        desc => 'clean slate hostless default',
        want => 'ip',
    },
    {
        desc => 'usage string',
        host => '<usage>',
        want => qr/disabled.*ip|ip.*disabled/,
    },
    {
        desc => 'usev4 disables use by default',
        host => 'host',
        cfg => {usev4 => 'webv4'},
        want => 'disabled',
    },
    {
        desc => 'usev6 disables use by default',
        host => 'host',
        cfg => {usev4 => 'webv4'},
        want => 'disabled',
    },
    {
        desc => 'explicitly setting use re-enables it',
        host => 'host',
        cfg => {use => 'web', usev4 => 'webv4'},
        want => 'web',
    },
);
for my $tc (@use_test_cases) {
    my $desc = "'use' dynamic default: $tc->{desc}";
    local %ddclient::protocols = (protocol => ddclient::Protocol->new());
    local %ddclient::cfgvars = (merged => {
        'protocol' => $ddclient::cfgvars{'merged'}{'protocol'},
        'use' => $ddclient::cfgvars{'protocol-common-defaults'}{'use'},
        'usev4' => $ddclient::cfgvars{'merged'}{'usev4'},
        'usev6' => $ddclient::cfgvars{'merged'}{'usev6'},
    });
    local %ddclient::config = (host => {protocol => 'protocol', %{$tc->{cfg} // {}}});
    local %ddclient::opt;
    local %ddclient::globals;

    my $got = ddclient::opt('use', $tc->{host});

    if (is_regexp($tc->{want})) {
        like($got, $tc->{want}, $desc);
    } else {
        is($got, $tc->{want}, $desc);
    }
}

done_testing();
