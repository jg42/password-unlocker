s!/bin/bash
#
# Password-Unlocker
#
# See README
#
# Built by Nathan Shobe

# Environment
PATH='/bin:/usr/bin'
WHOM=$(who -m | awk '{print $1}')
OS=$(uname)
HOST=$(hostname)
MAXAGE="30"
HEADER='Users to be modified'
FOOTER='Use the "u" option to update passwords'
ROOTHOME=$(echo ~root)
REPORT='/opt/unixadm/log/password-unlock.log'
OUTUSER='/opt/unixadm/log/passwordlocked.out'
ADMIN='nshobe'
RETURNADDY='unixadm@transcentra.com'
EXCLUDE='/opt/unixadm/etc/password-unlocker.conf'
EXCLUDEKEY='tIPPGRF4nh54MCZ76WMxqiNBCJUJSOL1zQPg7r7AopwVzsiljkT1qXXiNS8IERLR'
case "$OS" in
  SunOS)
    PASSOPS=' -s '
    HUMANS=':10:'
    ACCFILTER='LK\|NP\|UN'
    TODAY=$(($(truss date 2>&1 | grep ^time | awk -F"= " '{print $2}') / 86400))
    EXPIRE='passwd -f '
  ;;
  Linux)
    PASSOPS=' -S '
    HUMANS=':100:'
    ACCFILTER='L\|NP'
    TODAY=$(($(date --utc --date " " +%s)/86400))
    EXPIRE='passwd -e '
  ;;
  *)
    echo "Unknown OS, guessing it's kinda like linux."
    PASSOPS=' -S '
    HUMANS=':100:'
    ACCFILTER='L\|NP'
    TODAY=$(($(date --utc --date " " +%s)/86400))
    EXPIRE='passwd -e '
  ;;
esac

# Usage, tell people what to do
usage() {
  cat << EOF
#                     #
## Password Unlocker ##
#                     #

Usage:
    [ -l => List users without functional passwords (sends to stdout) ]
    [ -a => Generate admin email report ]
    [ -u => Update User Passwords ]
    [ -c => Specify a single user to password reset ]
    [ -v => Verbose: Enable CLI stdout logging ]
    [ -h => Usage/Help: This message ]

Warning: This must be run as root!"

EOF
  exit 1
}

# Validate required files exist and are writable
genFiles() {
  verbose "Checking to see if files already exist."
  if [ ! -f "$REPORT" ]; then
    verbose "Report file doesn't exist, attempting to create"
    touch $REPORT && chown root:root $REPORT && chmod 600 $REPORT
    if [ ! -f "$REPORT" ]; then
      printf "Report file creation failed, exiting"
      exit 1
    fi
  fi
  if [ ! -f "$OUTUSER" ]; then
    verbose "Userlist output file doesn't exist, attempting to create"
    touch $OUTUSER && chown root:root $OUTUSER && chmod 600 $OUTUSER
    if [ ! -f "$OUTUSER" ]; then
      printf "Userlist output file creation failed, exiting"
      exit 1
    fi
  fi
  if [ ! -f "$EXCLUDE" ]; then
    report "ERROR: Missing report file."
    echo "WARNING! Exclude list does not exist and is required, please see system administrator."
    exit 1
  elif grep -q $EXCLUDEKEY $EXCLUDE; then
    verbose "Exclude file exists, but ensuring permissions"
    chown root:root $EXCLUDE && chmod 600 $EXCLUDE
  else
    report "ERROR: Key missing from exclude file!"
    echo "Warning! Missing Key. Please see system administrator."
    exit 1
  fi
}
getUsers() {
  verbose "Finding human users"
  USERS=$(cat /etc/passwd | grep -v nologin | grep "$HUMANS" | awk -F':' '{print $1}')
}

## Check to see which users don't have usable passwords
checkUsers() {
  verbose "Checking for users with passwords older than 30 days"
  >$OUTUSER
  for i in $USERS; do
    verbose "Checking user $i"
    CHANGED=$(grep -e "^$i:" /etc/shadow | awk -F":" '{print $3}')
    AGE=$(echo $(( TODAY - CHANGED )))
    ISHUMAN=$(grep "^$i:" /etc/passwd | grep $HUMANS )
    INEXCLUDE=$(grep -v "^#\|^$" $EXCLUDE | grep "$i" $EXCLUDE )
    if [ -n "$ISHUMAN" ]; then
      verbose "$i seems to be in staff, GOOD!"
      if [ -z "$INEXCLUDE" ]; then
        verbose "$i seems to not be in exclude list, GOOD!"
        if [[ "$AGE" -gt 30 && "$AGE" -lt 1000 ]]; then
          echo $i >>$OUTUSER
          report "User $i has been found to have an old password of $AGE days old."
          verbose "User $i is past maximum age allowance"
        else
          verbose "User $i is not past maximum age allowance"
        fi
      else
        verbose "$i is in exclude list, skipping over"
      fi
    else
      verbose "$i is not in staff group, skipping"
    fi
    verbose "User $i has password of $AGE days old."
  done
}
# Initial Version, doesn't recognise expired, onlyed locked accounts.
#checkUsers() {
#  verbose "Checking for users without usable passwords"
#  >$OUTUSER
#  for i in $USERS; do
#    verbose "checking user $i"
#    passwd $PASSOPS $i | grep $ACCFILTER | awk '{print $1}' >>$OUTUSER
#    verbose "last entry was `tail -1 $OUTUSER`"
#  done
#}

## List users (handy for email and other reporting)
listUsers() {
  echo -e "$HEADER\n"
  while read i; do
    echo "$i"
  done<$OUTUSER
  echo -e "\n$FOOTER\n"
}

## Send the admin(s) a notice that something was changed
mailAdmin() {
  if [[ $OPTU -eq 1 ]] ; then
    FOOTER="Option u has been enacted and these users have had their accounts reset with new credentials mailed."
  else
    FOOTER="Option u was not used, this is information reporting only."
  fi
  HEADER="Password unlocker was run with option a enabled, which triggered this mail."
  ULIST=$(cat $OUTUSER)
  TO=$ADMIN
  SUBJECT="Accounts without functioning passwords"
  BODY=$(echo -e "
#
### Password Unlocker has been run
#
The following accounts are in a locked or otherwise unusable state.

$ULIST ")
  mailSend
  report "$ADMIN has been emailed a list of users."
}

## Notify the User that their password has been updated/modified
unlockUser() {
  SUBJECT="Auto-Updated Password(s) on $HOST"
  HEADER="This email was generated from $HOST"
  FOOTER="If you feel you've received this message by mistake, please forward your concerns to $RETURNADDY"
  while read i; do
    PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    BODY=$(echo -e "
#
### Your Password has been changed
#
Due to either account creation or lack of rotation within 30 days your password has been reset to:
$PASS

This means your new credentials are
Username: $i
Password: $PASS
On Server: $HOST

Please login and update password in a timely manner.\n\n")
    # Change following email to $i and uncomment passwd command for production change over.
    TO=nshobe
    mailSend
    #echo -e "$PASS\n$PASS" | passwd $i > /dev/null
    #$EXPIRE $i
    report "User $i password has been reset to $PASS on $HOST and has been emailed."
  done<$OUTUSER
}

## Specify a specific user to have password unlocked/reset for
resetUser() {
  verbose "Option c has been enabled, manually resetting password for $CHANGEUSER"
  report "!!!Manual user change has been enacted by $WHOM!!!"
  PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
  SUBJECT="Reset Password on $HOST"
  TO=$CHANGEUSER
  HEADER="This email was generated from $HOST"
  FOOTER="If you feel you've received this message by mistake, please forward your concerns to $RETURNADDY"
  BODY=$(echo -e "
#
### Your Password has been changed
#
Due to manual action your password has been changed. Your new credentials are:
Username: $CHANGEUSER
Password: $PASS
On Server: $HOST

Please login and update password in a timely manner.
")
  ISHUMAN=$(grep "^$CHANGEUSER\:" /etc/passwd | grep $HUMANS )
  INEXCLUDE=$(grep -v "^#\|^$" $EXCLUDE | grep "$CHANGEUSER" $EXCLUDE )
  if [ -z "$ISHUMAN" ]; then
    printf "$CHANGEUSER seems to not be in the staff group, exiting\n"
    exit 1
  elif [ -n "$INEXCLUDE" ]; then
    printf "$CHANGEUSER is listed as a user to not accept resets for, exiting.\n"
    exit 1
  else
    echo -e "$PASS\n$PASS" | passwd $CHANGEUSER > /dev/null
    $EXPIRE $CHANGEUSER
    mailSend
    report "!!!$CHANGEUSER was manually changed to $PASS by $WHOM!!!"
  fi
}

## To be used by other functions
mailSend() {
  mailx -r $RETURNADDY -s "$SUBJECT" $TO <<EOF
$HEADER
$BODY
$FOOTER
EOF
}

# If report option is switched, generate report file
report() {
  verbose "Report function called"
  printf "$(date +%F_%T) $* \n" >>$REPORT
}

# Extra noise when you want stout info
verbose() {
  if [[ $VERBOSE -eq 1 ]] ; then
    printf "$(date +%F_%T) $* \n"
  fi 
}


# Run with options
parseopts() {

  while getopts "lauc:vh" OPTION; do
    case "$OPTION" in
      l) OPTL=1                           ;;
      a) OPTA=1                           ;;
      u) OPTU=1                           ;;
      c) OPTC=1 && CHANGEUSER=$OPTARG     ;;
      v) VERBOSE=1                        ;;
      h) usage                            ;;
      *) usage                            ;;
    esac
  done
  if [ $# -eq 0 ]; then
    echo "No Options were provided."
    usage
  fi
}
main() {
  verbose "Verbose mode in enabled."
  report "Run initiated"
  genFiles
  getUsers
  checkUsers

## Run based on options
  if [[ $OPTL -eq 1 ]]; then
    verbose "Option l was used, so listUsers will output to stdout"
    listUsers
  fi
  if [[ $OPTA -eq 1 ]]; then
    verbose "Option a was used, so mail will be sent to the admin"
    mailAdmin
  fi
  if [[ $OPTU -eq 1 ]]; then
    verbose "Option u was used, so password will be updated and emailed to the user"
    unlockUser
  fi
  if [[ $OPTC -eq 1 ]]; then
    verbose "Option c was used, which allows a user to be specified. User $CHANGEUSER was specified."
    resetUser
  fi
}
if [ `whoami` != root ]; then
  echo "Error!!! Please run this as root or using the sudo command. Elevated rights are required."
  exit 1
else
parseopts $*
main
fi
