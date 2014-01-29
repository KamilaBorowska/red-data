package Pokemon::Red;
use strict;
use warnings;
use Pokemon::Handle;
use Memoize;
use Carp;

our @ISA = 'Pokemon::Handle';

sub characters {
    return (
        0x7F => " ",
        0x80 => "A",
        0x81 => "B",
        0x82 => "C",
        0x83 => "D",
        0x84 => "E",
        0x85 => "F",
        0x86 => "G",
        0x87 => "H",
        0x88 => "I",
        0x89 => "J",
        0x8A => "K",
        0x8B => "L",
        0x8C => "M",
        0x8D => "N",
        0x8E => "O",
        0x8F => "P",
        0x90 => "Q",
        0x91 => "R",
        0x92 => "S",
        0x93 => "T",
        0x94 => "U",
        0x95 => "V",
        0x96 => "W",
        0x97 => "X",
        0x98 => "Y",
        0x99 => "Z",
        0xE3 => "-",
    );
}

sub to_ascii {
    my ($self, $string) = @_;
    my %characters = $self->characters;
    my $result = "";
    for (split //, $string) {
        my $character = ord;
        if (exists $characters{$character}) {
            $result .= $characters{$character};
        }
        else {
            $result .= sprintf '\x%02X', $character;
        }
    }
    return $result;
}

sub decrease_number {
    my ($self, $index) = @_;
    return ($index || 256) - 1;
}

sub string {
    my ($self, $index) = @_;
    my $result = "";
    while ((my $character = $self->read_bytes(1)) ne "\x50") {
        $result .= $character;
    }
    return $result;
}

sub gb_address {
    my ($self, $bank, $address) = @_;
    my $bank_size = 0x4000;

    # Ram area
    croak "Tried to convert RAM" if $address > 0x7FFF;

    # Area that is not affected by bank switching.
    if ($address < $bank_size) {
        $bank = 0;
    }
    $address %= $bank_size;
    return $address + $bank * $bank_size;
}

sub move_to_gb_address {
    my ($self, $bank, $address) = @_;
    $self->to($self->gb_address($bank, $address));
}

sub to_pokedex_table {
    return 0x41024;
}

sub to_pokedex {
    my ($self, $index) = @_;

    # The number is decreased by one
    $index = $self->decrease_number($index);

    $self->to($self->to_pokedex_table + $index);

    return $self->byte;
}

memoize 'to_pokedex';

sub base_stats_length {
    return 28;
}

sub base_stats_table {
    return 0x383de;
}

sub base_stats_parse {
    my ($self) = shift;

    # Read the data.
    my %result;

    # Get Pokedex number.
    $result{id} = $self->byte;

    # Get base stats (and EV gain).
    $result{hp} = $self->byte;
    $result{attack} = $self->byte;
    $result{defense} = $self->byte;
    $result{speed} = $self->byte;
    $result{special} = $self->byte;

    # Get types.
    my $first_type = $self->byte;
    my $second_type = $self->byte;
    if ($first_type == $second_type) {
        $result{types} = [$first_type];
    }
    else {
        $result{types} = [$first_type, $second_type];
    }

    # Get catch rate.
    $result{catch_rate} = $self->byte;

    # Get base exp yield.
    $result{exp_yield} = $self->byte;

    # Get dimensions.
    my $dimensions = $self->byte;
    $result{x_size} = $dimensions & 0x0F;
    $result{y_size} = $dimensions >> 4;

    # Get pointers.
    $result{front_sprite} = $self->short;
    $result{back_sprite} = $self->short;

    # Level 0 attacks.
    for (1..4) {
        push @{$result{level0}}, $self->byte;
    }

    # Remove Cooltrainer attacks at end of list.
    for (1..3) {
        if ($result{level0}[-1] == 0) {
            pop @{$result{level0}};
        }
    }

    # Growth rate.
    $result{growth_rate} = $self->byte;

    # Learnset
    my $learnset = $self->read_bytes(7);
    for (0..54) {
        push @{$result{learnset}}, vec $learnset, $_, 1;
    }

    return %result;
}

sub base_stats_by_pokedex {
    my ($self, $index) = @_;

    # The number is decreased by one.
    $index = $self->decrease_number($index);

    $self->to($self->base_stats_table + $index * $self->base_stats_length);

    return $self->base_stats_parse;
}

memoize 'base_stats_by_pokedex';

sub base_stats {
    my ($self, $index) = @_;
    return $self->base_stats_by_pokedex($self->to_pokedex($index));
}

sub evo_lvl_pointers {
    return 0x3b05c;
}

sub evo_method {
    my ($self, $method) = @_;

    # Level up method
    if ($method == 1) {
        my $level = $self->byte;
        my $specie = $self->byte;
        return (
            type => 'level',
            level => $level,
            specie => $specie,
        );
    }
    # Item method
    if ($method == 2) {
        my $item = $self->byte;

        # Unused byte
        $self->byte;

        my $specie = $self->byte;

        return (
            type => 'item',
            item => $item,
            specie => $specie,
        );
    }
    # Trade method
    if ($method == 3) {
        # Has to be 1.
        my $one = $self->byte;
        my $specie = $self->byte;

        return unless $one == 1;

        return (
            type => 'trade',
            specie => $specie
        );
    }
    # Read two bytes if method is unrecognized.
    $self->byte;
    $self->byte;
    return;
}

sub evo_lvl_table {
    my ($self, $index) = @_;

    $index = $self->decrease_number($index);

    $self->to($self->evo_lvl_pointers + $index * 2);
    my $address = $self->short;
    $self->move_to_gb_address(14, $address);

    my @evolutions;
    my $trade = 0;
    while ((my $method = $self->byte) != 0) {
        my %method = $self->evo_method($method);
        if (%method) {
            push @evolutions, \%method;
        }
    }

    # Move back, because level up moves are parsed different way.
    # It doesn't matter for real mons, but glitch mons use strange
    # data structures.
    $self->move_to_gb_address(14, $address);

    # Read bytes until we get to level up moves.
    while ($self->byte != 0) {

    }

    my @learnset;
    my %levels;
    while ((my $level = $self->byte) != 0) {
        my $move = $self->byte;

        # Mons in first generation cannot learn more than one move
        # at given level.
        next if $levels{$level};
        $levels{$level} = 1;

        # Stop annoying me, typeless Perl.
        $level += 0;

        push @learnset, {
            level => $level,
            move => $move,
        };
    }
    @learnset = sort { $a->{level} <=> $b->{level} } @learnset;
    return evolutions => \@evolutions, learnset => \@learnset;
}
memoize 'evo_lvl_table';

sub evolutions {
    my ($self, $index) = @_;
    my %table = $self->evo_lvl_table($index);
    return @{$table{evolutions}};
}

sub learnset {
    my ($self, $index) = @_;
    my %table = $self->evo_lvl_table($index);
    my %base_stats = $self->base_stats($index);
    my @learnset = @{$table{learnset}};
    # Put level 0 moves at beginning.
    unshift @learnset, map { {level => 0, move => $_ } } @{$base_stats{level0}};
    return @learnset;
}

sub move_names_table {
    return 0xb0000;
}

sub move_names {
    my ($self) = @_;

    $self->to($self->move_names_table);
    # Cooltrainer (move 0)
    my @result = "\xE3\xE3";
    for (1..165) {
        push @result, $self->string;
    }
    return @result;
}
memoize 'move_names';

sub move_name {
    my ($self, $index) = @_;
    # Standard moves
    if ($index <= 165) {
        my @moves = $self->move_names;
        return $self->to_ascii($moves[$index]);
    }
    # TM moves
    elsif ($index >= 201) {
        return sprintf "TM%02d", $index - 200;
    }
    # HM movess
    elsif ($index >= 196) {
        return sprintf "HM%02d", $index - 195;
    }
    # Super glitch
    else {
        return sprintf "SUPER GLITCH (%02X)", $index;
    }
}

sub move_table {
    return 0x38000;
}

sub move {
    my ($self, $index) = @_;
    $index = $self->decrease_number($index);

    $self->to($self->move_table + $index * 6);

    my %result;
    $result{animation} = $self->byte;
    $result{effect} = $self->byte;
    $result{power} = $self->byte;
    $result{type} = $self->byte;
    $result{accuracy} = $self->byte;
    $result{pp} = $self->byte;

    return %result;
}

1;
