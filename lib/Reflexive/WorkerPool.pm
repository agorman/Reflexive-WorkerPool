package Reflexive::WorkerPool;

use Moose;
extends 'Reflex::Base';
use Reflex::Callbacks qw(cb_method);
use Reflexive::WorkerPool::Worker;

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


sub enqueue_job {
	my ( $self, $job ) = @_;

	foreach my $worker ( @{$self->workers} ) {
		next if ($worker->max_jobs == $worker->num_jobs);

		$self->_watch($job);
		return $worker->add_job($job);
	}

	Carp::croak "No available workers";
}


sub _watch {
	my ( $self, $job ) = @_;

	$self->watch(
		$job,
		job_started => cb_method($self, 'on_job_started'),
		job_stopped => cb_method($self, 'on_job_stopped'),
	);
}

sub on_job_started {
	my ( $self, $job ) = @_;

	printf "Job with id=%s started!\n", $job->get_id;
}

sub on_job_stopped {
	my ( $self, $job ) = @_;

	printf "Job with id=%s stopped!\n", $job->get_id;

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

__END__

=head1 SYNOPSIS

{
	package MyJob;
	use Moose;
	extends 'Reflex::Base';
	with 'Reflex::Role::Collectible';
	with 'Reflexive::WorkerPool::Role::Job';
	
	sub work {
		my $self = shift;
	
		# doing a unit of work!
	}
}


use Reflexive::WorkerPool;

my $worker_pool = Reflexive::WorkerPool->new();

for my $i (0..10) {
	try {
		$worker_pool->enqueue_job(MyJob->new);
	} catch {
		warn "Oh noes! bad stuff happened: $_\n";
	};
}

$worker_pool->run_all();