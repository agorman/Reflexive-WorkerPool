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