package PDF::MetadataVerifier::BkSortNamLotHandler;
use base 'PDF::MetadataVerifier::LotHandler';
use PDF::Log;
use PDF::DpLoad;

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub handle_lot {
    my ($self) = @_;
    my $model = $self->model;
    my $params = $self->params;
    my $pplogger = $self->pplogger;
    # $pplogger->setModelHeader($model);

    # Check if the lot needs to be skipped
    my $lot = $model->header->LOT;
    my $skip_lots = $params->{skip_lots} || [];
    my $lots_like = $params->{skip_lots_like} || [];
    my $lots_starts_with = $params->{skip_lots_starts_with} || [];

    if (grep { $_ eq $lot } @$skip_lots) {
        INFO("Skipping metadata check for lot: $lot");
        return 0;
    }

    # Skip lots that match a pattern
    foreach my $pattern (@$lots_like) {
        if ($lot =~ /$pattern/) {
            INFO("Skipping metadata check for lot: $lot due to pattern match: $pattern");
            return 0;
        }
    }

    # Skip lots that start with a certain prefix
    foreach my $prefix (@$lots_starts_with) {
        if ($lot =~ /^$prefix/) {
            INFO("Skipping metadata check for lot: $lot due to prefix match: $prefix");
            return 0;
        }
    }

    return($self->checkMetadataByLot($model, $params));
}

# Helper subroutine to replace the third character with zero
sub replace_third_char_with_zero {
    my ($lot) = @_;
    substr($lot, 2, 1, "0");
    return $lot;
}

# Main subroutine
sub checkMetadataByLot {
    my ($self, $model, $hash) = @_;
    my $header = $model->header;
    my $lot_modified = 0;
    # Original lot number
    my $orig_lot = $header->LOT;

     # Validate input
    unless (defined $orig_lot && length $orig_lot) {
        dpExit(1,"Invalid lot number");
    }

    my $customMessage = "First lookup original lot=$header->{LOT}";
    my $lot_check_successful = $header->checkLotMetadata($orig_lot, $customMessage);
    if ($lot_check_successful) {
        INFO("Metadata verifier found for original lot number: $orig_lot");
        return 0;  # Return early if lot check is successful
    }
    my $tempLot1 = $orig_lot;
    # Check for M0 lots
    # Modify lot number for M0 lots
    if ($orig_lot =~ /^M0\[a-zA-Z\]/i && length($orig_lot) == 10) {
        my $modified_lot = _replace_third_char_with_zero($orig_lot);
        my $customMessage = "Performing second lot lookup for M0 lot: $orig_lot => $modified_lot";
        $lot_check_successful = $header->checkLotMetadata($modified_lot, $customMessage);
        if ($lot_check_successful) {
            INFO("Metadata verifier found for modified M0 lot: $modified_lot");
            return 0;  # Return early if lot check is successful
        }
    } # Modify lot number for KG|KH lots
    elsif (length($orig_lot) > 8 && $orig_lot =~ /^KG|^KH/i) {
        my $modified_lot = substr($orig_lot, 0, 8);
        my $customMessage = "Performing second lot lookup for KG|KH lot: $orig_lot => $modified_lot";
        $lot_check_successful = $header->checkLotMetadata($modified_lot, $customMessage);
        if ($lot_check_successful) {
            INFO("Metadata verifier found for modified KG|KH lot: $modified_lot");
            return 0;  # Return early if lot check is successful
        }
        else {
            my $shortened_lot = substr($orig_lot, 0, -1);
            my $cm = "Performing third lot lookup for KG|KH lot: $orig_lot => $shortened_lot";
            $lot_check_successful = $header->checkLotMetadata($shortened_lot, $cm);
            if ($lot_check_successful) {
                INFO("Metadata verifier, found for shortened KG|KH lot: $shortened_lot");
                return 0;  # Return early if lot check is successful
            }
        }
    }

    # Check for MK lots
    elsif ($orig_lot =~ /^MK/i) {
        my $modified_lot = substr($orig_lot, 1);  # Drop the first character 'M'
        my $customMessage = "Performing second lot lookup for MK lot: $orig_lot => $modified_lot";
        $lot_check_successful = $header->checkLotMetadata($modified_lot, $customMessage);
        if ($lot_check_successful) {
            INFO("Metadata verifier found for modified MK lot: $modified_lot");
            return 0;  # Return early if lot check is successful
        }
        else {
            my $shortened_lot = substr($modified_lot, 0, 8);  # Strip to 8 characters
            my $cm = "Performing third lot lookup for MK lot: $orig_lot => $shortened_lot";
            $lot_check_successful = $header->checkLotMetadata($shortened_lot, $cm);
            if ($lot_check_successful) {
                INFO("Metadata verifier found for shortened MK lot: $shortened_lot");
                return 0;  # Return early if lot check is successful
            }
        }
    }

    # If no lot check was successful, move the file to the 'ReworkFiles' folder
    INFO("Metadata verifier not able to get metadata info in refdb. The file with lot number $orig_lot will be moved to the 'ReworkFiles' folder.");
    return 1011;
}



1;

=pod

=head1 SYNOPSIS
            


=head1 DESCRIPTIONS

B<This Module> used for specific implementation of bksort_wmap_nam environment lotid handler.
                                

=head1 AUTHOR

B<junifferallan.garcia@onsemi.com>

=head1 CHANGES
       2024-Apr-25 -jgarcia - initial
 
       
       
=head1 LICENSE

(C) onsemi 2023 All rights reserved.

=cut