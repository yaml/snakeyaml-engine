#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Cwd qw(getcwd);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3;
use JSON::PP qw(decode_json);
use MIME::Base64 qw(encode_base64);
use Symbol qw(gensym);

my $source = getcwd;
my $make = $ENV{MAKE} // 'make';
make_path('.cache');

sub write_file {
    my ($path, $value) = @_;
    open my $output, '>', $path or die "$path: $!";
    print {$output} $value;
    close $output or die "$path: $!";
}

sub read_file {
    my ($path) = @_;
    open my $input, '<', $path or die "$path: $!";
    local $/;
    return <$input>;
}

sub capture {
    my (@command) = @_;
    my $error = gensym;
    my $pid = open3(my $input, my $output, $error, @command);
    local $SIG{PIPE} = 'IGNORE';
    print {$input} ($ENV{ENGINE_TEST_ANSWER} // "y\n");
    close $input;
    local $/;
    my $log = (<$output> // '') . (<$error> // '');
    waitpid($pid, 0);
    return ($? >> 8, $log);
}

sub git {
    my ($root, @args) = @_;
    my ($status, $output) = capture('git', '-C', $root, @args);
    die "git @args: $output" if $status;
    $output =~ s/\n\z//;
    return $output;
}

sub fixture {
    my $root = File::Spec->rel2abs(
        tempdir('workflow-test-XXXXXX', DIR => '.cache', CLEANUP => 1));
    make_path("$root/util", "$root/src/changes", "$root/.cache/makes");
    for my $file (qw(Makefile pom.xml Fork.md util/maven-release
            src/changes/changes.xml)) {
        copy("$source/$file", "$root/$file") or die "$file: $!";
    }
    write_file("$root/.gitignore", ".cache/\n");
    my $maven = "$root/.cache/maven";
    write_file($maven, <<'PERL');
#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP qw(encode_json);
my $phase = grep($_ eq 'test', @ARGV) ? 'test' : 'deploy';
if ($phase eq 'test' && $ENV{ENGINE_TEST_TOUCH}) {
    open my $changed, '>>', $ENV{ENGINE_TEST_TOUCH} or die $!;
    print {$changed} "test modification\n";
    close $changed;
}
open my $pom, '<', 'pom.xml' or die $!;
my $source = do { local $/; <$pom> };
my ($version) = $source =~ m{<version>([^<]+)</version>};
open my $tags, '-|', 'git', 'tag', '--points-at', 'HEAD' or die $!;
my @tags = <$tags>;
close $tags or die $!;
chomp @tags;
open my $output, '>>', $ENV{ENGINE_TEST_LOG} or die $!;
print {$output} encode_json({phase => $phase, version => $version,
    tags => \@tags, args => \@ARGV}), "\n";
close $output;
exit($ENV{ENGINE_TEST_FAIL} // 0) if $phase eq 'test';
exit($ENV{ENGINE_DEPLOY_FAIL} // 0);
PERL
    chmod 0755, $maven or die $!;
    write_file("$root/.cache/makes/init.mk", '');
    write_file("$root/.cache/makes/maven.mk",
        "MAVEN := $maven\nMAVEN-REPOSITORY := $root/.cache/repository\n");
    write_file("$root/.cache/makes/perl.mk", "PERL := $^X\n");
    write_file("$root/.cache/makes/yamlscript.mk", "YS := $^X\n");
    write_file("$root/.cache/makes/$_.mk", '') for qw(shell clean);
    git($root, 'init', '--initial-branch=master');
    git($root, 'config', 'user.name', 'Release Test');
    git($root, 'config', 'user.email', 'release-test@example.invalid');
    git($root, 'config', 'commit.gpgsign', 'false');
    git($root, 'config', 'tag.gpgsign', 'false');
    git($root, 'config', 'core.hooksPath', '.git/no-hooks');
    git($root, 'config', 'core.excludesFile', File::Spec->devnull);
    git($root, 'add', '.');
    git($root, 'commit', '-m', 'Initial release fixture');
    return $root;
}

sub release {
    my ($root, $overrides, @args) = @_;
    local %ENV = %ENV;
    delete @ENV{qw(MAKEFLAGS MAKEOVERRIDES MAKEFILES GNUMAKEFLAGS MFLAGS
        MAKELEVEL ENGINE_TEST_FAIL
        ENGINE_DEPLOY_FAIL ENGINE_TEST_TOUCH ENGINE_RELEASE_ALLOW_BRANCH
        ENGINE_RELEASE_DRYRUN)};
    $ENV{CENTRAL_TOKEN} = encode_base64('fixture-user:fixture-password', '');
    $ENV{GPG_KEY_ID} = 'fixture-key';
    $ENV{MAVEN_GPG_PASSPHRASE} = '';
    $ENV{YS_SECRETS_FILE} = "$root/.cache/no-secrets";
    $ENV{ENGINE_TEST_LOG} = "$root/.cache/maven.log";
    @ENV{keys %$overrides} = values %$overrides;
    return capture($make, '--no-print-directory', '-C', $root,
        "M=$root/.cache/makes", "MAVEN=$root/.cache/maven",
        "MAVEN-REPOSITORY=$root/.cache/repository", "PERL=$^X", "YS=$^X",
        @args);
}

sub phases {
    my ($root) = @_;
    return [] unless -f "$root/.cache/maven.log";
    return [map { decode_json($_) }
        split /\n/, read_file("$root/.cache/maven.log")];
}

my ($current) = read_file('pom.xml') =~ m{<version>([^<]+)</version>};
my @parts = split /\./, $current;
my $next = join '.', $parts[0], $parts[1], $parts[2] + 1;

subtest 'preflight prevents mutations' => sub {
    my $root = fixture();
    my $head = git($root, 'rev-parse', 'HEAD');
    my ($upload_status) = release($root, {}, 'release-upload', "v=$current");
    isnt($upload_status, 0, 'upload retry requires a release tag');
    for my $version ('', $current, 'bad-version', '99.99.99', '3.2.01') {
        my ($status) = release($root, {}, 'release', "v=$version");
        isnt($status, 0, "reject version '$version'");
    }
    git($root, 'checkout', '-b', 'feature');
    my ($status, $log) = release($root, {}, 'release', "v=$next");
    isnt($status, 0, 'feature branches need explicit permission');
    like($log, qr/use a=1/, 'branch error explains the override');
    git($root, 'checkout', '--detach');
    ($status) = release($root, {}, 'release', "v=$next", 'a=1');
    isnt($status, 0, 'a=1 does not permit detached HEAD');
    git($root, 'checkout', 'master');
    write_file("$root/untracked", 'user work');
    ($status) = release($root, {}, 'release', "v=$next");
    isnt($status, 0, 'untracked work blocks release');
    unlink "$root/untracked" or die $!;
    git($root, 'tag', $next);
    ($status) = release($root, {}, 'release', "v=$next");
    isnt($status, 0, 'existing tags block release');
    is(git($root, 'rev-parse', 'HEAD'), $head, 'no commits were made');
    is(git($root, 'status', '--porcelain'), '', 'no source files changed');
    is_deeply(phases($root), [], 'Maven was never launched');
};

subtest 'cancellation leaves source and Git state unchanged' => sub {
    my $root = fixture();
    my $head = git($root, 'rev-parse', 'HEAD');
    my ($status, $log) = release($root, {ENGINE_TEST_ANSWER => "n\n"},
        'release', "v=$next");
    isnt($status, 0, 'operator can cancel');
    like($log, qr/Release cancelled/, 'cancellation is reported');
    is(git($root, 'rev-parse', 'HEAD'), $head, 'HEAD is unchanged');
    is(git($root, 'status', '--porcelain'), '', 'source is unchanged');
    is_deeply(phases($root), [], 'Maven was not launched');
};

subtest 'dry run bypasses credentials and all writes' => sub {
    my $root = fixture();
    git($root, 'checkout', '-b', 'feature');
    my $head = git($root, 'rev-parse', 'HEAD');
    my ($status, $log) = release($root, {CENTRAL_TOKEN => '', GPG_KEY_ID => ''},
        'release', "v=$next", 'a=1', 'd=1');
    is($status, 0, 'dry run completes') or diag($log);
    like($log, qr/Would bump \Q$current\E to \Q$next\E/, 'shows bump');
    like($log, qr/manual approval/, 'explains final publication');
    is(git($root, 'rev-parse', 'HEAD'), $head, 'HEAD is unchanged');
    is(git($root, 'tag', '--list', $next), '', 'no release tag was created');
    is(git($root, 'status', '--porcelain'), '', 'working tree is unchanged');
    is_deeply(phases($root), [], 'dry run never launches Maven');
};

subtest 'successful workflow and upload retry' => sub {
    my $root = fixture();
    git($root, 'checkout', '-b', 'feature');
    my ($status, $log) = release($root, {}, '-j4', 'release',
        "v=$next", 'a=1');
    is($status, 0, 'release completes') or diag($log);
    like(read_file("$root/pom.xml"), qr{<version>\Q$next\E</version>},
        'project version was bumped');
    like(read_file("$root/pom.xml"), qr{<tag>\Q$next\E</tag>},
        'SCM tag was bumped');
    like(read_file("$root/Makefile"), qr/^VERSION := \Q$next\E$/m,
        'Makefile version was bumped');
    like(read_file("$root/Fork.md"),
        qr/org.yamlstar:snakeyaml-engine:\Q$next\E/, 'fork docs were bumped');
    like(read_file("$root/src/changes/changes.xml"),
        qr/<release version="\Q$next\E" date="\d{4}-\d\d-\d\d"/,
        'release changelog was prepared');
    my $head = git($root, 'rev-parse', 'HEAD');
    is(git($root, 'rev-parse', "$next\^{commit}"), $head,
        'release tag points to the release commit');
    is(git($root, 'cat-file', '-t', $next), 'tag', 'tag is annotated');
    is(git($root, 'status', '--porcelain'), '', 'release tree is clean');
    my $commands = phases($root);
    is_deeply([map { $_->{phase} } @$commands], ['test', 'deploy'],
        'tests run before upload, even under parallel make');
    is_deeply([map { $_->{version} } @$commands], [$next, $next],
        'both Maven phases use the new version');
    is_deeply($commands->[0]{tags}, [], 'tests run before tagging');
    is_deeply($commands->[1]{tags}, [$next], 'upload uses the tagged commit');
    ok(grep($_ eq '-Dcentral.skipUpload=false', @{$commands->[1]{args}}),
        'upload is enabled only for the deploy phase');
    ($status, $log) = release($root, {}, 'release-upload', "v=$next");
    is($status, 0, 'upload retry completes') or diag($log);
    is(git($root, 'rev-parse', 'HEAD'), $head, 'retry does not commit');
    is_deeply([map { $_->{phase} } @{phases($root)}],
        ['test', 'deploy', 'deploy'], 'retry only uploads');
    ($status) = release($root, {}, 'release-upload', "v=$current");
    isnt($status, 0, 'retry rejects mismatched versions');
    git($root, 'commit', '--allow-empty', '-m', 'Later work');
    ($status) = release($root, {}, 'release-upload', "v=$next");
    isnt($status, 0, 'retry rejects a tag behind HEAD');
};

subtest 'failures preserve inspectable state' => sub {
    my $root = fixture();
    my $head = git($root, 'rev-parse', 'HEAD');
    my ($status) = release($root, {CENTRAL_TOKEN => ''},
        'release', "v=$next");
    isnt($status, 0, 'missing credentials block release');
    is(git($root, 'status', '--porcelain'), '', 'credentials fail before bump');
    ($status) = release($root, {ENGINE_TEST_FAIL => 42},
        'release', "v=$next");
    isnt($status, 0, 'test failure blocks release');
    is(git($root, 'rev-parse', 'HEAD'), $head, 'failed tests do not commit');
    is(git($root, 'tag', '--list', $next), '', 'failed tests do not tag');
    is_deeply([map { $_->{phase} } @{phases($root)}], ['test'],
        'failed tests never upload');
    like(read_file("$root/pom.xml"), qr{<version>\Q$next\E</version>},
        'prepared files remain available for inspection');
    $root = fixture();
    ($status) = release($root, {ENGINE_DEPLOY_FAIL => 42},
        'release', "v=$next");
    isnt($status, 0, 'upload failure is reported');
    is(git($root, 'rev-parse', "$next\^{commit}"),
        git($root, 'rev-parse', 'HEAD'), 'upload failure retains release tag');
    is(git($root, 'status', '--porcelain'), '', 'upload failure tree is clean');
    ($status) = release($root, {}, 'release-upload', "v=$next");
    is($status, 0, 'failed upload can be retried');
};

subtest 'test side effects cannot enter a release' => sub {
    for my $path ('Fork.md', 'unexpected-file') {
        my $root = fixture();
        my $head = git($root, 'rev-parse', 'HEAD');
        my ($status) = release($root, {ENGINE_TEST_TOUCH => $path},
            'release', "v=$next");
        isnt($status, 0, "test modifications to $path block release");
        is(git($root, 'rev-parse', 'HEAD'), $head, 'no release commit');
        is(git($root, 'tag', '--list', $next), '', 'no release tag');
        is_deeply([map { $_->{phase} } @{phases($root)}], ['test'],
            'test side effects never reach upload');
    }
};

subtest 'a missing changelog entry is generated' => sub {
    my $root = fixture();
    my $later = join '.', $parts[0], $parts[1], $parts[2] + 2;
    my ($status, $log) = release($root, {}, 'release', "v=$later");
    is($status, 0, 'release without a pending entry completes') or diag($log);
    like(read_file("$root/src/changes/changes.xml"),
        qr/<release version="\Q$later\E" date="\d{4}-\d\d-\d\d"/,
        'new entry has the requested version and current date');
};

subtest 'inherited Make settings cannot select real tools' => sub {
    my $root = fixture();
    my ($status, $log) = release($root,
        {M => '/missing-makes', MAVEN => '/missing-maven',
         YS => '/missing-ys', PERL => '/missing-perl'},
        'release', "v=$next");
    is($status, 0, 'fixture tools override inherited paths') or diag($log);
    is_deeply([map { $_->{phase} } @{phases($root)}], ['test', 'deploy'],
        'both phases used the fake Maven executable');
};

done_testing;
