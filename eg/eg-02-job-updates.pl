#!/usr/bin/env perl
use strict;
use warnings;
use lib qw(../lib);

# Job updates across the process boundary.

{
	package MyJob;
	use Moose;
	extends 'Reflex::Base';
	use Reflex::Trait::EmitsOnChange;
	with 'Reflex::Role::Collectible';
	with 'Reflexive::WorkerPool::Role::Job';

	# Changing this attribute inside work will also update the MyJob object in
	# this process provided:
	# 1) The attribute is rw
	# 2) The attribute uses the Reflex::Trait::EmitsOnChange trait
	emits attr => (
		is  => 'rw',
		isa => 'Int',
	);

	# This method will be executed within it's own process
	sub work {
		my $self = shift;

		$self->attr(42);

		sleep 5;
	}
}

{
	package HasWorkerPool;
	use Moose;
	extends 'Reflex::Base';
	use Reflexive::WorkerPool;
	use Reflex::Trait::Observed;

	observes pool => (
		is    => 'rw',
		isa   => 'Reflexive::WorkerPool',
		setup => {
			max_workers         => 5,
			max_jobs_per_worker => 1,
			poll_interval       => 1,
		},
		handles => {
			enqueue => 'enqueue_job',
		}
	);

	# The ready_to_work event files when the pool_interval is reached and the
	# workerpool isn't full.
	sub on_pool_ready_to_work {
		my $self = shift;

		for (1..$self->pool->available_job_slots) {
			$self->enqueue(MyJob->new);
		}
	}

	sub on_pool_job_started {
		my ( $self, $job ) = @_;

		printf "Job: %s, started!\n", $job->get_id;
	}

	sub on_pool_job_stopped {
		my ( $self, $job ) = @_;

		printf "Job: %s, stopped!\n", $job->get_id;

		print $job->attr;	# prints 42
	}

	sub on_pool_job_updated {
		my ( $self, $job ) = @_;

		printf "Job: %s, stopped!\n", $job->get_id;

		print $job->attr;	# prints 42
	}
}

HasWorkerPool->new->run_all();