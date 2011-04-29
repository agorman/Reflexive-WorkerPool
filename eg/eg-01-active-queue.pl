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

	sub work {
		my $self = shift;

		sleep 10;
		# doing a unit of work!
	}
}

{
	package HasWorkerPool;
	use Moose;
	extends 'Reflex::Base';
	use Reflexive::WorkerPool;
	use Reflex::Trait::Observed;
	use Reflex::Callbacks qw(cb_method);

	observes pool => (
		is    => 'rw',
		isa   => 'Reflexive::WorkerPool',
		setup => {
			max_workers         => 5,
			max_jobs_per_worker => 5,
			poll_interval       => 1,
		},
		handles => {
			enqueue => 'enqueue_job',
		}
	);

	sub on_pool_ready_to_work {
		my $self = shift;

		for (1..$self->pool->available_job_slots) {
			$self->enqueue(MyJob->new)
		}
	}

	sub on_pool_job_started {
		my ( $self, $job ) = @_;

		printf "Job: %s, started!\n", $job->get_id;
	}

	sub on_pool_job_stopped {
		my ( $self, $job ) = @_;

		printf "Job: %s, stopped!\n", $job->get_id;
	}
}

HasWorkerPool->new->run_all();