#!/bin/bash - 
#===============================================================================
# Copyright (c) 2015 Jeff Parent
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
#  * Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#  * Neither the name of the passwd.sh authors nor the names of its contributors
#    may be used to endorse or promote products derived from this software without
#    specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
#          FILE: passwd.sh
#
#         USAGE: ./passwd.sh 
#
#   DESCRIPTION: cgi script to modify unix passwords
#
#       OPTIONS: ---
#  REQUIREMENTS: sudo access to chpasswd
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: jecxjo (jeff@commentedcode.org)
#  ORGANIZATION:
#       CREATED: 09/20/15 13:28
#      REVISION: 0.0.5
#
#     CHANGELOG: 0.0.5 - Cron support and reset expirations
#                0.0.4 - Security holes and cleanup
#                0.0.3 - Moved bash_cgi code to file
#                0.0.2 - Clean up
#                0.0.1 - Initial version
#
#===============================================================================


# Global Vars
URL="https://example.com/cgi-bin/passwd.sh"
TITLE="Account Management"
EMAIL_FROM_NAME="Webmaster"
EMAIL_FROM_ADDRESS="webmaster@example.com"
USER_DB="/var/lib/passwd.sh/users.db"
RESET_DB="/var/lib/passwd.sh/reset.db"
CONFIRM_DB="/var/lib/passwd.sh/confirm.db"
EXPIRATION=3600 # 1 hour in seconds
RND_CMD=$(/usr/bin/dd if=/dev/random bs=1 count=32 2>/dev/null | \
          /usr/bin/base64 | \
          /usr/bin/sed 's|+||g' | \
          /usr/bin/sed 's|/||g' | \
          /usr/bin/sed 's|=||g' | \
          /usr/bin/sed 's| ||g')

BLACKLIST=(root http nobody)

#########
# Mutex #
#########
function LockConfirmMutext () {
  local count=5
  while [[ ${count} > 0 ]]
  do
    if mkdir /tmp/passwd.sh.confirm.lock; then
      echo "LOCKED"
      return
    fi
    count=$(( count - 1 ))
    sleep 1
  done
}

function UnlockConfirmMutex () {
  rm -rf /tmp/passwd.sh.confirm.lock
}

function LockResetMutex () {
  local count=5
  while [[ ${count} > 0 ]]
  do
    if mkdir /tmp/passwd.sh.reset.lock; then
      echo "LOCKED"
      return
    fi
    count=$(( count - 1 ))
    sleep 1
  done
}

function UnlockResetMutex () {
  rm -rf /tmp/passwd.sh.reset.lock
}

function LockUserMutex () {
  local count=5
  while [[ ${count} > 0 ]]
  do
    if mkdir /tmp/passwd.sh.user.lock; then
      echo "LOCKED"
      return
    fi
    count=$(( count - 1 ))
    sleep 1
  done
}

function UnlockUserMutex () {
  rm -rf /tmp/passwd.sh.user.lock
}

#################
# Confirm Reset #
#################

# Apply new password and output HTML status
# 1->user, 2->pass
function ResetPass () {
  local user=$(IsSaneUser "$1") pass="$2"

  if [ "$(LockResetMutex)" == "LOCKED" ]; then
    # write new user:pass to system
    echo "${user}:${pass}" | /usr/bin/sudo /usr/bin/chpasswd

    # Check if password change was successful
    if [ $? -eq 0 ]; then
      echo "<b>Success:</b> Password changed successfully<br />"

      # Remove all instances of reset keys
      umask 026
      local tmp=$(mktemp /tmp/reset.XXXXXX)
      sed "/:${user}:/d" "${RESET_DB}" > "${tmp}"
      cp --no-preserve=mode,ownership "${tmp}" "${RESET_DB}"
      rm "${tmp}"
    else
      echo "<b>Error 01:</b> Failed setting password<br />"
    fi
    UnlockResetMutex
  else
    echo "<b>Error 02:</b> Failed setting password<br />"
  fi
}

# Check if Key:User DB and return HTML Form to reset
# 1->user, 2->key
function ConfirmReset () {
  local user=$(IsSaneUser "$1") key="$2"
  /usr/bin/grep -q "^${key}:${user}" "${RESET_DB}"

  # Check if reset code is valid
  if [ $? -eq 0 ]; then
    # Create form to enter new password
    /usr/bin/cat <<EOF
<form action="${URL}" method="POST">
  <fieldset>
    <legend>Reset Password</legend>
    <input type="hidden" name="cmd" id="cmd" value="resetpass" />
    <input type="hidden" name="key" id="key" value="${key}" />
    <input type="hidden" name="user" id="user" value="${user}" />
    <p><label class="field" for="pass">Password:</label><input type="password" name="pass" id="pass" class="textbox-300" /></p>
    <p><label class="field" for="passcfm">Confirm:</label><input type="password" name="passcfm" id="passcfm" class="textbox-300" /></p>
    <input type="submit" value="Submit" />
  </fieldset>
</form>
EOF
  else
    echo "<b>Error 03:</b> Reset code is not valid<br />"
  fi
}

# Check if all form data is valid for new password on reset
# as generated by ConfirmReset
# 1->user, 2->key, 3->pass, 4->cfm
function ApplyNewPass () {
  local user=$(IsSaneUser "$1") key="$2" pass="$3" cfm="$4"

  if [ -z "${user}" ]; then
    echo "<b>Error 04:</b> No User entered<br />"
  elif [ -z "${key}" ]; then
    echo "<b>Error 05:</b> No Key<br />"
  elif [ -z "${pass}" ]; then
    echo "<b>Error 06:</b> No New Password<br />"
    ConfirmReset "${user}" "${key}"
  elif [ -z "${cfm}" ]; then
    echo "<b>Error 07:</b> No New Password<br />"
    ConfirmReset "${user}" "${key}"
  else
    /usr/bin/grep -q "^${user}:" /etc/passwd

    if [ $? -eq 1 ]; then
      echo "<b>Error 08:</b> User does not exist<br />"
    elif [ "${pass}" != "${cfm}" ]; then
      echo "<b>Error 09:</b> New Passwords don't match<br />"
      ConfirmReset "${user}" "${key}"
    else
      ResetPass "${user}" "${pass}"
    fi
  fi
}

##################
# Password Reset #
##################

# Find Email Address from Contact Info
# 1->user
function GetAddress () {
  local user=$(IsSaneUser "$1")
  /usr/bin/awk -v user="^${user}:" 'BEGIN { FS = ":" } { if ( $0 ~ user ){ print $2; exit 0; }}' "${USER_DB}"
}

# Create form to request Reset Email
# 1->user
function UserResetForm () {
  local user=$(IsSaneUser "$1")

  /usr/bin/cat <<EOF
<form action="${URL}" method="POST">
  <fieldset>
    <legend>Reset Password</legend>
    <input type="hidden" name="cmd" id="cmd" value="setreset" />
    <p><label class="field" for="user">User:</label><input type="text" name="user" id="user" class="textbox-300" value="${user}" /></p>
    <input type="submit" value="Submit" />
  </fieldset>
</form>
EOF
}

# Create Email, send it and then generate HTML status
# 1->user
function ApplyReset () {
  local user=$(IsSaneUser "$1")
  local key="${RND_CMD}"

  if [ -z "${user}" ]; then
    echo "<b>Error 10:</b> No User entered<br />"
    UserResetForm ""
  else
    /usr/bin/grep -q "^${user}:" /etc/passwd

    if [ $? -eq 1 ]; then
      echo "<b>Error 11:</b> User does not exist<br />"
      UserResetForm ""
    else
      /usr/bin/grep -q "^${user}:" "${USER_DB}"

      if [ $? -eq 1 ]; then
        echo "<b>Error 12:</b> User has no contact info<br />"
        UserResetForm ""
      else
        if [ "$(LockResetMutex)" == "LOCKED" ]; then
          # Create Email message
          local subject="Password Reset"
          local link="${URL}?cmd=cfmreset&user=${user}&key=${key}"
          local address=$(GetAddress "${user}")
          local message=$(/usr/bin/cat <<EOF
A request was made to reset the password for ${user}. If this was in error
please ignore this message. Otherwise follow the link to reset your account
password:

${link}

Thank you
EOF)
          local mail="subject:${subject}\nfrom:${EMAIL_FROM_ADDRESS}\n\n${message}"

          echo -e "${mail}" | /usr/bin/sendmail -F "${EMAIL_FROM_NAME}" -f "${EMAIL_FROM_ADDRESS}" "${address}"

          if [ $? -eq 0 ]; then
            echo "<b>Success:</b> Email sent<br />"
            # Write key to database
            local now=$(/usr/bin/date +%s)
            local timeout=$(( ${now} + ${EXPIRATION} ))
            echo "${key}:${user}:$timeout" >> "${RESET_DB}"
          else
            echo "<b>Error 13:</b> Failed sending email<br />"
          fi
          UnlockResetMutex
        else
          echo "<b>Error 14:</b> System in use, please try again<br />"
        fi
      fi
    fi
  fi
}

################
# Set Password #
################

# Create form to change password
# 1->user 2->old_pass
function UserPassForm () {
  local user=$(IsSaneUser "$1")
  local old_pass=$2

  /usr/bin/cat <<EOF
<form action="${URL}" method="POST">
  <fieldset>
    <legend>Change Password</legend>
    <input type="hidden" name="cmd" id="cmd" value="setpass" />
    <p><label class="field" for="user">User:</label> <input type="text" name="user" id="user" value="${user}" /></p>
    <p><label class="field" for="oldpass">Old Password:</label><input type="password" name="oldpass" id="oldpass" value="${old_pass}" /></p>
    <p><label class="field" for="pass">New Password:</label> <input type="password" name="pass" id="pass" /></p>
    <p><label class="field" for="passcfm">Confirm Password:</label> <input type="password" name="passcfm" id="passcfm" /></p>
    <input type="submit" value="Submit" />
  </fieldset>
</form>
EOF
}

# Apply new password to user and generate HTML status
# 1->user, 2->old pass, 3->new pass
function SetPass () {
  local user=$(IsSaneUser "$1") pass=$2 new=$3

  local out=$(echo -e "${pass}\n${pass}\n${new}\n${new}" | /usr/bin/su -c 'if /usr/bin/passwd; then echo "SUCCESS"; fi ' "${user}")

  echo "${out}" | /usr/bin/grep -q "SUCCESS"

  if [ $? -eq 0 ]; then
    echo "<b>Success:</b> Password Changed<br />"
  else
    echo "<b>Error 15:</b> Failed changing password[${out}]<br />"
  fi
}

# Validate form data generated by UserPassForm
# 1->user, 2->old, 3->newa, 4->newb
function ApplyPass () {
  local user=$(IsSaneUser "$1")
  local old="$2"
  local newa="$3"
  local newb="$4"

  if [ -z "${user}" ]; then
    echo "<b>Error 16:</b> Invalid User<br />"
    UserPassForm "" ""
  elif [ -z "${old}" ]; then
    echo "<b>Error 17:</b> No Old Password<br />"
    UserPassForm "${user}" ""
  elif [ -z "${newa}" ]; then
    echo "<b>Error 18:</b> No New Password<br />"
    UserPassForm "${user}" "${old}"
  elif [ -z "${newb}" ]; then
    echo "<b>Error 19:</b> No New Password<br />"
    UserPassForm "${user}" "${old}"
  else
    /usr/bin/grep -q "^${user}:" /etc/passwd

    if [ $? -eq 1 ]; then
      echo "<b>Error 20:</b> User does not exist<br />"
      UserPassForm "" ""
    elif [ "${newa}" != "${newb}" ]; then
      echo "<b>Error 21:</b> New Passwords don't match<br />"
      UserPassForm "${user}" "${old}"
    else
      SetPass "${user}" "${old}" "${newa}"
    fi
  fi
}

################
# Contact Info #
################

# Create form to update Contact Info
# 1->user, 2->email
function UserContactForm () {
  local user=$(IsSaneUser "$1") email=$(IsSaneEmail "$2")

  /usr/bin/cat <<EOF
<form action="${URL}" method="POST">
  <fieldset>
    <legend>Change Contact Info</legend>
    <input type="hidden" name="cmd" id="cmd" value="sendcfmcontact" />
    <p><label class="field" for="user">User:</label><input type="text" name="user" id="user" value="${user}" /></p>
    <p><label class="field" for="user">Password:</label><input type="password" name="pass" id="pass"  /></p>
    <p><label class="field" for="user">Email:</label><input type="email" name="email" id="email" value="${email}" /></p>
    <input type="submit" value="Submit" />
  </fieldset>
</form>
EOF
}

# Apply new contact info and generate HTML status
# 1->user, 2->key
function SetContact () {
  local user=$(IsSaneUser "$1") key="$2"

  if [ "$(LockConfirmMutext)" == "LOCKED" ]; then
    if [ "$(LockUserMutex)" == "LOCKED" ]; then

      /usr/bin/grep -q "^${key}:${user}:" "${CONFIRM_DB}"

      if [ $? -eq 0 ]; then
        # Copy and remove entry from Confirm
        local email=$(awk -v ku="${key}:${user}" 'BEGIN { FS = ":" } { if ( $0 ~ ku ){ print $3; exit 0; } }' "${CONFIRM_DB}")

        # Remove entry from Confirm
        local tmp=$(/usr/bin/mktemp /tmp/confirm.XXXXXX)
        /usr/bin/sed "/^${key}:${user}:/d" "${CONFIRM_DB}" > "${tmp}"
        cp --no-preserve=mode,ownership "${tmp}" "${CONFIRM_DB}"

        # Remove old entry from Contact and insert new
        /usr/bin/sed "/^${user}:/d" "${USER_DB}" > "${tmp}"
        echo "${user}:${email}" >> "${tmp}"

        # Move back
        cp --no-preserve=mode,ownership "${tmp}" "${USER_DB}"

        # Clean up
        rm "${tmp}"
        echo "<b>Success:</b> New contact info verified<br />"
      else
        echo "<b>Error 22:</b> Key not valid<br />"
      fi
      UnlockUserMutex
    else
      echo "<b>Error 23:</b> System in use, please try again<br />"
    fi
    UnlockConfirmMutex
  else
    echo "<b>Error 24:</b> System in use, please try again<br />"
  fi
}

# Validate form data from email
# 1->user, 2->key
function ApplyContact () {
  local user=$(IsSaneUser "$1") key="$2"

  if [ -z "${user}" ]; then
    echo "<b>Error 25:</b> Invalid Username<br />"
  else
    /usr/bin/grep -q "^${user}:" /etc/passwd

    if [ $? -eq 1 ]; then
      echo "<b>Error 26:</b> User does not exist<br />"
    else
      SetContact "${user}" "${key}"
    fi
  fi
}

# Sends a confirmation and stores key
# 1->user, 2->pass, 3->email
function SendConfirm () {
  local user=$(IsSaneUser "$1") pass="$2" email=$(IsSaneEmail "$3")

  local f="/tmp/${user}"
  # Touch file as user, requires correct password
  local out=$(echo -e "${pass}\n" | /usr/bin/su -c "/usr/bin/touch \"${f}\"" - "${user}")

  if [ -e "${f}" ]; then
    local out=$(echo -e "${pass}\n" | /usr/bin/su -c "rm \"${f}\"" - "${user}")
    if [ "$(LockConfirmMutext)" == "LOCKED" ]; then
      # Create email
      local key=$"${RND_CMD}"
      local subject="Contact Confirmation"
      local link="${URL}?cmd=cfmcontact&user=${user}&key=${key}"
      local message=$(/usr/bin/cat <<EOF
A request was made to change the contact info for "${user}". If this was
in error please ignore this message. Otherwise follow the link to confirm
this address.

${link}

Thank you
EOF)
      local mail="subject:${subject}\nfrom:${EMAIL_FROM_ADDRESS}\n\n${message}"
      echo -e "${mail}" | /usr/bin/sendmail -F "${EMAIL_FROM_NAME}" -f "${EMAIL_FROM_ADDRESS}" "${email}"

      if [ $? -eq 0 ]; then
        # write key to database
        local now=$(/usr/bin/date +%s)
        local timeout=$(( ${now} + ${EXPIRATION} ))
        echo "${key}:${user}:${email}:${timeout}" >> "${CONFIRM_DB}"
        echo "<b>Success:</b> Confirmation email sent<br />"
      else
        echo "<b>Error 27:</b> Failed sending email<br />"
      fi
      UnlockConfirmMutex
    else
      echo "<b>Error 28:</b> System in use, please try again<br />"
    fi
  else
    echo "<b>Error 29:</b> Username/Password incorrect<br />"
  fi
}

# Validate params from UserContactForm and email confirmation
# 1->user, 2->pass, 3->email
function SendConfirmContact () {
  local user=$(IsSaneUser "$1") pass="$2" email=$(IsSaneEmail "$3")

  if [ -z "${user}" ]; then
    echo "<b>Error 30:</b> Invalid Username<br />"
    UserContactForm "" "${email}"
  elif [ -z "${pass}" ]; then
    echo "<b>Error 31:</b> Invalid Password<br />"
    UserContactForm "${user}" "${email}"
  elif [ -z "${email}" ]; then
    echo "<b>Error 32:</b> Invalide Email<br />"
    UserContactForm "${user}" ""
  else
    /usr/bin/grep -q "^${user}:" /etc/passwd

    if [ $? -eq 1 ]; then
      echo "<b>Error 33:</b> User does not exist<br />"
      UserContactForm "" "${email}"
    else
      SendConfirm "${user}" "${pass}" "${email}"
    fi
  fi
}

####################
# Main Application #
####################

# Switch on URL argument "cmd" to generate correct page
# $1->cmd
function Body () {
  /usr/bin/cat <<EOF
<body>
  <h1>${TITLE}</h1>
EOF

  cgi_getvars BOTH cmd
  case "${cmd}" in
    resetpass)
      cgi_getvars BOTH user
      cgi_getvars BOTH key
      cgi_getvars BOTH pass
      cgi_getvars BOTH passcfm
      ApplyNewPass "${user}" "${key}" "${pass}" "${passcfm}"
      ;;
    cfmreset)
      cgi_getvars BOTH user
      cgi_getvars BOTH key
      ConfirmReset "${user}" "${key}"
      ;;
    setreset)
      cgi_getvars BOTH user
      ApplyReset "${user}"
      ;;
    setpass)
      cgi_getvars BOTH user
      cgi_getvars BOTH oldpass
      cgi_getvars BOTH pass
      cgi_getvars BOTH passcfm
      ApplyPass "${user}" "${oldpass}" "${pass}" "${passcfm}"
      ;;
    cfmcontact)
      cgi_getvars BOTH user
      cgi_getvars BOTH key
      ApplyContact "${user}" "${key}"
      ;;
    resetform)
      cgi_getvars BOTH user
      UserResetForm "${user}"
      ;;
    sendcfmcontact)
      cgi_getvars BOTH user
      cgi_getvars BOTH email
      cgi_getvars BOTH pass
      SendConfirmContact "${user}" "${pass}" "${email}"
      ;;
    contactform)
      cgi_getvars BOTH user
      cgi_getvars BOTH email
      UserContactForm "${user}" "${email}"
      ;;
    passform)
      cgi_getvars BOTH user
      cgi_getvars BOTH oldpass
      UserPassForm "${user}" "${oldpass}"
      ;;
    *)
      cgi_getvars BOTH user
      cgi_getvars BOTH oldpass
      UserPassForm "${user}" "${oldpass}"
      ;;
  esac

  /usr/bin/cat <<EOF
  <br />
  <a href="${URL}?cmd=passform">Password</a>
  <a href="${URL}?cmd=contactform">Contact</a>
  <a href="${URL}?cmd=resetform">Reset Password</a>
  <br />
  <p>Contact <a href="mailto:${EMAIL_FROM_ADDRESS}">${EMAIL_FROM_NAME}</a> if you have any issues</p>
</body>
EOF
}

# START bash_cgi
# Created by Philippe Kehl
# http://oinkzwurgl.org/bash_cgi
# (internal) routine to store POST data
function cgi_get_POST_vars()
{
  # check content type
  # FIXME: not sure if we could handle uploads with this..
  [ "${CONTENT_TYPE}" != "application/x-www-form-urlencoded" ] && \
    echo "bash.cgi warning: you should probably use MIME type "\
    "application/x-www-form-urlencoded!" 1>&2
  # save POST variables (only first time this is called)
  [ -z "$QUERY_STRING_POST" \
    -a "$REQUEST_METHOD" = "POST" -a ! -z "$CONTENT_LENGTH" ] && \
    read -n $CONTENT_LENGTH QUERY_STRING_POST
  # prevent shell execution
  local t
  t=${QUERY_STRING_POST//%60//} # %60 = `
  t=${t//\`//}
  t=${t//\$(//}
  t=${t//%24%28//} # %24 = $, %28 = (
  QUERY_STRING_POST=${t}
  return
}

# (internal) routine to decode urlencoded strings
function cgi_decodevar()
{
  [ $# -ne 1 ] && return
  local v t h
  # replace all + with whitespace and append %%
  t="${1//+/ }%%"
  while [ ${#t} -gt 0 -a "${t}" != "%" ]; do
    v="${v}${t%%\%*}" # digest up to the first %
    t="${t#*%}"       # remove digested part
    # decode if there is anything to decode and if not at end of string
    if [ ${#t} -gt 0 -a "${t}" != "%" ]; then
      h=${t:0:2} # save first two chars
      t="${t:2}" # remove these
      v="${v}"`echo -e \\\\x${h}` # convert hex to special char
    fi
  done
  # return decoded string
  echo "${v}"
  return
}

# routine to get variables from http requests
# usage: cgi_getvars method varname1 [.. varnameN]
# method is either GET or POST or BOTH
# the magic varible name ALL gets everything
function cgi_getvars()
{
  [ $# -lt 2 ] && return
  local q p k v s
  # prevent shell execution
  t=${QUERY_STRING//%60//} # %60 = `
  t=${t//\`//}
  t=${t//\$(//}
  t=${t//%24%28//} # %24 = $, %28 = (
  QUERY_STRING=${t}
  # get query
  case $1 in
    GET)
      [ ! -z "${QUERY_STRING}" ] && q="${QUERY_STRING}&"
      ;;
    POST)
      cgi_get_POST_vars
      [ ! -z "${QUERY_STRING_POST}" ] && q="${QUERY_STRING_POST}&"
      ;;
    BOTH)
      [ ! -z "${QUERY_STRING}" ] && q="${QUERY_STRING}&"
      cgi_get_POST_vars
      [ ! -z "${QUERY_STRING_POST}" ] && q="${q}${QUERY_STRING_POST}&"
      ;;
  esac
  shift
  s=" $* "
  # parse the query data
  while [ ! -z "$q" ]; do
    p="${q%%&*}"  # get first part of query string
    k="${p%%=*}"  # get the key (variable name) from it
    v="${p#*=}"   # get the value from it
    q="${q#$p&*}" # strip first part from query string
    # decode and evaluate var if requested
    [ "$1" = "ALL" -o "${s/ $k /}" != "$s" ] && \
      eval "$k=\"`cgi_decodevar \"$v\"`\""
  done
  return
}

#cgi_getvars BOTH ALL
# END of bash_cgi

################
# Sanitization #
################
# Checks if username is a sane username
# 1->user
function IsSaneUser () {
  local user=$(echo "$1" | /usr/bin/grep "^[0-9A-Za-z-]\+$")
  if [ ! -z "${user}" ]; then
    local count = 0
    while [ "x${BLACKLIST[count]}" != "x" ]
    do
      if [ "${user}" == "${BLACKLIST[count]}" ]; then
        return
      fi
      count=$(( ${count} + 1 ))
    done
  fi
  echo "${user}"
}

# Checks if email is sane
# 1->email
function IsSaneEmail () {
  echo "$1" | /usr/bin/grep -E -o "\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,6}\b"
}

#################
# CLI Functions #
#################
function PrintUsage () {
  /usr/bin/cat <<EOF
usage: passwd.sh [OPTION]

  -h | --help  Print this output
  -c | --cron  Trigger cleanup of expired entries

This application is a CGI script that generates a Unix account password
manager. The script should be executed as a non-root user and the user
should be given sudo access to /usr/bin/chpasswd.

To allow password reset requests to expire, this script should be run as
a cron job with the -c flag.

EOF
}

function CronMode () {
  if [ "$(LockResetMutex)" == "LOCKED" ]; then
    umask 026
    local file=$(/usr/bin/mktemp /tmp/reset.XXXXXX)

    /usr/bin/awk -v now=$(/usr/bin/date +%s) '
      BEGIN { FS = ":" }
      {
        if ( $3 != "" ) {
          if ( $3 > now ) {
            print $0;
          }
        }
      }' "${RESET_DB}" > "${file}"

    cp --no-preserve=mode,ownership "${file}" "${RESET_DB}"
    rm "${file}"
    UnlockResetMutex
  fi

  if [ "$(LockConfirmMutext)" == "LOCKED" ]; then
    umask 026
    local file=$(/usr/bin/mktemp /tmp/confirm.XXXXXX)

    /usr/bin/awk -v now=$(/usr/bin/date +%s) '
      BEGIN { FS = ":" }
      {
        if ( $4 != "" ) {
          if ( $4 > now ) {
            print $0
          }
        }
      }' "${CONFIRM_DB}" > "${file}"
    cp --no-preserve=mode,ownership "${file}" "${CONFIRM_DB}"
    rm "${file}"
    UnlockConfirmMutex
  fi
}


###################
# HTML Generation #
###################
function Header() {
  /usr/bin/cat <<EOF
<head>
  <title>${TITLE}</title>
  <style>
    fieldset {
      width: 500px;
    }
    legend {
      font-size: 20px;
    }
    label.field {
      text-align: right;
      width: 200px;
      float: left;
      font-weight: bold;
    }
    label.textbox-300 {
      width: 300px;
      float: left;
    }
    fieldset p {
      clear: bloth;
      padding: 5px;
    }
  </style>
</head>
EOF
}

# Cron mode, trigger cleanup of reset requests
CRON_MODE=0

# Print usage and quit
HELP_MODE=0

while [[ $# > 0 ]]
do
  case $1 in
    -c|--cron)
      CRON_MODE=1
      ;;
    -h|--help)
      HELP_MODE=1
      ;;
    *)
      ;;
  esac
  shift # next arg
done

if [ ${HELP_MODE} -eq 1 ]; then
  PrintUsage
elif [ ${CRON_MODE} -eq 1 ]; then
  CronMode
else
  /usr/bin/cat <<EOF
Content-type: text/html

<!DOCTYPE html>
<html>
$(Header)
$(Body)
</html>
EOF
fi

