#!/usr/bin/env perl
use strict;
use warnings;
use lib qw(../lib);


# Simple polling mechanism. In practive fetch_jobs would be more complex. For
# example polling a database or a watch folder.


{
	package MyJob;
	use Moose;
	extends 'Reflex::Base';
	with 'Reflex::Role::Collectible';
	with 'Reflexive::WorkerPool::Role::Job';

	has id => (
		is         => 'ro',
		isa        => 'Int',
		lazy_build => 1,
	);
	
	sub _build_id {
		srand time;
		return int(rand 1000);
	}

	sub work {
		my $self = shift;

		# doing a unit of work!
	}
}


use Reflexive::WorkerPool;

my $worker_pool = Reflexive::WorkerPool->new(
	max_workers     => 5,
	poll_interval   => 1,
	poll_action     => \&fetch_jobs,
	on_job_started  => sub {
		my ( $self, $job ) = @_;

		printf "Job: %s, started!\n", $job->id;
	},
	on_job_stopped => sub {
		my ( $self, $job ) = @_;

		printf "Job: %s, stopped!\n", $job->id;
	}
);

$worker_pool->run_all();


# Returns a list of jobs to run
sub fetch_jobs {
	[ MyJob->new, MyJob->new ];
}