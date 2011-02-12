#!/usr/bin/perl -w

##############################################################################################
# Copyright 2009 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file 
# except in compliance with the License. A copy of the License is located at
#
#       http://aws.amazon.com/apache2.0/
#
# or in the "LICENSE.txt" file accompanying this file. This file is distributed on an "AS IS"
# BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under the License. 
#
#############################################################################################
#
#  Amazon Product Advertising API
#  Signed Requests Sample Code
#
#  API Version: 2009-03-31
#
#############################################################################################

use strict;
use warnings;

use Data::Dumper;

use RequestSignatureHelper;
use LWP::UserAgent;
use XML::Simple;

use constant myAWSId	    => 'YOUR_ACCESS_KEY_ID_HERE';
use constant myAWSSecret    => 'YOUR_SECRET_KEY_HERE';
use constant myEndPoint	    => 'ecs.amazonaws.com';

# see if user provided ItemId on command-line
my $itemId = shift @ARGV || '0545010225';

# Set up the helper
my $helper = new RequestSignatureHelper (
    +RequestSignatureHelper::kAWSAccessKeyId => myAWSId,
    +RequestSignatureHelper::kAWSSecretKey => myAWSSecret,
    +RequestSignatureHelper::kEndPoint => myEndPoint,
);

# A simple ItemLookup request
my $request = {
    Service => 'AWSECommerceService',
    Operation => 'ItemLookup',
    Version => '2009-03-31',
    ItemId => $itemId,
    ResponseGroup => 'Small',
};

# Sign the request
my $signedRequest = $helper->sign($request);

# We can use the helper's canonicalize() function to construct the query string too.
my $queryString = $helper->canonicalize($signedRequest);
my $url = "http://" . myEndPoint . "/onca/xml?" . $queryString;
print "Sending request to URL: $url \n";

my $ua = new LWP::UserAgent();
my $response = $ua->get($url);
my $content = $response->content();
print "Recieved Response: $content \n";

my $xmlParser = new XML::Simple();
my $xml = $xmlParser->XMLin($content);

print "Parsed XML is: " . Dumper($xml) . "\n";

if ($response->is_success()) {
    my $title = $xml->{Items}->{Item}->{ItemAttributes}->{Title};
    print "Item $itemId is titled \"$title\"\n";
} else {
    my $error = findError($xml);
    if (defined $error) {
	print "Error: " . $error->{Code} . ": " . $error->{Message} . "\n";
    } else {
	print "Unknown Error!\n";
    }
}

sub findError {
    my $xml = shift;
    
    return undef unless ref($xml) eq 'HASH';

    if (exists $xml->{Error}) { return $xml->{Error}; };

    for (keys %$xml) {
	my $error = findError($xml->{$_});
	return $error if defined $error;
    }

    return undef;
}
