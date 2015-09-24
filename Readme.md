# Passwd.cgi

A simple cgi script for managing Unix system accounts.

## Description

This script is a very basic webpage for managing unix accounts on your server.
Most services (email, bboards, photo galleries) all have their own internal
users and as a result, their own internal password management. If you setup
your server to use system users password management turns into a lesson in
using ssh and running passwd. This script provides a web interface to this
functionality while having nearly no overhead.

This script supports a lost password contact info, changing your password and
requesting a new password. Changes to your info require email confirmation and
all emails have expirations to make sure no one can later on change your
password.

Written in bash (which ever linux system has) and uses only system commands.
Nice and simple.

## Setup

Copy the script file into your cgi-bin directory. Modify the configuration
parameters to match your system.

Once configured, run as root with the `--setup` option to install the 
proper directories/files.

    $ sudo ./passwd.sh --setup
    Enter user that runs cgi scripts (http):
    Created /var/lib/passwd.sh
    Initialized database
    Install complete

To allow this script to recover lost passwords it requires sudo access to
`/usr/bin/chpasswd`. To do this run `sudo visudo` and edit:

    # Access for passwd.sh cgi script
    http ALL=(ALL) NOPASSWD:/usr/bin/chpasswd

Use the account that runs your cgi scripts. After that hit the script from
a web browser and thats it.

## Options

    # Path to store database info
    DB_DIR="/var/lib/passwd.sh"
    
    # Title of page
    TITLE="Account Management"
    
    # Full URL path. This is used in the HTML generation, all forms will
    # point to this path
    URL="https://example.com/cgi-bin/passwd.sh"
    
    # Email Account info for sender
    # Account is required as sendmail may get rejected if your server
    # is setup to not allow random non-existant accounts to send email.
    EMAIL_FROM_NAME="Webmaster"
    EMAIL_FROM_ADDRESS="webmaster@example.com"
    
    # Expiration (in seconds) for Reset requests and Confirmation acknowledgments.
    # If cron mode is run after the expiration then all keys will be made invalid.
    EXPIRATION=3600 # 1 hour in seconds
    
    # List of users that are not allowed to be updated/modified by this script.
    BLACKLIST=(root http nobody)

## Cron Cleanup Support

The script supports expirations on all confirmations. When a contact or reset
email is issued an expiration is set. A periodic cron job can be setup to clean
up all keys that are no longer valid.

Setup the cronjob as either root or the cgi user.

    */5 * * * * /srv/http/cgi-bin/passwd.sh -c

## License and Acknowledgements

This script uses bash_cgi created by Philippe Kehl. See
[site](http://oinkzwurgl.org/bash_cgi) for more information.

The reset of this script is released on the New BSD License.
