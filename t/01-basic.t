#!/usr/bin/env perl

use warnings;
use strict;

use Test::More;

use lib 'lib';
use lib '/root/contrib/reflex/lib';

{
	package MyJob;
	use Moose;
	extends 'Reflex::Base';
	with 'Reflex::Role::Collectible';
	with 'Reflexive::WorkerPool::Role::Job';

	sub work {}
}

use_ok 'Reflexive::WorkerPool';
use_ok 'Reflexive::WorkerPool::Worker';

my $worker_pool = Reflexive::WorkerPool->new();
isa_ok $worker_pool, 'Reflexive::WorkerPool', 'WorkerPool Instantiated';

my $job = MyJob->new();
$worker_pool->enqueue_job($job);

my ( $job_started, $job_stopped ) = ( 0, 0 );

while (my $event = $worker_pool->next()) {
	$job_started = 1 if $event->{name} eq 'job_started';
	$job_stopped = 1 if $event->{name} eq 'job_stopped';

	last if ($event->{name} eq 'job_stopped');
}

ok $job_started, 'got job_started event';
ok $job_stopped, 'got_job stopped event';

pass 'All done!';

done_testing();