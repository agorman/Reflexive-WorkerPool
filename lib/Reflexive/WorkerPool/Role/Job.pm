package Reflexive::WorkerPool::Role::Job;

use Moose::Role;
use Reflex::POE::Wheel::Run;
use Reflex::Callbacks qw(cb_role);
use Try::Tiny;

requires 'work';

has wheel => (
	is         => 'ro',
	isa        => 'Reflex::POE::Wheel::Run',
	writer     => '_set_wheel',
	clearer    => '_clear_wheel',
	lazy_build => 1,
);

sub run {
	my $self = shift;

	$self->emit(event => 'job_started', args => $self);

	$self->_set_wheel(
		Reflex::POE::Wheel::Run->new(
			Program => sub {
				my $self = shift;

				$self->work();
			},
			ProgramArgs => [ $self ],
			cb_role($self, "child"),
		)
	);
}

sub on_child_signal {
	my ( $self, $args ) = @_;

	$self->emit(event => 'job_stopped', args => $self);

	$self->_clear_wheel();
	$self->stopped();
}

1;