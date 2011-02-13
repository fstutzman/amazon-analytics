#!/usr/bin/perl -w
use strict;
use DBI;
use LWP;
use FileHandle;
use Date::Manip;
use XML::Simple;
use Data::Dumper;
use URI::Escape;
use RequestSignatureHelper;
use LWP::UserAgent;
use XML::Simple;
use Data::Dumper;


#
# Configuration
#
BEGIN { require "./conf/config.dev.pl"; }

###################################################
# Variables

#
# Control variables
#

use constant myAWSId	    => '<FILL IN>';
use constant myAWSSecret    => '<FILL IN>';
use constant myEndPoint	    => 'ecs.amazonaws.com';

# Set up the helper
my $helper = new RequestSignatureHelper (
    +RequestSignatureHelper::kAWSAccessKeyId => myAWSId,
    +RequestSignatureHelper::kAWSSecretKey => myAWSSecret,
    +RequestSignatureHelper::kEndPoint => myEndPoint,
);

my $request = {
    Service => 'AWSECommerceService',
    Operation => 'ListLookup',
    Version => '2009-03-31',
    AssociateTag => 'yotrse-20',
	IsOmitPurchasedItems => 'True',
	Sort => 'LastUpdate',
	ListType => 'WishList',
	ListId => 'MLYHFVQ19CQH'
};

# Sign the request
my $signedRequest = $helper->sign($request);

# We can use the helper's canonicalize() function to construct the query string too.
my $queryString = $helper->canonicalize($signedRequest);
my $urlbase = "http://" . myEndPoint . "/onca/xml?" . $queryString;
print "Sending request to URL: $urlbase \n";

#my $urlbase =
#"http://ecs.amazonaws.com/onca/xml?Service=AWSECommerceService&AWSAccessKeyId=<YOURKEY>&AssociateTag=yotrse-20&Operation=ListLookup&IsOmitPurchasedItems=True&Sort=LastUpdated&ListType=WishList&ListId=";
my %userlist = (
    #"MLYHFVQ19CQH" => "fred\@fredstutzman.com" #Old list
    #"3C6GSRDXQXHNC" => "fred\@fredstutzman.com"
    #"1AZU37QJ53VZE" => "fred\@fredstutzman.com", #Vander Wal
    "3HG9J97L0IQ89" => "fred\@fredstutzman.com" #JPOM
);
# Interval is the time deltas to search for used prices.  If the user is new interval should be zero.
my $interval = "60";

#
# Declarations
#
my $browser = LWP::UserAgent->new();
my ( $db_prefix, $k, $email_copy );

my (
	%current_product_prices,  	# Assigned in &assign_current_product_prices, it is the hash of the current elements for all of the 	
							  	# local object.  Access by $current_product_prices{ $list{ASIN} }{$key}

	%product_information,		# Product_information and product prices table.  Product information is a singular copy.
	%product_prices, 			# Product_prices is the last price in the DB, UNDEF if new.  Access 
	
	%lowest_price,  			# Finds the lowest price for the item by comparing lowest new and lowest used prices.  Can return 0
    
    %product_discount,  		# This is the discount from the lowest new to the lowest used price.  If there is a discount
  								# it returns a percentage, if there isn't it returns a zero

	%product_discount_az,		# This is the difference from Amazon's price to the lowest price available
								# It returs a percentage, and if there isn't one it returns zero

	%average_new, 				# average_new, average_used and average_amazon are the average prices.  If no price will
	%average_used, 				# return zero
	%average_amazon, 
	%lowest_average_price, 		# The lowest average price (of all three)
	
	%last_value_new,			# The last set of prices in the DB.  If undef then 0. 
	%last_value_used, 
	%last_value_amazon,
	%lowest_last_price,			# The lowest of the last prices


	#%noused,  					########################## I dunno      
	#%lastused,
	#%useddiff,     
	#%lastused_week, 
	#%useddiff_week,
	#%pricerank
);

#
# Local logging and operations control
#
my $crawler_log = "$appbase/log/crawler.log";
my $error_log   = "$appbase/log/error.log";
my $retry_log   = "$appbase/log/retry.log";

#
# Debugging variables
#
# Increase debug value to get more info
# Levels 1: Most basic
# Level 2: Basic, plus db routines
# Level 3: All, plus hashes (tabbed)
# Level 4: All, plus
# Level 5: All - including dumpers
my $debug = 5;
# If nodb =1, no data is written to the db
my $nodb = 0;
# If send_email =1, no email is sent
my $send_email = 0;



###################################################
# Main Program

#
# Run the program by passing it a whishlist url
#
while ( my ( $uid, $email ) = each(%userlist) ) {
    if ( $debug >= 1 ) { print "\$uid => $email\n"; }
    &wishlist( $uid, $email );

	# This is ugly.  Better way of doing this w/o complete re-architecture?
	%current_product_prices = ();
	%product_information = ();
	%product_prices = ();      
	%lowest_price = ();
	%product_discount = ();      
	%product_discount_az = ();
	%average_new = ();
	%average_used = ();
	%average_amazon = ();      
	%lowest_average_price = ();
	%last_value_new = ();         
	%last_value_used = ();
	%last_value_amazon = ();      
	%lowest_last_price = ();
}

##########################
# Controller routines

# The primary routine.  We look the user up, find number of books/pages on their wishlist.
# If we can't find the user we exit out.  We then run analytics on the processed data (results of getitems)
sub wishlist {

    # Wishlist is passed the Amazon UID and the user's email address
    my $uid   = $_[0];
    my $email = $_[1];


    # Format the URL of the wishlist to determine the number of pages.
    my $wlurl = $urlbase;
    #my $wlurl = $urlbase . "" . $uid;
    if ( $debug >= 1 ) { print "$wlurl\n"; }


	my $ua = new LWP::UserAgent();
	my $response = $ua->get($wlurl);
	my $content = $response->content();
	print "Recieved Response: $content \n";

	my $xmlParser = new XML::Simple();
	my $data = $xmlParser->XMLin($content);

	print "Parsed XML is: " . Dumper($data) . "\n";

    # Go and get the page (with LWP) and parse it using XML::Simple
    #my $inbound_link = $browser->get($wlurl);
    #my $xml          = new XML::Simple;
    #my $data         = $xml->XMLin( $inbound_link->content );

	# Here we check the number of pages in the user's wislist.  If greater than 30, we restrict to 30
	# per Amazon ECS API guidelines.  If the user has no items, we return null.
    if ( $data->{Lists}->{List}->{TotalPages} ) {
        if ( $data->{Lists}->{List}->{TotalPages} > 30 ) {
            &getitems( $uid, 30 );
        }
        else {
            &getitems( $uid, $data->{Lists}->{List}->{TotalPages} );
        }
    }
    else {
        print "Couldn't find this user, something is wrong";
        return;
    }

    #
    # Our Analytic routines
	&process($uid,$email);
}

# First subroutine called from Wishlist
# From wishlist -> we're sent the uid and total number of pages to capture.
# We capture the pages and send them off for processing with &master, and then move on
sub getitems {

    # Get items is passed the Amazon UID and the user's email address
    my $wlurl     = $urlbase . "&ResponseGroup=Large&ProductPage=";
    #my $wlurl     = $urlbase . "" . $_[0] . "&ResponseGroup=Large&ProductPage=";
    my $itemcount = $_[1];
	if ( $debug >= 2 ) { $itemcount=2; }

 	# Here we get the collect each page of items from the user's wishlist (up to 30)
	# And we assign them to the database.  We call master, which is a midlevel controller subroutine.
    for($b=1; $b<=$itemcount; $b++)
	{
		# Format the URL of the wishlist item page.
        my $itempage = $wlurl . "$b";
        if ( $debug >= 1 ) { print "\n\$itempage: ". $itempage. "\n"; }

		# Go and get the page (with LWP) and parse it using XML::Simple
        my $inbound_link1 = $browser->get($itempage);
        my $xml           = new XML::Simple;
        my $data          = $xml->XMLin( $inbound_link1->content );

		# We look at the formatted data.  If the data is an array (meaning more than one item on the item page)
		# we send the data off to master with the number of the item (iterated through the total).  If there is only 
		# one item on the list we send the data off to master with a value of -1 which handles the special case.
        if ( ref( $data->{Lists}->{List}->{ListItem} ) eq "ARRAY" ) {
	
			# We look for the number of items on the list
            my $d = $#{ $data->{Lists}->{List}->{ListItem} };

			# We iterate through and pass master the XML data and the number of the item in the page
            for ( $k = 0 ; $k <= $d ; $k++ ) {
                &master( $data, $k );
            }

        }
        else {
            &master( $data, -1 );
        }
    }
}

# Master
sub master {
	
	# Master is passed the data (XML object) and the iterator
    my $data = $_[0];
    my $k    = $_[1];
	my %list;

	# Our first complication.  These are the parsing subroutines.
	# If the data object is a singleton we pass it to na_parse, if not we pass it to 
	# ar_parse with the iterator number.  This tells the parser the object to extract.
    if ( $k != -1 ) {
        %list = &ar_parse( $data, $k );
    }
    else {
        %list = &na_parse($data);
    }

   	# Master is being called by the iterator in &getitems.
   	# Therefore, this is occurring in a loop.  Everything called in here
   	# must be loop-dependent.
 	#

	###Master Debug
    if ( $debug >= 2 ) { &print_a(\%list); }

	### Database routines
    # We insert the db record into primary and product_prices (as necessary)
    unless ( $nodb == 1) { &product_information( \%list ); }

	### Local hash access routines
 	# We assign the current amazon variables (the parsed results) to a local hash
  	&assign_current_product_prices( \%list );

	# We pull out the primary record and the last secondary record (more than 1 hour old) and assign them into a local hash
    &db_hash( \%list );

	### Local hash comparison routines
    # Finds the lowest price for the item by comparing lowest new and lowest used prices
    &find_lowest_price( \%list );

    # This is the discount from the lowest new to the lowest used price.
    &find_discount( \%list );

    # This is the discount from Amazon's price to the lowest price available
    &find_discount_amazon( \%list );

    # We find the average price and assign them to a local hash
    &find_averages( \%list );

	# The lowest average price (of all three)
	&find_lowest_average( \%list );
	
	# The last set of prices in the DB.  If undef then 0.
	&find_last_value( \%list );
	
	# The lowest of the last prices, 0 if none defined
	&find_lowest_last_price( \%list );
}

#####################################################
# Database routines
#
# 1) product_information - Looks to see if ASIN is in master table, adds if not.
#	 Calls product_group_meta, a routine that looks to see if we've got an item in the product table
# 2) product_group_meta - Finds/Writes a product group
# 3) product_prices - Updates product_prices table with prices

sub product_information {
	# ins_product_info_rec is passed %list, which is scoped here.  We're going to write it to the DB.
    my (%list) = %{ $_[0] };

	# DBI Method.  We're going to look and see if there is already a primary record for the item
    my $dbh = DBI->connect( $adpter, $dbuser, $dbpswd, { "mysql_enable_utf8" => 1 } ) or log_( $error_log, $dbname, $DBI::errstr ) && die;
    my $sql_get_record = "SELECT * FROM product_information where asin = ?";
    my $dbq = $dbh->prepare($sql_get_record) or log_( $error_log, $sql_get_record, $DBI::errstr ) && die;
    $dbq->execute( $list{ASIN} );

	# If the title has a primary record, we do not insert again, we simply insert the updated pricing information 
	# in the product_pricing table
    my $parent_ref = $dbq->fetchrow_hashref();
    if ($parent_ref) {
        if ( $debug >= 2 ) { print "\n\n\$list{ASIN} $list{ASIN} In product_information DB"; }

		# product_prices is a subroutine which updates the product_pricing table
        &product_prices( \%list );
    }
    else {
        if ( $debug >= 2 ) { print "\n\n\$list{ASIN} $list{ASIN} Not in product_information DB"; }

 		# Shorten is a subroutine that generates a shortened is.gd URL for the URL
        my $surl = &shorten( $list{URL} );
		my $productgroup_id = &product_group_meta( $list{ProductGroup} );

		# DBI Method.  We're going to insert the primary record into product_information
        my $sql_link = "INSERT into product_information (asin, title, author, url, surl, productgroup, smallimage, mediumimage, largeimage, productgroup_id, date) VALUES (?,?,?,?,?,?,?,?,?,?,?)";
        my $dbh = DBI->connect( $adpter, $dbuser, $dbpswd, { "mysql_enable_utf8" => 1 } ) or log_( $error_log, $dbname, $DBI::errstr ) && die;
        my $dbq = $dbh->prepare($sql_link) or log_( $error_log, $sql_link, $DBI::errstr ) && die;
        $dbq->execute(
            $list{ASIN}, $list{Title}, $list{Author}, $list{URL}, $surl, $list{ProductGroup}, 
       		$list{SmallImage}, $list{MediumImage}, $list{LargeImage}, $productgroup_id, &realtime(0)
        ) or log_( $error_log, $sql_link, $DBI::errstr ) && die;

        if ( $debug >= 2 ) { print "\n\nDB Insert \$list{ASIN} $list{ASIN} Now in product_information DB"; }

		# product_prices is a subroutine which updates the product_pricing table
        &product_prices( \%list );
    }
}

sub product_prices {
	
	# product_prices is passed %list, which is scoped here.  We're going to write it to the DB.
    my (%list) = %{ $_[0] };
    my $dbh = DBI->connect( $adpter, $dbuser, $dbpswd, { "mysql_enable_utf8" => 1 } ) or log_( $error_log, $dbname, $DBI::errstr ) && die;
    my $sql_get_record = "SELECT * FROM product_information where asin = ?";
    my $dbq = $dbh->prepare($sql_get_record) or log_( $error_log, $sql_get_record, $DBI::errstr ) && die;
    $dbq->execute( $list{ASIN} );

	# DBI Method.  We're going to insert the pricing record into product_prices
    my $parent_ref = $dbq->fetchrow_hashref();
    my $sql_link ="INSERT into product_prices (lid, asin, listprice, amaprice, usedprice, newprice, totalnew, totalused, totalcollectible, totalrefurbished, date) VALUES (?,?,?,?,?,?,?,?,?,?,?)";
    my $dbq1 = $dbh->prepare($sql_link)
      or log_( $error_log, $sql_link, $DBI::errstr ) && die;
    $dbq1->execute(
        $parent_ref->{id},       $list{ASIN},
        $list{ListPrice},        $list{AmaPrice},
        $list{UsedPrice},        $list{NewPrice},
        $list{TotalNew},         $list{TotalUsed},
        $list{TotalCollectible}, $list{TotalRefurbished},
        &realtime(0)
    ) or log_( $error_log, $sql_link, $DBI::errstr ) && die;

    if ( $debug >= 2 ) { print "\nDB Insert \$list{ASIN} $list{ASIN} Now in product_prices"; }
}


sub product_group_meta {
	
	#### This method needs testing
	# Called from ins_product_info_rec
	# Here we look to see if a product group exists for the product.  If so, we find the ID of the product group
	# And we assign that to the product.  This will make searching by product group much more efficient.
	# If we don't find a product group we create a record for it in the DB, pull that record back out, and assign it to the product.
	
	# Is passed the product group
    my $productgroup = $_[0];
    my $dbh = DBI->connect( $adpter, $dbuser, $dbpswd, { "mysql_enable_utf8" => 1 } ) or log_( $error_log, $dbname, $DBI::errstr ) && die;
    my $sql_get_record = "SELECT * FROM product_group_meta where productgroup = ? limit 1";
    my $dbq = $dbh->prepare($sql_get_record) or log_( $error_log, $sql_get_record, $DBI::errstr ) && die;
    $dbq->execute( $productgroup );
 	my $parent_ref = $dbq->fetchrow_hashref();
    if ($parent_ref) {
        if ( $debug >= 2 ) { print "\n\$productgroup $productgroup already exists in product_group_meta"; }
		return($parent_ref->{id});
    }
    else {
	    my $sql_link ="INSERT into product_group_meta (productgroup) VALUES (?)";
	    my $dbq1 = $dbh->prepare($sql_link) or log_( $error_log, $sql_link, $DBI::errstr ) && die;
	    $dbq1->execute( $productgroup ) or log_( $error_log, $sql_link, $DBI::errstr ) && die;	
		my $sql_get_record = "SELECT * FROM product_group_meta where productgroup = ? limit 1";
	    my $dbq = $dbh->prepare($sql_get_record) or log_( $error_log, $sql_get_record, $DBI::errstr ) && die;
	    $dbq->execute( $productgroup );
	    if ( $debug >= 2 ) { print "\nDB Insert \$productgroup $productgroup inserted in product_group_meta"; }
	 	my $parent_ref = $dbq->fetchrow_hashref();
		return($parent_ref->{id});
	}
}


########################################################################
# Hash access routines

sub assign_current_product_prices {
	# Current_product_prices is a local multidimensional hash that contains
	# All of the current elements that we retrieve from the 
    my (%list) = %{ $_[0] };
    while ( my ( $key, $value ) = each(%list) ) {
        $current_product_prices{ $list{ASIN} }{$key} = $value;
        if ( $debug >= 4 ) { print "MD Hash: \$current_product_prices{ $list{ASIN} }{$key} $current_product_prices{ $list{ASIN} }{$key} -> $value\t"; }
    }
}

sub db_hash {
	# Here we create local hashes for faster access inside the program (for comparison and display purposes)
	# One is product_information, which is simply the product_information table, and ther other is the product_prices
	# table - which is the last entry in the product prices table.  Theoretically there should be no nulls
	# In either of these tables
	# SAFE Global: product_inforamtion, product_prices
    my (%list) = %{ $_[0] };

	# Product information
    my $dbh = DBI->connect( $adpter, $dbuser, $dbpswd, { "mysql_enable_utf8" => 1 } ) or log_( $error_log, $dbname, $DBI::errstr ) && die;
    my $sql_get_record = "SELECT * FROM product_information where asin = ?";
    my $dbq = $dbh->prepare($sql_get_record) or log_( $error_log, $sql_get_record, $DBI::errstr ) && die;
    $dbq->execute( $list{ASIN} );
    while ( my $ref = $dbq->fetchrow_hashref() ) {
        foreach my $keys ( keys %$ref ) {
            $product_information{ $list{ASIN} }{$keys} = $ref->{$keys};
            if ( $debug >= 3 ) { print "Hash: \$product_information{ $list{ASIN} }{$keys}: $product_information{ $list{ASIN} }{$keys}\n"; }
        }
    }

	# Product prices
    my $dbq2 = $dbh->prepare($sql_get_record) or log_( $error_log, $sql_get_record, $DBI::errstr ) && die;  $dbq2->execute( $list{ASIN} );
    my $parent_ref = $dbq2->fetchrow_hashref();
    my $sql_link = "SELECT * FROM product_prices where asin = ? and date < ? ORDER by date ASC";
    my $dbq1 = $dbh->prepare($sql_link) or log_( $error_log, $sql_link, $DBI::errstr ) && die;   
	$dbq1->execute( $parent_ref->{asin}, &realtime($interval) ) or log_( $error_log, $sql_link, $DBI::errstr ) && die;  
	while ( my $ref = $dbq1->fetchrow_hashref() ) {
        foreach my $keys ( keys %$ref ) {
            $product_prices{ $list{ASIN} }{$keys} = $ref->{$keys};
            if ( $debug >= 4 ) { print "MD Hash \$product_prices{ $list{ASIN} }{$keys}: $product_prices{ $list{ASIN} }{$keys}\t"; }
        }
    }
}

########################################################################
# Hash comparison routines

# Find's the product's current lowest price
sub find_lowest_price {
    my (%list) = %{ $_[0] };
    if ( ( $list{UsedPrice} != 0 ) && ( $list{NewPrice} != 0 ) ) {
        if ( $list{UsedPrice} < $list{NewPrice} ) {
            $lowest_price{ $list{ASIN} } = $list{UsedPrice};
        }
        else {
            $lowest_price{ $list{ASIN} } = $list{NewPrice};
        }
    }
    elsif ( $list{UsedPrice} == 0 ) {
        $lowest_price{ $list{ASIN} } = $list{NewPrice};
    }
    else {
        $lowest_price{ $list{ASIN} } = $list{UsedPrice};
    }
	if ( $debug >= 3 ) { print "\nHash: \$lowest_price{ $list{ASIN} }: $lowest_price{ $list{ASIN} }"; }
}


# Finds the discount from lowest new to the lowest used price
sub find_discount {
    my (%list) = %{ $_[0] };
    if ( ( $list{UsedPrice} != 0 ) && ( $list{NewPrice} != 0 ) ) {
        if ( $list{UsedPrice} < $list{NewPrice} ) {
            $product_discount{ $list{ASIN} } = sprintf( "%.1f", ( 1 - ( ( $list{UsedPrice} ) / $list{NewPrice} ) ) * 100 );
        }
        else {
            $product_discount{ $list{ASIN} } = "0";
        }
    }
    elsif ( $list{UsedPrice} == 0 ) {
        $product_discount{ $list{ASIN} } = "0";
    }
    else {
        $product_discount{ $list{ASIN} } = "0";
    }
	if ( $debug >= 3 ) { print "\nHash: \$product_discount{ $list{ASIN} }: $product_discount{ $list{ASIN} }"; }
}

# Finds the discount from Amazon to the lowest price
sub find_discount_amazon {
    my (%list) = %{ $_[0] };
	if ( $list{AmaPrice} != 0 ) {
	    if ( ( $list{UsedPrice} != 0 ) && ( $list{NewPrice} != 0 ) ) {
	        if ( $list{UsedPrice} < $list{NewPrice} ) {
	            $product_discount_az{ $list{ASIN} } = sprintf( "%.1f", ( 1 - ( ( $list{UsedPrice} ) / $list{AmaPrice} ) ) * 100 );
	        }
	        else {
	            $product_discount_az{ $list{ASIN} } = sprintf( "%.1f", ( 1 - ( ( $list{NewPrice} ) / $list{AmaPrice} ) ) * 100 );
	        }
	    }
	    elsif ( $list{UsedPrice} == 0 ) {
            $product_discount_az{ $list{ASIN} } = sprintf( "%.1f", ( 1 - ( ( $list{NewPrice} ) / $list{AmaPrice} ) ) * 100 );
	    }
	    else {
            $product_discount_az{ $list{ASIN} } = sprintf( "%.1f", ( 1 - ( ( $list{UsedPrice} ) / $list{AmaPrice} ) ) * 100 );
	    }
	}
	else {
		$product_discount_az{ $list{ASIN} } = "0";
	}
	if ( $debug >= 3 ) { print "\nHash: \$product_discount_az{ $list{ASIN} }: $product_discount_az{ $list{ASIN} }"; }
}


# Find the average prices for all three categories - Amazon, New and Used
sub find_averages {
    my (%list) = %{ $_[0] };

	# Counters for division
	my $lownewcount = "0";
	my $lowusedcount = "0";
	my $amazoncount = "0";
	
	# Values
	my $lownewvalue = "0";
	my $lowusedvalue = "0";
	my $amazonvalue = "0";
	
	# Let's see if we have some used prices in the DB
    my $dbh = DBI->connect( $adpter, $dbuser, $dbpswd, { "mysql_enable_utf8" => 1 } ) or log_( $error_log, $dbname, $DBI::errstr ) && die; 
    my $sql_link = "SELECT * FROM product_prices where asin = ? and date < ? ORDER by date ASC";
    my $dbq = $dbh->prepare($sql_link) or log_( $error_log, $sql_link, $DBI::errstr ) && die;   
	$dbq->execute( $list{ASIN}, &realtime($interval) ) or log_( $error_log, $sql_link, $DBI::errstr ) && die;
	
	
	# Iterate through the results
	while ( my $ref = $dbq->fetchrow_hashref() ) {
		if ( $$ref{'usedprice'} != 0 ) {
			$lowusedvalue = $lowusedvalue + $$ref{'usedprice'};
			$lowusedcount++;
		} 
		if ( $$ref{'newprice'} != 0 ) {
			$lownewvalue = $lownewvalue + $$ref{'newprice'};
			$lownewcount++;
		}
		if ( $$ref{'amaprice'} != 0 ) {
			$amazonvalue = $amazonvalue + $$ref{'amaprice'};
			$amazoncount++;
		}
	}
		
	if ($lownewcount == "0") {
		$lownewcount = 1;
		$average_new{ $list{ASIN} } = $lownewvalue/$lownewcount;
	}
	else {
		$average_new{ $list{ASIN} } = $lownewvalue/$lownewcount;	
	}
	if ($lowusedcount == "0") {
		$lowusedcount = 1;
		$average_used{ $list{ASIN} } = $lowusedvalue/$lowusedcount;
	}
	else {
		$average_used{ $list{ASIN} } = $lowusedvalue/$lowusedcount;
	}
	if ($amazoncount == "0") {
		$amazoncount = 1;
		$average_amazon{ $list{ASIN} } = $amazonvalue/$amazoncount;
	}
	else {
		$average_amazon{ $list{ASIN} } = $amazonvalue/$amazoncount;
	}
	if ( $debug >= 3 ) { print "\nHash: \$average_new{ $list{ASIN} }: $average_new{ $list{ASIN} }"; }
	if ( $debug >= 3 ) { print "\nHash: \$average_used{ $list{ASIN} }: $average_used{ $list{ASIN} }"; }
	if ( $debug >= 3 ) { print "\nHash: \$average_amazon{ $list{ASIN} }: $average_amazon{ $list{ASIN} }"; }
	
}

sub find_lowest_average {
	my (%list) = %{ $_[0] };
	$lowest_average_price{ $list{ASIN} } = "99955999";
	my @values = ($average_new{ $list{ASIN} }, $average_used{ $list{ASIN} }, $average_amazon{ $list{ASIN} });
	foreach my $key(@values) {
		if (($key > 0) && ($key < $lowest_average_price{ $list{ASIN} })) {
			$lowest_average_price{ $list{ASIN} } = $key;
		}		
	}
	if ($lowest_average_price{ $list{ASIN} } == "99955999") {
		$lowest_average_price{ $list{ASIN} } = "0";
	}
	if ( $debug >= 3 ) { print "\nHash: \$lowest_average_price{ $list{ASIN} }: $lowest_average_price{ $list{ASIN} }"; }
}
	
sub find_last_value {	
	my (%list) = %{ $_[0] };
	$last_value_used{ $list{ASIN} } = "0";
    $last_value_new{ $list{ASIN} } = "0";
    $last_value_amazon{ $list{ASIN} } = "0";
    	
	# Let's see if we have some used prices in the DB
    my $dbh = DBI->connect( $adpter, $dbuser, $dbpswd, { "mysql_enable_utf8" => 1 } ) or log_( $error_log, $dbname, $DBI::errstr ) && die;       
    my $sql_link = "SELECT * FROM product_prices where asin = ? and date < ? ORDER by date ASC";
    my $dbq = $dbh->prepare($sql_link) or log_( $error_log, $sql_link, $DBI::errstr ) && die;     
	$dbq->execute( $list{ASIN}, &realtime($interval) ) or log_( $error_log, $sql_link, $DBI::errstr ) && die;
		
    # Iterate through the results
    while ( my $ref = $dbq->fetchrow_hashref() ) {
        $last_value_used{ $list{ASIN} } = $$ref{'usedprice'};
        $last_value_new{ $list{ASIN} } = $$ref{'newprice'};
        $last_value_amazon{ $list{ASIN} } = $$ref{'amaprice'};
    }

	if ( $debug >= 3 ) { print "\nHash: \$last_value_new{ $list{ASIN} }: $last_value_new{ $list{ASIN} }"; }
	if ( $debug >= 3 ) { print "\nHash: \$last_value_used{ $list{ASIN} }: $last_value_used{ $list{ASIN} }"; }
	if ( $debug >= 3 ) { print "\nHash: \$last_value_amazon{ $list{ASIN} }: $last_value_amazon{ $list{ASIN} }"; }
}

sub find_lowest_last_price {
	my (%list) = %{ $_[0] };
	$lowest_last_price{ $list{ASIN} } = "99955999"; 
	my @values = ($last_value_new{ $list{ASIN} }, $last_value_used{ $list{ASIN} }, $last_value_amazon{ $list{ASIN} });
	foreach my $key (@values) {
		if (($key > 0) && ($key < $lowest_last_price{ $list{ASIN} })) {
			if ( $debug >= 5 ) { print "LLP Key is " .$list{ASIN} ." " . $lowest_last_price{ $list{ASIN} } ." ". $key."\n"; }
			$lowest_last_price{ $list{ASIN} } = $key;
		}		
	}
	if ($lowest_last_price{ $list{ASIN} } == "99955999") {
		$lowest_last_price{ $list{ASIN} } = "0";
	}
	if ( $debug >= 3 ) { print "\nHash: \$lowest_last_price{ $list{ASIN} }: $lowest_last_price{ $list{ASIN} }"; }
}

sub find_interval_value {	
	# This basically needs to be rewritten so that a time interval is called in
	# Then we create a local hash, do the evaluation and send the hash to the second routine
	# That routine evaluates it and passes it on
	my $kinterval = ($_[0] * 60);
	my $interval_value_used = "0";
    my $interval_value_new = "0";
    my $interval_value_amazon = "0";
	my $lowest_interval_value;
	my %interval_hash;

	while ( my ($key, $value) = each(%product_information) ) {
		if ( $debug >= 5 ) { print "MD Hash noused: $key => $value\n"; }
        my $dbh = DBI->connect( $adpter, $dbuser, $dbpswd, { "mysql_enable_utf8" => 1 } ) or log_( $error_log, $dbname, $DBI::errstr ) && die;       
	    my $sql_link = "SELECT * FROM product_prices where asin = ? and date < ? ORDER by date DESC LIMIT 1";
	    my $dbq = $dbh->prepare($sql_link) or log_( $error_log, $sql_link, $DBI::errstr ) && die;     
		$dbq->execute( $key, &realtime($kinterval) ) or log_( $error_log, $sql_link, $DBI::errstr ) && die;
		#print "\nSELECT * FROM product_prices where asin = '".$key."' and date < '".&realtime($kinterval)."' ORDER by date DESC LIMIT 1";

	    # Iterate through the results
	    while ( my $ref = $dbq->fetchrow_hashref() ) {
	        $interval_value_used = $$ref{'usedprice'};
	        $interval_value_new = $$ref{'newprice'};
	        $interval_value_amazon = $$ref{'amaprice'};
	    }
		my @values = ($interval_value_used, $interval_value_new, $interval_value_amazon);
		$lowest_interval_value = "99955999";
		foreach my $key (@values) {
			if (($key > 0) && ($key < $lowest_interval_value)) {
				$lowest_interval_value = $key;
			}		
		}
		if ($lowest_interval_value == "99955999") {
			$lowest_interval_value = "0";
		}
	
	if ( $debug >= 2 ) { print "\nHash: $key Interval time $kinterval - \$interval_value_new: $interval_value_new"; }
	if ( $debug >= 2 ) { print "\nHash: $key Interval time $kinterval - \$interval_value_used: $interval_value_used"; }
	if ( $debug >= 2 ) { print "\nHash: $key Interval time $kinterval - \$interval_value_amazon: $interval_value_amazon"; }
	if ( $debug >= 2 ) { print "\nHash: $key Interval time $kinterval - \$lowest_interval_value: $lowest_interval_value"; }
	#current_product_prices{ $list{ASIN} }{$key}
	$interval_hash{$key}{'time'} = $kinterval;
	$interval_hash{$key}{'new'} = $interval_value_new;
	$interval_hash{$key}{'used'} = $interval_value_used;
	$interval_hash{$key}{'amazon'} = $interval_value_amazon;
	$interval_hash{$key}{'lowest'} = $lowest_interval_value;
	}
	return %interval_hash;
}


##############################################################
## Email Routine

sub process {
	my $uid = $_[0];
	my $email = $_[1];
	my $email_copy;
	my $noused = &noused();
	#my $usedmovers = &usedmovers();
	my $intervalmovers = &intervalmovers();
	my $product_discount = &product_discount();
	my $lowest_price = &lowest_price();


	#if ($usedmovers) {
	#	$email_copy .= "\nItems that have changed value:\n\nIn the past day\n";
	#	$email_copy .= "Price\tValue\tChange\tLast\tAvg.\tAmazon\tTitle\t\t\tAuthor\t\t\tURL\n";
	#	$email_copy .= $usedmovers;
	#}
	if ($intervalmovers) {
		#$email_copy .= "\nUsed Items that have changed value in the past interval:\n";
		#$email_copy .= "Price\tValue\tChange\tLast\tAvg.\tAmazon\tTitle\t\t\tAuthor\t\t\tURL\n";
		$email_copy .= $intervalmovers;
	}
	if ($product_discount) {
		$email_copy .= "\nSorted by Largest Discount:\n";
		$email_copy .= "Disc.\t\tPrice\t\tAvg.\t\tAmazon\tTitle\t\t\t\t\tAuthor\t\t\tURL\n";
	
		#$email_copy .= "\nUsed Items that have changed value in the past interval:\n";
		#$email_copy .= "Price\tValue\tChange\tLast\tAvg.\tAmazon\tTitle\t\t\tAuthor\t\t\tURL\n";
		$email_copy .= $product_discount;
	}
	if ($lowest_price) {
		$email_copy .= "\nSorted by Lowest Price:\n";
		$email_copy .= "Price\t\tDisc.\t\tAvg.\t\tAmazon\tTitle\t\t\t\t\tAuthor\t\t\tURL\n";
	
		#$email_copy .= "\nUsed Items that have changed value in the past interval:\n";
		#$email_copy .= "Price\tValue\tChange\tLast\tAvg.\tAmazon\tTitle\t\t\tAuthor\t\t\tURL\n";
		$email_copy .= $lowest_price;
	}
	if ($noused) {
		$email_copy .= "\nNo used versions available:\n";
		$email_copy .= $noused
	}



	if ( $debug >= 1 ) { print $email_copy; }
	unless ( $send_email == 1) { &email($email_copy, $email); }

}

##############################################################
## View functions

# Displays books where there is no copy
sub noused {
	my $email_copy;
	while ( my ($key, $value) = each(%product_prices) ) {
        if ( $debug >= 5 ) { print "MD Hash noused: $key => $value\n"; }
		if ($current_product_prices{$key}{UsedPrice} == 0) {
			$email_copy .= "$current_product_prices{$key}{Title}\t ". &price($lowest_last_price{$key})."\t $product_information{$key}{surl}\n";
		}
	}
	#while ( my ($key, $value) = each(%last_value_used) ) {
    #    if ( $debug >= 5 ) { print "MD Hash noused: $key => $value\n"; }
	#	if ($value == 0) {
	#		$email_copy .= "$current_product_prices{$key}{Title}\t ". &price($lowest_last_price{$key})."\t $product_information{$key}{surl}\n";
	#	}
	#}
	return $email_copy;
}


# Finds and displays copies that have changed price
sub usedmovers {
	my $email_copy;
	my %delta;
	my %value;
	while ( my ($key, $value) = each(%lowest_last_price) ) {
	    if ( $debug >= 5 ) { print "\nMD Hash usedmovers: $key => $value => $lowest_price{ $key }"; }
		if ($value != $lowest_price{ $key }) {
			$delta{$key} = ($lowest_price{ $key } - $value);
			$value{$key} = &value($key, $lowest_price{ $key });
		}
	}
	    
	foreach my $key ( sort { $delta{$a} <=> $delta{$b} } ( keys(%delta) ) ) {
			if ( $debug >= 5 ) { print "\nMD Hash usedmovers: $key"; }
            $email_copy .= "\$"
              . &price($lowest_price{ $key }) . "\t\$"
              . &price($delta{$key}) . "\t\$"
              . &price($lowest_last_price{ $key }) . "\t\$"
              . &price($lowest_average_price{ $key }) . "\t\$"
              . &price($current_product_prices{$key}{AmaPrice}) . "\t"
              . $product_information{$key}{surl} . "\t"
			  . &compact($current_product_prices{$key}{Title}) ."...\t"
			  . &compact($current_product_prices{$key}{Author}) ."...\n";
			  #. $value{$key} . "\n";
    }
	return $email_copy;
}

sub intervalmovers {
    #
    # Big refactoring needed here
    my $email_copy;
    my %email_hash;
    #my @price_interval = ( 4, 3, 2, 1, 0 );
    my @price_interval = ( 4, 3, 2, 1, 0 );

    foreach (@price_interval) {
        my $k = "0";
        my $sub_email_copy;
        my %delta;
        my %value;
        my %interval_hash;
        my $price_interval;
        my $price_interval_fmt;

        if ( $_ == 0 ) {
            $price_interval     = 1;
            $price_interval_fmt = "today.";
        }
        else {
            $price_interval = ( $_ * 24 );
            if ( $_ == 1 ) {
                $price_interval_fmt = "yesterday";
            }
            else {
                $price_interval_fmt = "in the past $_ days.";
            }
        }

        %interval_hash = &find_interval_value($price_interval);

        while ( my ( $key, $value ) = each(%interval_hash) ) {

            if (   ( $interval_hash{$key}{'lowest'} != $lowest_price{$key} )
                && ( $interval_hash{$key}{'lowest'} > 0 ) )
            {
                $delta{$key} =
                  ( $lowest_price{$key} - $interval_hash{$key}{'lowest'} );
                $value{$key} =
                  &value_comparison( $interval_hash{$key}{'lowest'},
                    $lowest_price{$key} );
            }
        }
        foreach my $key ( sort { $delta{$a} <=> $delta{$b} } ( keys(%delta) ) )
        {
            if ( $debug >= 5 ) { print "\nMD Hash usedmovers: $key"; }
            $k++;
            if (   ( $email_hash{$key} )
                && ( $email_hash{$key} ne $interval_hash{$key}{'lowest'} ) )
            {
                $sub_email_copy .= "\$"
                  . &price( $lowest_price{$key} ) . "\t\$"
                  . &price( $delta{$key} ) . "\t\$"
                  . &price( $interval_hash{$key}{'lowest'} ) . "\t\$"
                  . &price( $lowest_average_price{$key} ) . "\t\$"
                  . &price( $interval_hash{$key}{'amazon'} ) . "\t"
                  . $product_information{$key}{surl} . "\t"
                  . &compact( $current_product_prices{$key}{Title} ) . "...\t"
                  . &compact( $current_product_prices{$key}{Author} ) . "...\n";
                  #. $value{$key} . "\n";
            }
            elsif (( $email_hash{$key} )
                && ( $email_hash{$key} eq $interval_hash{$key}{'lowest'} ) )
            {
            }
            else {
                $email_hash{$key} = $interval_hash{$key}{'lowest'};
                $sub_email_copy .= "\$"
                  . &price( $lowest_price{$key} ) . "\t\$"
                  . &price( $delta{$key} ) . "\t\$"
                  . &price( $interval_hash{$key}{'lowest'} ) . "\t\$"
                  . &price( $lowest_average_price{$key} ) . "\t\$"
                  . &price( $interval_hash{$key}{'amazon'} ) . "\t"
                  . $product_information{$key}{surl} . "\t"
                  . &compact( $current_product_prices{$key}{Title} ) . "...\t"
                  . &compact( $current_product_prices{$key}{Author} ) . "...\n";
                  #. $value{$key} . "\n";
            }
        }
        if ( $k > 0 ) {
            $email_hash{$_} .= "\nItems that have changed value $price_interval_fmt \n";
            $email_hash{$_} .= "Price\t\tChange\tLast\t\tAvg.\t\tAmazon\tURL\t\t\t\tTitle\t\t\t\t\tAuthor\n";
            $email_hash{$_} .= $sub_email_copy;
        }
    }
    for ( $b = 0 ; $b <= 4 ; $b++ ) {
        if ( $email_hash{$b} ) {
            $email_copy .= $email_hash{$b};
        }
    }
    return $email_copy;

}


sub product_discount {	
	my $email_copy;
    foreach my $key ( sort { $product_discount{$b} <=> $product_discount{$a} } ( keys(%product_discount) ) ) {
		$email_copy .= ""
			  . $product_discount{$key} . "\%\t\$"
              . &price($lowest_price{ $key }) . "\t\$"
              . &price($lowest_average_price{ $key }) . "\t\$"
              . &price($current_product_prices{$key}{AmaPrice}) . "\t"
			  . &compact($current_product_prices{$key}{Title}) ."...\t"
			  . &compact($current_product_prices{$key}{Author}) ."...\t"
			  . $product_information{$key}{surl} . "\n";
			  #. &value_comparison($lowest_average_price{ $key }, $lowest_price{ $key }) . "\n";
	}
	return $email_copy; 
}

sub lowest_price {
	my $email_copy;	
    foreach my $key ( sort { $lowest_price{$a} <=> $lowest_price{$b} } ( keys(%lowest_price) ) ) {
		$email_copy .= "\$"
              . &price($lowest_price{ $key }) . "\t\$"
			  . $product_discount{$key} . "\%\t\$"
              . &price($lowest_average_price{ $key }) . "\t\$"
              . &price($current_product_prices{$key}{AmaPrice}) . "\t"
			  . &compact($current_product_prices{$key}{Title}) ."...\t"
			  . &compact($current_product_prices{$key}{Author}) ."...\t"
			  . $product_information{$key}{surl} . "\n";
			  #. &value_comparison($lowest_average_price{ $key }, $lowest_price{ $key })  . "\n";
	}
	return $email_copy; 
}

##############################


sub value {
	my $key = $_[0];
	my $lp = $_[1];
   	my $value = "";

	if ( $lp > $lowest_average_price{$key} ) {
		unless ( sprintf( "%.2f", ( $lp / 100 ) ) eq sprintf( "%.2f", ( $lowest_average_price{$key} / 100 ) )) {
			my $disc = ($lp / $lowest_average_price{$key}) * 10;
			for ( $b = 1 ; $b <= $disc ; $b++ ) {
	            if ( $b >= 10 ) {
	                $value .= "-";
	            }
	        }
		}
	}
	if ( $lp < $lowest_average_price{$key} ) {
		unless ( sprintf( "%.2f", ( $lp / 100 ) ) eq sprintf( "%.2f", ( $lowest_average_price{$key} / 100 ) )) {
			my $disc = ($lowest_average_price{$key} / $lp) * 10;
			for ( $b = 1 ; $b <= $disc ; $b++ ) {
	            if ( $b >= 10 ) {
	                $value .= "+";
	            }
	        }
		}
	}
	return substr( $value, 0, 6 );
}

sub value_comparison {
	my $cp = $_[0];
	my $lp = $_[1];
   	my $value = "";

	if ( ($lp > $cp) && ($cp ne 0) ) {
		unless ( sprintf( "%.2f", ( $lp / 100 ) ) eq sprintf( "%.2f", ( $cp / 100 ) )) {
			my $disc = ($lp / $cp) * 10;
			for ( $b = 1 ; $b <= $disc ; $b++ ) {
	            if ( $b >= 10 ) {
	                $value .= "-";
	            }
	        }
		}
	}
	if ( ($lp < $cp) && ($lp ne 0) ) {
		unless ( sprintf( "%.2f", ( $lp / 100 ) ) eq sprintf( "%.2f", ( $cp / 100 ) )) {
			my $disc = ($cp / $lp) * 10;
			for ( $b = 1 ; $b <= $disc ; $b++ ) {
	            if ( $b >= 10 ) {
	                $value .= "+";
	            }
	        }
		}
	}
	return substr( $value, 0, 6 );
}


sub compact {
	my $text = $_[0];
	return substr( $text, 0, 19 );
}

sub price {
	my $val = $_[0];
	if ($val == 0) {
		return "N/A";
	}
	else {
		my $fval = sprintf( "%.2f", ( $_[0] / 100 ) );
		return $fval;
	}
}

##############################################################
# Utility Functions

##
# Amazon XML Parsing

# This routine is fairly straightforward.  We are parsing the XML and assigning the value to variables.
# The main challenge is figuring out the author title.  Books can either have authors or editors.  
# The Author object is just an array of names.  The Editor is actually a hash of creators.  
sub ar_parse {
	
	# We're passed the data (XML object) and iterator
    my $data = $_[0];
    my $k    = $_[1];
	my %list;
	
	# This variable captures either our author 
    my $z;
	
	# If there is an author specified
    if ( $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Author} )
    {
		# If there is more than one author
        if (ref($data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Author}) eq "ARRAY")
        {
			# We collapse the array of authors we assign it to z
            $z = join(', ',@{$data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Author}});
        }
		# If there is just one author we assign it to z
        elsif ( $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Author} )
        {
            $z = $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Author};
        }
    }
	# If there is no author, but there is a creator specified
    elsif ( $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Creator} )
    {
		# If there is more than one creator
        if ( ref( $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Creator} ) eq "ARRAY" )
        {
			# We get the number of creators
            my $x = $#{ $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Creator} };
            my $m;
			
			# We iterate through creators, assigning them to z, appending a comma between creators (except for the last) 
            for ( $m = 0 ; $m <= $x ; $m++ ) {
                $z .= $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Creator}->[$m]->{content};
 				# Unless it is the last item on the list
				unless ( $m == $x ) {
                	$z .= ", ";
                }
            }
        }
		# If there is only one creator, the data is a hash.  So we have to iterate through the hash.
        elsif ( ref( $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Creator} ) eq "HASH" )
        {
            for my $key ( keys %{ $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Creator} } )
            {
                my $value = ${ $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Creator} }{$key};
                $z = "$value";
            }
        }
    }
	else
	{
		$z = $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Manufacturer};
	}

	# Assign values to our list hash (global)
    %list = (
    	"Title" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{Title},
        "Author" => $z,
    	"ProductGroup" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{ProductGroup},
        "ASIN" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ASIN},
        "UsedPrice" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{OfferSummary}->{LowestUsedPrice}->{Amount},
        "TotalUsed" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{OfferSummary}->{TotalUsed},
        "NewPrice" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{OfferSummary}->{LowestNewPrice}->{Amount},
        "TotalNew" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{OfferSummary}->{TotalNew},
        "TotalUsed" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{OfferSummary}->{TotalUsed},
        "TotalCollectible" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{OfferSummary}->{TotalCollectible},
        "TotalRefurbished" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{OfferSummary}->{TotalRefurbished},
        "AmaPrice" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{Offers}->{Offer}->{OfferListing}->{Price}->{Amount},
        "ListPrice" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{ItemAttributes}->{ListPrice}->{Amount},
        "URL" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{DetailPageURL},
		"SmallImage" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{SmallImage}->{URL},
		"MediumImage" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{MediumImage}->{URL},
		"LargeImage" => $data->{Lists}->{List}->{ListItem}->[$k]->{Item}->{LargeImage}->{URL},
    );

	# If there are any null values, assign them to 0
    for my $key ( keys %list )
    {
		unless ($list{$key})
		{
			$list{$key} = "0";
		}
    }
    if ( $debug >= 4 ) { print Dumper(%list); }

    # Return the cleaned list to master
    return (%list);
}

sub na_parse {
    my $data = shift;
	my %list;
    
	# This variable captures either our author 
    my $z;
	
	# If there is an author specified
    if ( $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Author} )
    {
		# If there is more than one author
        if (ref($data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Author}) eq "ARRAY")
        {
			# We collapse the array of authors we assign it to z
            $z = join(', ',@{$data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Author}});
        }
		# If there is just one author we assign it to z
        elsif ( $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Author} )
        {
            $z = $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Author};
        }
    }
	# If there is no author, but there is a creator specified
    elsif ( $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Creator} )
    {
		# If there is more than one creator
        if ( ref( $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Creator} ) eq "ARRAY" )
        {
			# We get the number of creators
            my $x = $#{ $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Creator} };
            my $m;
			
			# We iterate through creators, assigning them to z, appending a comma between creators (except for the last) 
            for ( $m = 0 ; $m <= $x ; $m++ ) {
                $z .= $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Creator}->[$m]->{content};
 				# Unless it is the last item on the list
				unless ( $m == $x ) {
                	$z .= ", ";
                }
            }
        }
		# If there is only one creator, the data is a hash.  So we have to iterate through the hash.
        elsif ( ref( $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Creator} ) eq "HASH" )
        {
            for my $key ( keys %{ $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Creator} } )
            {
                my $value = ${ $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Creator} }{$key};
                $z = "$value";
            }
        }
    }
	else
	{
		$z = $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Manufacturer};
	}

	# Assign values to our list hash (global)
    %list = (
    	"Title" => $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{Title},
        "Author" => $z,
    	"ProductGroup" => $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{ProductGroup},
        "ASIN" => $data->{Lists}->{List}->{ListItem}->{Item}->{ASIN},
        "UsedPrice" => $data->{Lists}->{List}->{ListItem}->{Item}->{OfferSummary}->{LowestUsedPrice}->{Amount},
        "TotalUsed" => $data->{Lists}->{List}->{ListItem}->{Item}->{OfferSummary}->{TotalUsed},
        "NewPrice" => $data->{Lists}->{List}->{ListItem}->{Item}->{OfferSummary}->{LowestNewPrice}->{Amount},
        "TotalNew" => $data->{Lists}->{List}->{ListItem}->{Item}->{OfferSummary}->{TotalNew},
        "TotalUsed" => $data->{Lists}->{List}->{ListItem}->{Item}->{OfferSummary}->{TotalUsed},
        "TotalCollectible" => $data->{Lists}->{List}->{ListItem}->{Item}->{OfferSummary}->{TotalCollectible},
        "TotalRefurbished" => $data->{Lists}->{List}->{ListItem}->{Item}->{OfferSummary}->{TotalRefurbished},
        "AmaPrice" => $data->{Lists}->{List}->{ListItem}->{Item}->{Offers}->{Offer}->{OfferListing}->{Price}->{Amount},
        "ListPrice" => $data->{Lists}->{List}->{ListItem}->{Item}->{ItemAttributes}->{ListPrice}->{Amount},
        "URL" => $data->{Lists}->{List}->{ListItem}->{Item}->{DetailPageURL},
		"SmallImage" => $data->{Lists}->{List}->{ListItem}->{Item}->{SmallImage}->{URL},
		"MediumImage" => $data->{Lists}->{List}->{ListItem}->{Item}->{MediumImage}->{URL},
		"LargeImage" => $data->{Lists}->{List}->{ListItem}->{Item}->{LargeImage}->{URL}
    );

	# If there are any null values, assign them to 0
    for my $key ( keys %list )
    {
		unless ($list{$key})
		{
			$list{$key} = "0";
		}
    }
    if ( $debug >= 4 ) { print Dumper(%list); }

    # Return the cleaned list to master
    return (%list);
}

##
# Processing and utility routines

sub email {
    my $sendmail = "/usr/local/bin/sendmail -t";
    my $from     = "From: Wishlist Processing <aw\@fstutzman.com>\n";
    my $reply_to = "Reply-to: fred\@fredstutzman.com\n";
    my $subject  = "Subject: Wishlist Analytics\n";
    my $content  = $_[0];
    my $send_to  = "To: $_[1]\n";

    open( SENDMAIL, "|$sendmail" ) or die "Cannot open $sendmail: $!";
    print SENDMAIL $from;
    print SENDMAIL $reply_to;
    print SENDMAIL $subject;
    print SENDMAIL $send_to;
    print SENDMAIL "Content-type: text/plain\n\n";
    print SENDMAIL $content;
    close(SENDMAIL);

    #print $content;
}

sub print_a {
    my (%list) = %{ $_[0] };
 	print "\nASIN: ". $list{ASIN};
    print "\nTitle: ". $list{Title};
 	print "\nAuthor/Manufacturer: ". $list{Author};
 	print "\nProduct Group: ". $list{ProductGroup};
	print "\nList Price: ". $list{ListPrice};
	print "\nAmazon Price: ". $list{AmaPrice};
	print "\nUsed Price: " . $list{UsedPrice};
	print "\nLowest New Price: " . $list{NewPrice};
	print "\nTotal Remaining New: " .$list{TotalNew} . " Used: " . $list{TotalUsed} . " Collectible: " . $list{TotalCollectible} . " Refurbished: " . $list{TotalRefurbished};
    print "\nURL: " . $list{URL};
    print "\nSmallImage: " . $list{SmallImage};
    print "\nMediumImage: " . $list{MediumImage};
    print "\nLargeImage: " . $list{LargeImage};
}

sub shorten {
    my $shurl        = "http://is.gd/api.php?longurl=" . uri_escape(shift);
 	my $bb;
    for($bb=1; $bb<=5; $bb++) {
    	my $inbound_link = $browser->get($shurl);
	    if ($inbound_link->content_type =~ m/text\/.*/ && $inbound_link->is_success) {       
			my $response = $inbound_link->content;
    		return $response;
		}
	}
	return "N/A";
}

sub realtime {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( time - ( $_[0] * 60 ) );
    $year += 1900;
    $mon++;
    if ( $mon < 10 )  { $mon  = "0$mon"; }
    if ( $mday < 10 ) { $mday = "0$mday"; }
    if ( $hour < 10 ) { $hour = "0$hour"; }
    if ( $min < 10 )  { $min  = "0$min"; }
    if ( $sec < 10 )  { $sec  = "0$sec"; }
    my $realtime = "$year-$mon-$mday $hour:$min:$sec";
    return $realtime;
}

sub log_ {
	open(LOG, ">>$_[0]") or die ("$_[0] not able to be opened");
	my $time = &realtime(0);
	print LOG "$time\ $_[1]\ $_[2]\n";
	close(LOG);
}



