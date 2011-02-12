# amazon-analytics

Simple program to calculate price movement on an Amazon wishlist, and provide a simple, email-based visualization when price variance indicates a high likelihood of value purchase.

### Setup

The program was written in Perl, with a Mysql backend database (running locally or remotely).

Requires the following modules:

* DBI;
* LWP;
* FileHandle;
* Date::Manip;
* XML::Simple;
* Data::Dumper;
* URI::Escape;
* RequestSignatureHelper;
* LWP::UserAgent;
* XML::Simple;
* Data::Dumper;

To configure the program, edit `conf/config.dev.pl` - you can also set up a `config.prod.pl` when you move from testing to "production."

You'll also need to edit the crawler to add your wishlist ID - the crawler accepts a hash of wishlist ID's if you want to run across multiple lists.

### Note

This software is unmaintained - Amazon ended the affiliate program in NC.

## License

The MIT License (MIT)
Copyright (c) 2011 Fred Stutzman

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.