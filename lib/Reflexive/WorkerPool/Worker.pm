package Reflexive::WorkerPool::Worker;

use Moose;
extends 'Reflex::Base';
use Reflex::Collection;

has_many jobs => (
	handles => {
		remove_job => 'forget',
	}
);

has max_jobs => (
	is      => 'ro',
	isa     => 'Int',
	default => 5,
);

sub num_jobs {
	my $self = shift;

	return scalar keys %{$self->jobs->_objects};
}

sub add_job {
	my ( $self, $job ) = @_;

	Carp::croak "Not a valid job"
		unless $job->does('Reflex::Role::Collectible');

	Carp::croak "Job doesn't implement a work() method"
		unless $job->can('work');

	Carp::croak "Too many jobs!"
		if $self->num_jobs == $self->max_jobs;

	$self->jobs->remember($job);

	$job->run();
}

1;