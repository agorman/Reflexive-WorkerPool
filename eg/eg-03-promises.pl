#!/usr/bin/env perl
use strict;
use warnings;
use lib qw(../lib);
#use lib '/root/contrib/reflex/lib';

# Job updates across the process boundary.

{
	package MyJob;
	use Moose;
	extends 'Reflex::Base';
	with 'Reflex::Role::Collectible';
	with 'Reflexive::WorkerPool::Role::Job';

	# This method will be executed within it's own process
	sub work {}
}

use Reflexive::WorkerPool;

my $pool = Reflexive::WorkerPool->new;
my @jobs = ( MyJob->new, MyJob->new, MyJob->new );

$pool->enqueue_job(shift @jobs);

while(my $event = $pool->next()) {
	print "$event->{name}\n";

	if ($event->{name} eq 'job_stopped') {
		my $job = shift @jobs;
		last unless $job;

		$pool->enqueue_job($job);
	}
}