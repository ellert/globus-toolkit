#! /usr/bin/env perl

use strict;
use POSIX;
use Test;

my @tests;
my @todo;
my $test_exec="./framework_test";

sub run_test
{
    my $cmd=(shift);
    my ($errors,$rc) = ("",0);

    unlink("core");

    my $command = "$test_exec $cmd >/dev/null 2>/dev/null";

    $rc = system($command);
    if($rc != 0)
    {
        $errors .= "\n # Tests :$command: exited with  $rc.";
    }
    if(-r 'core')
    {
        my $core_str = "something.core";
        system("mv core $core_str");
        $errors .= "\n# Core file generated.";
    }

    if($errors eq "")
    {
        ok('success', 'success');
    }
    else
    {
        $errors = "\n# Test failed\n# $command\n# " . $errors;
        ok($errors, 'success');
    }
}


my $inline_finish;
my $buffer_size=2048;
my $c;

# setup different chunk sizes
my @chunk_sizes;
push(@chunk_sizes, "1024");
push(@chunk_sizes, "1924");
push(@chunk_sizes, "2048");

#setup different driver combinations
my @drivers;
push(@drivers, "");
push(@drivers, "-D debug");
push(@drivers, "-D test_bounce_transform");
push(@drivers, "-D debug -D test_bounce_transform");
push(@drivers, "-D test_bounce_transform -D debug");
push(@drivers, "-D debug -D test_bounce_transform -D debug");
push(@drivers, "-D test_bounce_transform -D debug -D test_bounce_transform");

my @failures;
push(@failures, "-F 1");
push(@failures, "-F 2");
push(@failures, "-F 5");
push(@failures, "-F 6");
push(@failures, "-F 7");
push(@failures, "-F 8");
push(@failures, "-F 9");
push(@failures, "-F 10");

sub basic_tests
{
    my $test_name="framework";
    my $inline_finish="-i";

    for(my $i = 0; $i < 2; $i++)
    {
        foreach(@drivers)
        {
            my $d=$_;
            foreach(@chunk_sizes)
            {
                my $c = $_;
                push(@tests, "$test_name -w 1 -r 0 -c $c -b $buffer_size $inline_finish $d");
                push(@tests, "$test_name -w 0 -r 1 -c $c -b $buffer_size $inline_finish $d");
                for(my $write_count = 1; $write_count <= 8; $write_count *= 2)
                {
                    for(my $read_count = 1; $read_count <= 8; $read_count *= 2)
                    {
                        push(@tests, "$test_name -w $write_count -r $read_count -c $c -b $buffer_size $inline_finish $d");
                    }
                }
            }
        }
        $inline_finish="";
    }
}

&basic_tests();
plan tests => scalar(@tests), todo => \@todo;
foreach(@tests)
{
    &run_test($_);    
}
