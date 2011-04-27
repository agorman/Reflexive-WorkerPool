package Reflexive::WorkerPool;

use Moose;
extends 'Reflex::Base';
use Reflex::Callbacks qw(cb_method);
use Reflexive::WorkerPool::Worker;
use Reflex::Interval;

has workers => (
	is         => 'ro',
	isa        => 'ArrayRef[Reflexive::WorkerPool::Worker]',
	lazy_build => 1,
	traits     => ['Array'],
	handles    => {
		
	},
);

has max_workers => (
	is      => 'ro',
	isa     => 'Int',
	default => 5,
);


has poll_interval => (
	is      => 'ro',
	isa     => 'Int',
	default => 60,
);

has poll_action => (
	is  => 'ro',
	isa => 'CodeRef',
);

has active_queue => (
	is     => 'ro',
	isa    => 'Reflex::Interval',
	writer => '_set_active_queue',
);

has on_job_started => (
	is  => 'ro',
	isa => 'CodeRef',
);

has on_job_stopped => (
	is  => 'ro',
	isa => 'CodeRef',
);

sub BUILD {
	my $self = shift;

	if ($self->poll_action) {
		$self->_set_active_queue(
			Reflex::Interval->new(
				interval => $self->poll_interval,
				on_tick  => cb_method($self, 'on_active_queue_tick'),
			)
		);
	}
}

sub on_active_queue_tick {
	my $self = shift;

	my $jobs = $self->poll_action->();
	$self->enqueue_jobs($jobs);
}

sub enqueue_jobs {
	my ( $self, $jobs ) = @_;

	foreach my $job ( @$jobs ) {
		$self->enqueue_job($job);
	}
}

sub enqueue_job {
	my ( $self, $job ) = @_;

	foreach my $worker ( @{$self->workers} ) {
		next if ($worker->max_jobs <= $worker->num_jobs);

		$self->_watch($job);
		return $worker->add_job($job);
	}

	Carp::croak "No available workers";
}

sub _watch {
	my ( $self, $job ) = @_;

	$self->watch(
		$job,
		job_started => cb_method($self, '_on_job_started'),
		job_stopped => cb_method($self, '_on_job_stopped'),
	);
}

sub _on_job_started {
	my ( $self, $job ) = @_;

	$self->on_job_started->($self, $job);
}

sub _on_job_stopped {
	my ( $self, $job ) = @_;

	$self->on_job_stopped->($self, $job);
	$self->ignore($job);
}

sub _build_workers {
	my $self = shift;

	my @workers;
	for (1..$self->max_workers) {
		push @workers, Reflexive::WorkerPool::Worker->new;
	}

	return \@workers;
}

1;