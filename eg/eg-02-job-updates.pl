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

	emits attr => (
		is  => 'rw',
		isa => 'Int',
	);

	sub work {
		my $self = shift;

		$self->attr(123456789);
		$self->attr(2);

		sleep 5;
	}
}

{
	package HasWorkerPool;
	use Moose;
	extends 'Reflex::Base';
	use Reflexive::WorkerPool;
	use Reflex::Trait::Observed;
	use Reflex::Callbacks qw(cb_method);
	use Scalar::Util qw(blessed);
	use Data::Dumper;

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
	}

	sub on_pool_job_errored {
		my ( $self, $job ) = @_;

		printf "Job: %s, errored!\n", $job->get_id;
	}

	sub on_pool_job_updated {
		my ( $self, $state ) = @_;

		# This sessions job object
		my $job = delete($state->{_sender})->get_first_emitter;
		printf "Job: %s, updated with values:\n", $job->get_id;

		# Other sessions emitted attribute change
		print Dumper $state;
	}
}

HasWorkerPool->new->run_all();