#!/usr/bin/env perl
binmode(STDOUT, ":utf8");

use lib qw(./lib);

use Cmd;
use v5.40;

Cmd->new_with_command->run();