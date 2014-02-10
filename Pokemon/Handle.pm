package Pokemon::Handle;
use strict;
use warnings;
use autodie;
use Carp;

sub new {
    my ($self, $file_name) = @_;
    open my $file_handle, '<', $file_name;
    binmode $file_handle;
    return bless {
        handle => $file_handle,
    }, $self;
}

sub handle {
    return shift->{handle};
}

sub to {
    my ($self, $position) = @_;
    seek $self->handle, $position, 0;
}

# Reads one byte, and moves the file handle forward.
sub byte {
    my ($self) = @_;
    return ord $self->read_bytes(1);
}

sub short {
    my ($self) = @_;
    return unpack 'S<', $self->read_bytes(2);
}

sub read_bytes {
    my ($self, $length) = @_;
    my $result;
    read $self->handle, $result, $length or croak "Value couldn't be read";
    return $result;
}

1;
