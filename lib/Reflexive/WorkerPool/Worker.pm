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

sub available_job_slots {
	my $self = shift;

	return $self->max_jobs - $self->num_jobs;
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

__END__

=head1 NAME

Reflexive::Worker - Manages a collection of jobs

=head1 DESCRIPTION

See L<Reflexive::WorkerPool> for details.

=head1 AUTHOR

Andy Gorman, agorman@cpan.org

=head1 COPYRIGHT AND LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.