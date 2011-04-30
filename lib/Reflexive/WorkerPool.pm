package Reflexive::WorkerPool;

use Moose;
extends 'Reflex::Base';
use Reflex::Callbacks qw(cb_method);
use Reflexive::WorkerPool::Worker;
use Reflex::Interval;
use Scalar::Util qw(reftype);

has workers => (
	is         => 'ro',
	isa        => 'ArrayRef[Reflexive::WorkerPool::Worker]',
	lazy_build => 1,
	traits     => ['Array'],
	handles    => {
		all_workers => 'elements',
	},
);

has max_workers => (
	is      => 'ro',
	isa     => 'Int',
	default => 5,
);

has max_jobs_per_worker => (
	is      => 'ro',
	isa     => 'Int',
	default => 5,
);

has poll_interval => (
	is      => 'ro',
	isa     => 'Int',
	default => 60,
);

has active_queue => (
	is      => 'ro',
	isa     => 'Reflex::Interval',
	writer  => '_set_active_queue',
	clearer => '_clear_active_queue',
);

sub BUILD {
	my $self = shift;

	$self->_set_active_queue(
		Reflex::Interval->new(
			interval => $self->poll_interval,
			on_tick  => cb_method($self, 'on_active_queue_tick'),
		)
	);
}

sub available_job_slots {
	my $self = shift;

	my $available = 0;
	foreach my $worker ( $self->all_workers ) {
		$available += $worker->available_job_slots();
	}

	return $available;
}

sub on_active_queue_tick {
	my $self = shift;

	return unless $self->available_job_slots();

	$self->emit(event => 'ready_to_work');
}

sub enqueue_job {
	my ( $self, $job ) = @_;

	Carp::croak "no available job slots"
		unless $self->available_job_slots();

	Carp::croak "enqueue_job expects a job class"
		unless eval { $job->can('can') };

	Carp::croak "jobs must consume Reflexive::WorkerPool::Role::Job"
		unless $job->does('Reflexive::WorkerPool::Role::Job');

	if (my $worker = $self->get_next_available_worker) {
		$self->_watch($job);
		$worker->add_job($job);
	}
}

sub get_next_available_worker {
	my $self = shift;

	foreach my $worker ( @{$self->workers} ) {
		return $worker if $worker->available_job_slots();
	}

	return;
}

sub shut_down {
	my $self = shift;

	$self->_clear_active_queue();
}

sub _watch {
	my ( $self, $job ) = @_;

	$self->watch(
		$job,
		job_started => cb_method($self, '_on_job_started'),
		job_stopped => cb_method($self, '_on_job_stopped'),
		job_errored => cb_method($self, '_on_job_errored'),
		job_updated => cb_method($self, '_on_job_updated'),
	);
}

sub _on_job_started {
	my ( $self, $job ) = @_;

	$self->emit(event => 'job_started', args => $job);
}

sub _on_job_stopped {
	my ( $self, $job ) = @_;

	$self->ignore($job);
	$self->emit(event => 'job_stopped', args => $job);
}

sub _on_job_errored {
	my ( $self, $job ) = @_;

	$self->emit(event => 'job_errored', args => $job);
}

sub _on_job_updated {
	my ( $self, $state ) = @_;

	$self->emit(event => 'job_updated', args => $state);
}

sub _build_workers {
	my $self = shift;

	my @workers;
	for (1..$self->max_workers) {
		push(
			@workers,
			Reflexive::WorkerPool::Worker->new(
				max_jobs => $self->max_jobs_per_worker,
			)
		);
	}

	return \@workers;
}

1;

__END__

=head1 NAME

Reflexive::WorkerPool - Sandbox for brain dumping workerpool ideas/concepts

=head1 SYNOPSIS

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

=head1 DESCRIPTION

A worker pool for Reflex! The pool contains 0 or more workers. Calling the
enqueue method adds a job to a worker and starts that job running.

=head2 Workers

Each worker has 0 or more jobs. The pool delegates jobs to the first free worker
it finds. The worker adds a job to it's L<Reflex::Collection> and calls the
job's work() method.

=head2 Jobs

Jobs implement a work() method that is run it's own process using
L<Reflex::POE::Wheel::Run>.

If a job has an attribute with the L<Reflex::Trait::EmitsOnChange> trait then
that attribute will be updated across processes so that when the job_updated
or job_stopped events are fired the job's attributes reflect the changes.

=head1 METHODS

=head1 available_job_slots

Gets the number of jobs that can be run by the worker pool at any given moment.

=head2 enqueue

	(Object $job)

Adds an object that consumes Reflexive::WorkerPool::Role::Job,
Reflex::Role::Collectible and implements a work() method.

=head2 shut_down

Stops worker pool execution by destroying the internal Reflex::Interval object.

=head1 ATTRIBUTES

=head2 max_workers

	is: ro, isa: Int, default: 5

The maximum number of workers that can be running at any given time.

TODO: Should this just be called num_workers? The workers are created during
WorkerPool construction.

=head2 max_jobs_per_worker

	is: ro, isa: Int, default: 5

The maximum number of workers that can be run for a given worker.

=head2 poll_interval

	is: ro, isa: Int, default: 60

How often the workerpool will fire the ready_to_work event so that new jobs can
be added to the pool. Keep in mind that if the pool is full the ready_to_work
event will not fire.

=head1 CALLBACKS

=head1 job_started

	(Object $job)

Fires right before a job's work() method is run.

=head1 job_stopped

	(Object $job)

Fires right after a job's work() method is run.

=head1 job_updated

	(Object $job)

Fires any time an attribute of a job (with the L<Reflex::Trait::EmitsOnChange>
trait) is changed.

=head1 TODO

Get Rocco's opinion on the way Job classes update. e.g. POE::Filter::Reference
and STDOUT.

Add the ability to $workerpool->enqueue( sub { ... }, [ $arg1, $arg2 ] ). This
could be done by creating a BasicJob class that implements a work method to
call the bassed in sub.

enqueue is probably a bad method name for adding a job to the job. It's not
enqueued...

Add proper job erroring. This can be done by adding a _error attribute to
Reflexive::WorkerPool::Role::Job and updating it across the process boundary via
STDOUT and POE::Filter::Reference

The on_pool_... callbacks clober _sender. It makes for a nicer interface but
worse functionality.

Should be have any other kind of worker balancing besides just grabbing the
first available worker and giving it a job? Does it really matter?

What other callbacks might people care about? Should workers have callbacks?

Is there a better way to pass callbacks up than having the workerpool watch jobs
and manually reemit their events?

=head1 AUTHOR

Andy Gorman, agorman@cpan.org

=head1 COPYRIGHT AND LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.