##
# Analytic routines

# Displays books where there is no copy
sub noused {
    my $key;
    if (%noused) {
        $email_copy .= "\nNo used copy available:\n";
        foreach $key ( sort { $noused{$a} <=> $noused{$b} } ( keys(%noused) ) )
        {
            $email_copy .=
              "$current_product_prices{$key}{Title}\t" . $product_information{$key}{surl} . "\n";
        }
    }
}

# Finds and displays used copies that have changed price
sub usedmovers {
    $email_copy .= "\nUsed Books that have changed value in the past day:\n";
    $email_copy .=
      "Price\tLast\tAvg.\tDiff.\tValue\tURL\t\t\tTitle\t\t\tAuthor\n";
    my $key;
    foreach $key ( sort { $useddiff{$a} <=> $useddiff{$b} }
        ( keys(%useddiff) ) )
    {
        my $dr;
        if ( $product_discount{$key} ) {
            $dr = $product_discount{$key};
        }
        else {
            $dr = "ND";
        }
        my $title = $current_product_prices{$key}{Title};
        $title = substr( $title, 0, 19 );
        my $author = $current_product_prices{$key}{Author};
        $author = substr( $author, 0, 15 );
        my $value = "";
        if (
            ( $current_product_prices{$key}{UsedPrice} > $pricerank{$key} )
            && (
                sprintf( "%.2f", ( $current_product_prices{$key}{UsedPrice} / 100 ) ) ne
                sprintf( "%.2f", ( $pricerank{$key} / 100 ) ) )
          )
        {
            my $disc =
              ( $current_product_prices{$key}{UsedPrice} / $pricerank{$key} ) * 10;
            for ( $b = 1 ; $b <= $disc ; $b++ ) {
                if ( $b >= 10 ) {
                    $value .= "-";
                }
            }
        }
        if (
            ( $current_product_prices{$key}{UsedPrice} < $pricerank{$key} )
            && (
                sprintf( "%.2f", ( $current_product_prices{$key}{UsedPrice} / 100 ) ) ne
                sprintf( "%.2f", ( $pricerank{$key} / 100 ) ) )
          )
        {
            my $disc =
              ( $pricerank{$key} / $current_product_prices{$key}{UsedPrice} ) * 10;
            for ( $b = 1 ; $b <= $disc ; $b++ ) {
                if ( $b >= 10 ) {
                    $value .= "+";
                }
            }
        }
        if ( $current_product_prices{$key}{UsedPrice} ne $lastused{$key} ) {

            #print $lastused{$key};
            $email_copy .= "\$"
              . sprintf( "%.2f", ( $current_product_prices{$key}{UsedPrice} / 100 ) )
              . "\t\$"
              . sprintf( "%.2f", ( $lastused{$key} / 100 ) ) . "\t\$"
              . sprintf( "%.2f", ( $pricerank{$key} / 100 ) ) . "\t\$"
              . sprintf( "%.2f", ( $useddiff{$key} / 100 ) ) . "\t"
              . substr( $value, 0, 6 ) . "\t"
              . $product_information{$key}{surl}
              . "\t$title...\t$author...\n";
        }
    }
}

# Finds and displays used copies that have changed price
sub usedmovers_week {
    $email_copy .=
      "\nUsed Books that have changed value in the past seven days:\n";
    $email_copy .=
      "Price\tLast\tAvg.\tDiff.\tValue\tURL\t\t\tTitle\t\t\tAuthor\n";
    my $key;
    foreach $key ( sort { $useddiff_week{$a} <=> $useddiff_week{$b} }
        ( keys(%useddiff_week) ) )
    {
        my $dr;
        if ( $product_discount{$key} ) {
            $dr = $product_discount{$key};
        }
        else {
            $dr = "ND";
        }
        my $title = $current_product_prices{$key}{Title};
        $title = substr( $title, 0, 19 );
        my $author = $current_product_prices{$key}{Author};
        $author = substr( $author, 0, 15 );
        my $value = "";
        if (
            ( $current_product_prices{$key}{UsedPrice} > $pricerank{$key} )
            && (
                sprintf( "%.2f", ( $current_product_prices{$key}{UsedPrice} / 100 ) ) ne
                sprintf( "%.2f", ( $pricerank{$key} / 100 ) ) )
          )
        {
            my $disc =
              ( $current_product_prices{$key}{UsedPrice} / $pricerank{$key} ) * 10;
            for ( $b = 1 ; $b <= $disc ; $b++ ) {
                if ( $b >= 10 ) {
                    $value .= "-";
                }
            }
        }
        if (
            ( $current_product_prices{$key}{UsedPrice} < $pricerank{$key} )
            && (
                sprintf( "%.2f", ( $current_product_prices{$key}{UsedPrice} / 100 ) ) ne
                sprintf( "%.2f", ( $pricerank{$key} / 100 ) ) )
          )
        {
            my $disc =
              ( $pricerank{$key} / $current_product_prices{$key}{UsedPrice} ) * 10;
            for ( $b = 1 ; $b <= $disc ; $b++ ) {
                if ( $b >= 10 ) {
                    $value .= "+";
                }
            }
        }
        if ( $current_product_prices{$key}{UsedPrice} ne $lastused_week{$key} ) {

            #print $lastused{$key};
            $email_copy .= "\$"
              . sprintf( "%.2f", ( $current_product_prices{$key}{UsedPrice} / 100 ) )
              . "\t\$"
              . sprintf( "%.2f", ( $lastused_week{$key} / 100 ) ) . "\t\$"
              . sprintf( "%.2f", ( $pricerank{$key} / 100 ) ) . "\t\$"
              . sprintf( "%.2f", ( $useddiff_week{$key} / 100 ) ) . "\t"
              . substr( $value, 0, 6 ) . "\t"
              . $product_information{$key}{surl}
              . "\t$title...\t$author...\n";
        }
    }
}

sub product_discount {
    $email_copy .= "\nSorted by Largest Discount:\n";
    $email_copy .=
      "Disc.\tPrice\tAvg.\tNew\tValue\tURL\t\t\tTitle\t\t\tAuthor\n";
    my $key;
    foreach $key ( sort { $product_discount{$b} <=> $product_discount{$a} }
        ( keys(%product_discount) ) )
    {
        my $title = $current_product_prices{$key}{Title};
        $title = substr( $title, 0, 19 );
        my $author = $current_product_prices{$key}{Author};
        $author = substr( $author, 0, 15 );
        my $value = "";
        if (
            ( $current_product_prices{$key}{UsedPrice} > $pricerank{$key} )
            && (
                sprintf( "%.2f", ( $current_product_prices{$key}{UsedPrice} / 100 ) ) ne
                sprintf( "%.2f", ( $pricerank{$key} / 100 ) ) )
          )
        {
            my $disc =
              ( $current_product_prices{$key}{UsedPrice} / $pricerank{$key} ) * 10;
            for ( $b = 1 ; $b <= $disc ; $b++ ) {
                if ( $b >= 10 ) {
                    $value .= "-";
                }
            }
        }
        if (
            ( $current_product_prices{$key}{UsedPrice} < $pricerank{$key} )
            && (
                sprintf( "%.2f", ( $current_product_prices{$key}{UsedPrice} / 100 ) ) ne
                sprintf( "%.2f", ( $pricerank{$key} / 100 ) ) )
          )
        {
            my $disc =
              ( $pricerank{$key} / $current_product_prices{$key}{UsedPrice} ) * 10;
            for ( $b = 1 ; $b <= $disc ; $b++ ) {
                if ( $b >= 10 ) {
                    $value .= "+";
                }
            }
        }
        $email_copy .=
            "$product_discount{$key}\%\t" . "\$"
          . sprintf( "%.2f", ( $current_product_prices{$key}{UsedPrice} / 100 ) ) . "\t\$"
          . sprintf( "%.2f", ( $pricerank{$key} / 100 ) ) . "\t"
          . sprintf( "%.2f", ( $current_product_prices{$key}{AmaPrice} / 100 ) ) . "\t"
          . substr( $value, 0, 6 ) . "\t"
          . $product_information{$key}{surl}
          . "\t$title...\t$author...\n";

#$email_copy .= "$product_discount{$key} \t ". sprintf("%.2f",($current_product_prices{$key}{UsedPrice} / 100)) ."\t $current_product_prices{$key}{Title}\n";
    }
}

sub pricerank {
    $email_copy .= "\nSorted by Lowest Price:\n";
    $email_copy .=
      "Price\tAvg.\tNew\tDisc.\tValue\tURL\t\t\tTitle\t\t\tAuthor\n";
    my $key;
    foreach $key ( sort { $lowest_price{$a} <=> $lowest_price{$b} } ( keys(%lowest_price) ) ) {

   #foreach $key (sort {$pricerank{$a} <=> $pricerank{$b}} (keys(%pricerank))) {
        my $dr;
        if ( $product_discount{$key} ) {
            $dr = $product_discount{$key};
        }
        else {
            $dr = "ND";
        }
        my $title = $current_product_prices{$key}{Title};
        $title = substr( $title, 0, 19 );
        my $author = $current_product_prices{$key}{Author};
        $author = substr( $author, 0, 15 );
        my $value = "";
        if (
            ( $current_product_prices{$key}{UsedPrice} > $pricerank{$key} )
            && (
                sprintf( "%.2f", ( $current_product_prices{$key}{UsedPrice} / 100 ) ) ne
                sprintf( "%.2f", ( $pricerank{$key} / 100 ) ) )
          )
        {
            my $disc =
              ( $current_product_prices{$key}{UsedPrice} / $pricerank{$key} ) * 10;
            for ( $b = 1 ; $b <= $disc ; $b++ ) {
                if ( $b >= 10 ) {
                    $value .= "-";
                }
            }
        }
        if (
            ( $current_product_prices{$key}{UsedPrice} < $pricerank{$key} )
            && (
                sprintf( "%.2f", ( $current_product_prices{$key}{UsedPrice} / 100 ) ) ne
                sprintf( "%.2f", ( $pricerank{$key} / 100 ) ) )
          )
        {
            my $disc =
              ( $pricerank{$key} / $current_product_prices{$key}{UsedPrice} ) * 10;
            for ( $b = 1 ; $b <= $disc ; $b++ ) {
                if ( $b >= 10 ) {
                    $value .= "+";
                }
            }
        }
        $email_copy .= "\$"
          . sprintf( "%.2f", ( $current_product_prices{$key}{UsedPrice} / 100 ) ) . "\t\$"
          . sprintf( "%.2f", ( $pricerank{$key} / 100 ) ) . "\t"
          . sprintf( "%.2f", ( $current_product_prices{$key}{AmaPrice} / 100 ) )
          . "\t$dr\%\t"
          . substr( $value, 0, 6 ) . "\t"
          . $product_information{$key}{surl}
          . "\t$title...\t$author...\n";

#$email_copy .= "$product_discount{$key} \t ". sprintf("%.2f",($current_product_prices{$key}{UsedPrice} / 100)) ."\t $current_product_prices{$key}{Title}\n";
#print "". sprintf("%.2f",($current_product_prices{$key}{UsedPrice} / 100)) ."\t $product_discount{$key} \t $current_product_prices{$key}{Title}\n";
    }
}