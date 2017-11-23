##############################################
# $Id: 37_echodevice.pm 13588 2017-10-20 00:00:00Z moises $$$
#
#  37_echodevice.pm
#
#  2017 Markus Moises < vorname at nachname . de >
#
#  This module provides basic remote control for the Amazon Echo
#
#  http://forum.fhem.de/index.php/topic,77458.0.html
#
#
##############################################################################
#
# define <name> echodevice <DeviceID> [DeviceType]
#
##############################################################################

package main;

use strict;
use warnings;
use Time::Local;
use Encode;
use URI::Escape;

use utf8;

##############################################################################

# dnd schedule: https://layla.amazon.de/api/dnd/schedule?deviceType=AB72C64C86AW2&deviceSerialNumber=ECHOSERIALNUMBER&_=1506940081763
# wifi settings: https://layla.amazon.de/api/device-wifi-details?deviceSerialNumber=ECHOSERIALNUMBER&deviceType=AB72C64C86AW2&_=1506940081768
# /api/todos?startTime=&endTime=&completed=&type=TASK&size=100&offset=-1&_=1507577670365
# /api/todos?startTime=&endTime=&completed=&type=SHOPPING_ITEM&size=100&offset=-1&_=1507577670355
# https://alexa-comms-mobile-service.amazon.com/homegroups/amzn1.comms.id.hg.amzn1~HOMEGROUP/devices?target=false


sub echodevice_Initialize($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{DefFn}        = "echodevice_Define";
  $hash->{UndefFn}      = "echodevice_Undefine";
  $hash->{NOTIFYDEV}    = "global";
  $hash->{NotifyFn}     = "echodevice_Notify";
  $hash->{GetFn}        = "echodevice_Get";
  $hash->{SetFn}        = "echodevice_Set";
  $hash->{AttrFn}       = "echodevice_Attr";
  $hash->{AttrList}     = "disable:0,1 ".
                          "IODev ".
                          "interval ".
                          "server ".
                          "cookie ".
                          $readingFnAttributes;
}

sub echodevice_Define($$$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my ($found, $dummy);

  return "syntax: define <name> echodevice <account> <password>" if(int(@a) != 4 );
  my $name = $hash->{NAME};

  $attr{$name}{server} = "layla.amazon.de" if( defined($attr{$name}) && !defined($attr{$name}{server}) );

  if($a[2] =~ /crypt/ || $a[2] =~ /@/ || $a[2] =~ /^\+/)
  {
    
    $hash->{model} = "ACCOUNT";
    
    my $user = $a[2];
    my $pass = $a[3];
    
    my $username = echodevice_encrypt($user);
    my $password = echodevice_encrypt($pass);
    $hash->{DEF} = "$username $password";

    $hash->{helper}{USER} = $username;
    $hash->{helper}{PASSWORD} = $password;
    $hash->{helper}{SERVER} = $attr{$name}{server};
    $hash->{helper}{SERVER} = "layla.amazon.de" if(!defined($hash->{helper}{SERVER}));

    $modules{$hash->{TYPE}}{defptr}{"account"} = $hash;

    if(defined($attr{$name}{cookie})) {
      $hash->{helper}{COOKIE} = $attr{$name}{cookie};
      $hash->{helper}{COOKIE} =~ s/Cookie: //g;
      $hash->{helper}{COOKIE} =~ /csrf=([-\w]+)[;\s]?(.*)?$/;
      $hash->{helper}{CSRF} = $1;
    }

    $hash->{STATE} = "INITIALIZED";
    echodevice_CheckAuth($hash);
    
  } else {
    $hash->{model} = $a[2];
    
    $hash->{helper}{DEVICETYPE} = $a[2];
    $hash->{helper}{SERIAL} = $a[3];

    $modules{$hash->{TYPE}}{defptr}{$a[3]} = $hash;

    my $account = $modules{$hash->{TYPE}}{defptr}{"account"};
    $hash->{IODev} = $account;
    $attr{$name}{IODev} = $account->{NAME} if( !defined($attr{$name}{IODev}) && $account);

  }

  return undef;
}

sub echodevice_Undefine($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  RemoveInternalTimer($hash);
  delete( $modules{$hash->{TYPE}}{defptr}{"ACCOUNT"} ) if($hash->{model} eq "ACCOUNT");
  delete( $modules{$hash->{TYPE}}{defptr}{"$hash->{helper}{SERIAL}"} ) if($hash->{model} ne "ACCOUNT");
  return undef;
}

sub echodevice_Notify($$) {
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));
  Log3 "echodevice", 2, "echodevice: notify reload";

  return undef;
}

sub echodevice_Get($@) {
  my ($hash, @a) = @_;
  shift @a;
  my $command = shift @a;
  my $parameter = join(' ',@a);
  my $name = $hash->{NAME};

  my $usage = "Unknown argument $command, choose one of update:noArg ";
  
  $usage .= "devices:noArg conversations:noArg reminders:noArg list:all,SHOPPING_ITEM,TASK " if($hash->{model} eq "ACCOUNT");
  $usage .= "tunein tracks:noArg " if($hash->{model} eq "ACCOUNT");
  
  $usage .= "settings:noArg " if($hash->{model} ne "ACCOUNT");
  return $usage if $command eq '?';


  if(IsDisabled($name)) {
    $hash->{STATE} = "disabled";
    readingsSingleUpdate($hash, "state", "disabled", 1);
    return "$name is disabled. Aborting...";
  }

  if($command eq "update") {
    echodevice_GetUpdate($hash);
  } elsif($command eq "settings") {
    echodevice_GetSettings($hash);
  } elsif($command eq "echodevice_") {
    return echodevice_GetNotifications($hash);
  } elsif($command eq "media") {
    echodevice_GetMedia($hash);
  } elsif ( $command eq "player" ) {
    echodevice_GetPlayer($hash);
  } elsif($command eq "wakeword") {
    echodevice_GetWakeword($hash);
  } elsif($command eq "bluetooth") {
    echodevice_GetBluetooth($hash);
  } elsif($command eq "history") {
    echodevice_GetHistory($hash);
  } elsif($command eq "cards") {
    echodevice_GetCards($hash);
  } elsif ( $command eq "list" ) {
    return echodevice_GetLists($hash) if($parameter eq "all" || !defined($parameter));
    return echodevice_GetList($hash,$parameter);
  } elsif($command eq "devices") {
    return echodevice_GetDevices($hash);
  } elsif($command eq "conversations") {
    return echodevice_GetConversations($hash);
  } elsif($command eq "tunein") {
    return echodevice_SearchTunein($hash,$parameter);
  } elsif($command eq "tracks") {
    my $return = echodevice_GetTracks($hash);
    return $return;
  }
  
  return undef;
}

sub echodevice_Set($@) {
  my ($hash, @a) = @_;
  shift @a;
  my $command = shift @a;
  my $parameter = join(' ',@a);
  my $name = $hash->{NAME};

  my $usage = 'Unknown argument $command, choose one of ';

  $usage .= 'login:noArg autocreate_devices:noArg listitem reminder ' if($hash->{model} eq "ACCOUNT");
  $usage .= 'textmessage ' if(defined($hash->{helper}{COMMSID}));

  $usage .= 'volume:slider,0,1,100 play:noArg pause:noArg next:noArg previous:noArg forward:noArg rewind:noArg shuffle:on,off repeat:one,off dnd:on,off volume_alarm:slider,0,1,100 ' if($hash->{model} ne "ACCOUNT");
  $usage .= 'tunein primeplaylist track ' if($hash->{model} ne "ACCOUNT");
  $usage .= 'bluetooth_connect:'.$hash->{helper}{bluetooth}.' bluetooth_disconnect:'.$hash->{helper}{bluetooth}.' ' if(defined($hash->{helper}{bluetooth}));

  return $usage if $command eq '?';


  if(IsDisabled($name)) {
    $hash->{STATE} = "disabled";
    readingsSingleUpdate($hash, "state", "disabled", 1);
    return "$name is disabled. Aborting...";
  }
  
  return echodevice_GetDevices($hash,0,1) if($command eq "autocreate_devices");
  return echodevice_Login($hash) if($command eq "login");

  if($command =~ /bluetooth_/){
    my @parameters = split("/",$parameter);
    echodevice_ConnectBluetooth($hash,$command,$parameters[0]);
  } elsif($command eq "dnd"){
    echodevice_SetDnd($hash,"dnd",$parameter);
  } elsif ( $command eq "listitem" ) {
    my @parameters = split(" ",$parameter);
    my $listtype = shift @parameters;
    $parameter = join(" ",@parameters);
    echodevice_SetList( $hash, $listtype, $parameter );
  } elsif ( $command eq "reminder" ) {
    my @parameters = split(" ",$parameter);
    my $timestamp = shift @parameters;
    $parameter = join(" ",@parameters);
    echodevice_SetReminder( $hash, $timestamp, $parameter );
  } elsif ( $command eq "volume_alarm" ) {
    echodevice_SetAlarmVolume($hash,$parameter);
  } elsif($command eq "tunein"){
    my @parameters = split(" ",$parameter);
    $parameter = shift @parameters;
    echodevice_SetTunein($hash,$parameter);
  } elsif($command eq "primeplaylist"){
    my @parameters = split(" ",$parameter);
    $parameter = shift @parameters;
    echodevice_SetPrimeMusic($hash,$parameter);
  } elsif($command eq "pandora"){
    my @parameters = split(" ",$parameter);
    $parameter = shift @parameters;
    echodevice_SetPandora($hash,$parameter);
  } elsif($command eq "track"){
    my @parameters = split(" ",$parameter);
    $parameter = shift @parameters;
    echodevice_SetTrack($hash,$parameter);
  } elsif($command eq "textmessage"){
    my @parameters = split(" ",$parameter);
    my $conversationid = shift @parameters;
    $parameter = join(" ",@parameters);
    echodevice_SendTextMessage($hash,$conversationid,$parameter);
  } else {
    echodevice_SendMessage($hash,$command,$parameter);
  }

  return undef;
}

#########################

sub echodevice_SendMessage($$$) {
  my ($hash,$command,$value) = @_;
  my $name = $hash->{NAME};

  my $json = encode_json( {} );

  if($command eq "volume") {
    $json = encode_json( {  type => 'VolumeLevelCommand',
                            volumeLevel => 0+$value,
                            contentFocusClientId => undef } );
  } elsif ($command eq "play") {
    $json = encode_json( {  type => 'PlayCommand',
                            contentFocusClientId => undef } );
  } elsif ($command eq "pause") {
    $json = encode_json( {  type => 'PauseCommand',
                            contentFocusClientId => undef } );
  } elsif ($command eq "next") {
    $json = encode_json( {  type => 'NextCommand',
                            contentFocusClientId => undef } );
  } elsif ($command eq "previous") {
    $json = encode_json( {  type => 'PreviousCommand',
                            contentFocusClientId => undef } );
  } elsif ($command eq "forward") {
    $json = encode_json( {  type => 'ForwardCommand',
                            contentFocusClientId => undef } );
  } elsif ($command eq "rewind") {
    $json = encode_json( {  type => 'RewindCommand',
                            contentFocusClientId => undef } );
  } elsif ($command eq "shuffle") {
    $json = encode_json( {  type => 'ShuffleCommand',
                            shuffle => ($value eq "on"?"true":"false"),
                            contentFocusClientId => undef } );
  } elsif ($command eq "repeat") {
    $json = encode_json( {  type => 'RepeatCommand',
                            repeat => ($value eq "one"?"true":"false"),
                            contentFocusClientId => undef } );
  } else {
    Log3 ($name, 1, "$name: Unknown command $command $value");
    return undef;
  }

  $json =~s/\"true\"/true/g;
  $json =~s/\"false\"/false/g;

  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/np/command?deviceSerialNumber=".$hash->{helper}{SERIAL}."&deviceType=".$hash->{helper}{DEVICETYPE};
  Log3 ($name, 3, "Setting URL ".echodevice_anonymize($hash, $url)."\n$json");
  
  HttpUtils_NonblockingGet({
    url => $url,
    method => "POST",
    header => "Cookie: ".$hash->{IODev}->{helper}{COOKIE}."\r\ncsrf: ".$hash->{IODev}->{helper}{CSRF}."\r\nContent-Type: application/x-www-form-urlencoded; charset=UTF-8",#\r\nReferer: https://alexa.amazon.de/spa/index.html',
    timeout => 10,
    data => $json,
    hash => $hash,
    type => 'command',
    callback => \&echodevice_Parse,
  });

  return undef;
}

sub echodevice_Parse($$$) {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $msgtype = $param->{type};
  
  Log3 $name, 5, "$name: ".Dumper(echodevice_anonymize($hash, $data));

  if($err){
    readingsSingleUpdate($hash, "state", "disconnected", 1);
    Log3 $name, 2, "$name: connection error $msgtype $err";
    return undef;
  }

  if($err){
    readingsSingleUpdate($hash, "state", "error", 1);
    Log3 $name, 2, "$name: connection error $msgtype $err";
    return undef;
  }
  
  if($data =~ /No routes found/){
    Log3 $name, 2, "$name: No routes found";
    readingsSingleUpdate($hash, "state", "timeout", 1);
    return undef;
  }
  if($data =~ /UnknownOperationException/){
    Log3 $name, 2, "$name: Unknown Operation";
    readingsSingleUpdate($hash, "state", "unknown", 1);
    return undef;
  }

  if($msgtype eq "null"){
    return undef;
  } elsif($msgtype eq "setting") {
    InternalTimer( gettimeofday() + 3, "echodevice_GetSettings", $hash, 0);
    return undef;
  } elsif($msgtype eq "command") {
    InternalTimer( gettimeofday() + 3, "echodevice_GetPlayer", $hash, 0);
    return undef;
  } elsif($msgtype eq "listitem") {
    InternalTimer( gettimeofday() + 3, "echodevice_GetLists", $hash, 0);
    return undef;
  } elsif($msgtype eq "reminderitem") {
    InternalTimer( gettimeofday() + 3, "echodevice_GetReminders", $hash, 0);
    return undef;
  }

  
  my $json = eval { JSON->new->utf8(0)->decode($data) };
  if($@)
  {
    if($data =~ /doctype html/){
      RemoveInternalTimer($hash);
      Log3 $name, 2, "$name: Invalid cookie";
      readingsSingleUpdate($hash, "state", "unauthorized", 1);
      $hash->{STATE} = "COOKIE ERROR";
      InternalTimer( gettimeofday() + 10, "echodevice_CheckAuth", $hash, 0);
      return undef;
    }
    readingsSingleUpdate($hash, "state", "error", 1);
    Log3 $name, 1, "$name: json evaluation error ".$@."\n".Dumper(echodevice_anonymize($hash, $data));
    return undef;
  }

  readingsSingleUpdate($hash, "state", "connected", 1);

  if($msgtype eq "activities") {
    my $timestamp = int(time - ReadingsAge($name,'voice',time));
    return undef if(!defined($json->{activities}));
    return undef if(ref($json->{activities}) ne "ARRAY");
    foreach my $card (reverse(@{$json->{activities}})) {
      #next if($card->{cardType} ne "TextCard");
      #next if($card->{sourceDevice}{serialNumber} ne $hash->{helper}{SERIAL});
      next if($timestamp >= int($card->{creationTimestamp}/1000));
      next if($card->{description} !~ /firstUtteranceId/);
      
      my $textjson = $card->{description};
      $textjson =~ s/\\//g;
      my $cardjson = eval { JSON->new->utf8(0)->decode($textjson) };
      next if($@);
      next if(!defined($cardjson->{summary}));

      readingsBeginUpdate($hash);
      $hash->{".updateTimestamp"} = FmtDateTime(int($card->{creationTimestamp}/1000));
      readingsBulkUpdate( $hash, "voice", $cardjson->{summary}, 1 );
      $hash->{CHANGETIME}[0] = FmtDateTime(int($card->{creationTimestamp}/1000));
      readingsEndUpdate($hash,1);
    }
    return undef;
  } elsif($msgtype eq "cards") {
    my $timestamp = int(time - ReadingsAge($name,'voice',time));
    return undef if(!defined($json->{cards}));
    return undef if(ref($json->{cards}) ne "ARRAY");
    foreach my $card (reverse(@{$json->{cards}})) {
      #next if($card->{cardType} ne "TextCard");
      #next if($card->{sourceDevice}{serialNumber} ne $hash->{helper}{SERIAL});
      next if($timestamp >= int($card->{creationTimestamp}/1000));
      next if(!defined($card->{playbackAudioAction}{mainText}));
      readingsBeginUpdate($hash);
      $hash->{".updateTimestamp"} = FmtDateTime(int($card->{creationTimestamp}/1000));
      readingsBulkUpdate( $hash, "voice", $card->{playbackAudioAction}{mainText}, 1 );
      $hash->{CHANGETIME}[0] = FmtDateTime(int($card->{creationTimestamp}/1000));
      readingsEndUpdate($hash,1);
    }
    return undef;
  } elsif($msgtype eq "media") {

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "volume", $json->{volume}, 1) if(defined($json->{volume}));
    readingsBulkUpdate($hash, "mute", $json->{muted}?"on":"off", 1) if(defined($json->{muted}));
    readingsBulkUpdate($hash, "playStatus", ($json->{currentState} eq "IDLE" ? "stopped": lc($json->{currentState})), 1) if(defined($json->{currentState}));
    readingsBulkUpdate($hash, "progress", $json->{progressSeconds}, 1) if(defined($json->{progressSeconds}));
    readingsBulkUpdate($hash, "shuffle", $json->{shuffling}?"on":"off", 1) if(defined($json->{shuffling}));
    readingsBulkUpdate($hash, "repeat", $json->{looping}?"one":"off", 1) if(defined($json->{looping}));
    
    # if(defined($json->{currentState}) && $json->{currentState} eq "idle") {
    #   readingsBulkUpdate($hash, "currentTitle ", "-", 1);
    #   readingsBulkUpdate($hash, "currentArtist ", "-", 1);
    #   readingsBulkUpdate($hash, "currentAlbum ", "-", 1);
    #   readingsBulkUpdate($hash, "currentArtwork", "-", 1);
    # }
    readingsEndUpdate($hash,1);
    return undef;
  } elsif($msgtype eq "player") {
    return undef if(!defined($json->{playerInfo}));
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "playStatus", ($json->{playerInfo}{state} eq "IDLE" ? "stopped": lc($json->{playerInfo}{state})), 1) if(defined($json->{playerInfo}{state}));
    if(defined($json->{playerInfo}{infoText})) {
      readingsBulkUpdate($hash, "currentTitle ", $json->{playerInfo}{infoText}{title}, 1) if(defined($json->{playerInfo}{infoText}{title}));
      readingsBulkUpdate($hash, "currentArtist ", $json->{playerInfo}{infoText}{subText1}, 1) if(defined($json->{playerInfo}{infoText}{subText1}));
      readingsBulkUpdate($hash, "currentAlbum ", $json->{playerInfo}{infoText}{subText2}, 1) if(defined($json->{playerInfo}{infoText}{subText2}));
      readingsBulkUpdate($hash, "currentTitle ", "-", 1) if(!defined($json->{playerInfo}{infoText}{title}));
      readingsBulkUpdate($hash, "currentArtist ", "-", 1) if(!defined($json->{playerInfo}{infoText}{subText1}));
      readingsBulkUpdate($hash, "currentAlbum ", "-", 1) if(!defined($json->{playerInfo}{infoText}{subText2}));
    }
    if(defined($json->{playerInfo}{provider})) {
      readingsBulkUpdate($hash, "channel", $json->{playerInfo}{provider}{providerName}, 1) if(defined($json->{playerInfo}{provider}{providerName}));
      readingsBulkUpdate($hash, "channel", $json->{playerInfo}{provider}{providerName}, 1) if(!defined($json->{playerInfo}{provider}{providerName}));
    } else {
      readingsBulkUpdate($hash, "channel", "-", 1);
    }
    if(defined($json->{playerInfo}{mainArt})) {
      readingsBulkUpdate($hash, "currentArtwork", $json->{playerInfo}{mainArt}{url}, 1) if(defined($json->{playerInfo}{mainArt}{url}));
      readingsBulkUpdate($hash, "currentArtwork", "-", 1) if(!defined($json->{playerInfo}{mainArt}{url}));
    }
    if(defined($json->{playerInfo}{progress})) {
      readingsBulkUpdate($hash, "progress", $json->{playerInfo}{progress}{mediaProgress}, 1) if(defined($json->{playerInfo}{progress}{mediaProgress}));
      readingsBulkUpdate($hash, "progress", 0, 1) if(!defined($json->{playerInfo}{progress}{mediaProgress}));
    }
    if(defined($json->{playerInfo}{volume})) {
      readingsBulkUpdate($hash, "volume", $json->{playerInfo}{volume}{volume}, 1) if(defined($json->{playerInfo}{volume}{volume}));
      readingsBulkUpdate($hash, "mute", $json->{playerInfo}{volume}{muted}?"on":"off", 1) if(defined($json->{playerInfo}{volume}{muted}));
    }
        
    if(!defined($json->{playerInfo}{state})){
      #readingsBulkUpdate($hash, "state", "IDLE", 1);
      InternalTimer( gettimeofday() + 1, "echodevice_GetMedia", $hash, 0);
    } elsif($json->{playerInfo}{state} eq "PLAYING"){
      InternalTimer( gettimeofday() + 1, "echodevice_GetMedia", $hash, 0);
    } elsif($json->{playerInfo}{state} eq "IDLE") {
      readingsBulkUpdate($hash, "currentArtwork", "-", 1);
      readingsBulkUpdate($hash, "currentTitle ", "-", 1);
      readingsBulkUpdate($hash, "currentArtist ", "-", 1);
      readingsBulkUpdate($hash, "currentAlbum ", "-", 1);
    }

    readingsEndUpdate($hash,1);
    return undef;
  } elsif ( $msgtype eq "list" ) {
    my $listtype = $param->{listtype};
    my @listitems;
                
    foreach my $item ( @{ $json->{values} } ) {
      next if ($item->{complete});
      $item->{text} =~ s/,/;/g;
      push @listitems, $item->{text};
    }
    readingsSingleUpdate( $hash, "list_".$listtype, join(", ", @listitems),  1 );
    return undef;
  } elsif($msgtype eq "notifications") {
    
    foreach my $notification (sort { $a->{alarmTime} <=> $b->{alarmTime} } @{$json->{notifications}}) {
      $notification->{reminderLabel} = "ALARM" if(!defined($notification->{reminderLabel}));
      next if($notification->{deviceSerialNumber} ne $hash->{helper}{SERIAL});
      next if($notification->{status} eq "OFF");
      Log3 $name, 1, "$name: notify ".$notification->{alarmTime}." ".$notification->{reminderLabel};
    }
    return undef;
  } elsif($msgtype eq "account") {
    my $i=1;
    foreach my $account (@{$json}) {
      $hash->{helper}{COMMSID} = $account->{commsId} if(defined($account->{commsId}));
      $hash->{helper}{DIRECTID} = $account->{directedId} if(defined($account->{directedId}));
      last if(1<$i++);
    }
    echodevice_GetHomeGroup($hash) if(defined($hash->{helper}{COMMSID}));
  } elsif($msgtype eq "homegroup") {
    $hash->{helper}{HOMEGROUP} = $json->{homeGroupId} if(defined($json->{homeGroupId}));
    $hash->{helper}{SIPS} = $json->{aor} if(defined($json->{aor}));
  } elsif($msgtype eq "bluetoothstate") {
    my @btstrings;
    foreach my $device (@{$json->{bluetoothStates}}) {
      next if($device->{deviceSerialNumber} ne $hash->{helper}{SERIAL});
      foreach my $btdevice (@{$device->{pairedDeviceList}}) {
        next if(!defined($btdevice->{friendlyName}));
        $btdevice->{address} =~ s/:/-/g;
        $btdevice->{friendlyName} =~ s/ /_/g;
        $btdevice->{friendlyName} =~ s/,/./g;
        my $btstring .= $btdevice->{address}."/".$btdevice->{friendlyName};
        push @btstrings, $btstring;
      }
    }
    $hash->{helper}{bluetooth} = join(",", @btstrings);
    $hash->{helper}{bluetooth} = "-" if(!defined($hash->{helper}{bluetooth}));
    return undef;
  } elsif($msgtype eq "dnd") {
    foreach my $device (@{$json->{doNotDisturbDeviceStatusList}}) {
      next if($device->{deviceSerialNumber} ne $hash->{helper}{SERIAL});
      readingsSingleUpdate($hash, "dnd", $device->{enabled}?"on":"off", 1) if(defined($device->{enabled}));
    }
  } elsif($msgtype eq "alarmvolume") {
    readingsSingleUpdate($hash, "volume_alarm", $json->{volumeLevel}, 1) if(defined($json->{volumeLevel}));
  } elsif($msgtype eq "dndset") {
    readingsSingleUpdate($hash, "dnd", $json->{enabled}?"on":"off", 1) if(defined($json->{enabled}));
  } elsif($msgtype eq "wakeword") {
    foreach my $device (@{$json->{wakeWords}}) {
      next if($device->{deviceSerialNumber} ne $hash->{helper}{SERIAL});
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "active", $device->{active}?"true":"false", 1) if(defined($device->{active}));
      readingsBulkUpdate($hash, "wakeword", $device->{wakeWord}, 1) if(defined($device->{wakeWord}));
      readingsBulkUpdate($hash, "midfield", $device->{midFieldState}, 1) if(defined($device->{midFieldState}));
      readingsEndUpdate($hash,1);
    }
  } else {
    Log3 $name, 3, "$name: json for unknown message type $msgtype\n".Dumper(echodevice_anonymize($hash, $json));
  }
  
  return undef;
}

##########################

sub echodevice_GetUpdate($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  echodevice_GetPlayer($hash) if($hash->{model} ne "ACCOUNT");;
  echodevice_GetHistory($hash) if($hash->{model} eq "ACCOUNT");;
  echodevice_GetLists($hash) if($hash->{model} eq "ACCOUNT");;

  my $nextupdate = time()+int(AttrVal($name,"interval",300));
  RemoveInternalTimer($hash, "echodevice_GetUpdate");
  InternalTimer($nextupdate, "echodevice_GetUpdate", $hash, 1);

  return undef;
}

sub echodevice_GetSettings($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  echodevice_GetBluetooth($hash);
  echodevice_GetWakeword($hash);
  echodevice_GetDnd($hash);
  echodevice_GetAlarmVolume($hash);
  
  my $nextupdate = time()+7200;
  RemoveInternalTimer($hash, "echodevice_GetSettings");
  InternalTimer($nextupdate, "echodevice_GetSettings", $hash, 1);

  return undef;
}

sub echodevice_GetReminders($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  echodevice_GetNotifications($hash,1);

  return undef;
}

##########################

sub echodevice_GetHistory($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $url="https://".$hash->{helper}{SERVER}."/api/activities?startTime=&size=50&offset=1&_=".int(time);
  Log3 ($name, 3, "Getting history URL ".echodevice_anonymize($hash, $url));

  HttpUtils_NonblockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{helper}{COOKIE},
    noshutdown => 1,
    hash => $hash,
    type => 'activities',
    callback => \&echodevice_Parse,
  });
}

sub echodevice_GetCards($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $url="https://".$hash->{helper}{SERVER}."/api/cards?limit=10&beforeCreationTime=".int(time)."000&_=".int(time);
  Log3 ($name, 3, "Getting cards URL ".echodevice_anonymize($hash, $url));

  HttpUtils_NonblockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{helper}{COOKIE},
    noshutdown => 1,
    hash => $hash,
    type => 'cards',
    callback => \&echodevice_Parse,
  });
}

sub echodevice_GetMedia($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/media/state?deviceSerialNumber=".$hash->{helper}{SERIAL}."&deviceType=".$hash->{helper}{DEVICETYPE}."&screenWidth=1392&_=".int(time);
  Log3 ($name, 3, "Getting state URL ".echodevice_anonymize($hash, $url));

  HttpUtils_NonblockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{IODev}->{helper}{COOKIE},
    noshutdown => 1,
    hash => $hash,
    type => 'media',
    callback => \&echodevice_Parse,
  });
}

sub echodevice_GetPlayer($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/np/player?deviceSerialNumber=".$hash->{helper}{SERIAL}."&deviceType=".$hash->{helper}{DEVICETYPE}."&screenWidth=1392&_=".int(time);
  Log3 ($name, 3, "Getting player URL ".echodevice_anonymize($hash, $url));

  HttpUtils_NonblockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{IODev}->{helper}{COOKIE},
    noshutdown => 1,
    hash => $hash,
    type => 'player',
    callback => \&echodevice_Parse,
  });
}


sub echodevice_GetLists($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  echodevice_GetList($hash,'TASK');
  echodevice_GetList($hash,'SHOPPING_ITEM');
  
  return undef;
}

sub echodevice_GetList($$) {
  my ($hash,$listtype) = @_;
  my $name = $hash->{NAME};

  my $url = "https://".$hash->{helper}{SERVER}."/api/todos?size=100&startTime=&endTime=&completed=false&type=".$listtype."&deviceSerialNumber=&deviceType=&_=".int(time);
  Log3( $name, 3, "Getting list URL ".echodevice_anonymize( $hash, $url ) );

  HttpUtils_NonblockingGet({
    url        => $url,
    header     => 'Cookie: '.$hash->{helper}{COOKIE},
    noshutdown => 1,
    hash       => $hash,
    type       => 'list',
    listtype   => $listtype,
    callback   => \&echodevice_Parse,
  });
}

sub echodevice_GetWakeword($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/wake-word?_=".int(time);
  Log3 ($name, 3, "Getting settings URL ".echodevice_anonymize($hash, $url));

  HttpUtils_NonblockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{IODev}->{helper}{COOKIE},
    noshutdown => 1,
    hash => $hash,
    type => 'wakeword',
    callback => \&echodevice_Parse,
  });
}

sub echodevice_GetNotifications($;$) {
  my ($hash, $nonblocking) = @_;
  my $name = $hash->{NAME};

  my $url="https://".$hash->{helper}{SERVER}."/api/notifications?cached=true&_=".int(time);
  
  if($nonblocking) {
    Log3 ($name, 3, "Getting notifications nonblocking ".echodevice_anonymize($hash, $url));

    HttpUtils_NonblockingGet({
      url => $url,
      header => 'Cookie: '.$hash->{helper}{COOKIE},
      noshutdown => 1,
      hash => $hash,
      type => 'notifications',
      callback => \&echodevice_Parse,
    });
    return undef;
  }

  Log3 ($name, 3, "Getting notifications blocking ".echodevice_anonymize($hash, $url));
  my($err,$data) = HttpUtils_BlockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{helper}{COOKIE},
    noshutdown => 1,
    hash => $hash,
  });

  my $json = eval { JSON->new->utf8(0)->decode($data) };
  my $return = "Notifications:\n\nTime             \tType          \tDescription\n\n";

  return $return if(!defined($json->{notifications}));
  return $return if(ref($json->{notifications}) ne "ARRAY");

  foreach my $notification (sort { $a->{alarmTime} <=> $b->{alarmTime} } @{$json->{notifications}}) {
    next if($notification->{deviceSerialNumber} ne $hash->{helper}{SERIAL});
    #next if($notification->{status} eq "OFF");
    $notification->{reminderLabel} = $notification->{sound}{displayName} if(!defined($notification->{reminderLabel}));
    $return .= FmtDateTime($notification->{alarmTime}/1000).(($notification->{status} eq "OFF")?" - ":" ! ")." \t".$notification->{type}."    \t".$notification->{reminderLabel}."\n";
  }
  return $return;
}

sub echodevice_GetDnd($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/dnd/device-status-list?_=".int(time);
  Log3 ($name, 3, "Getting dnd URL ".echodevice_anonymize($hash, $url));

  HttpUtils_NonblockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{IODev}->{helper}{COOKIE},
    noshutdown => 1,
    hash => $hash,
    type => 'dnd',
    callback => \&echodevice_Parse,
  });
}

sub echodevice_GetAlarmVolume($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/device-notification-state/".$hash->{helper}{DEVICETYPE}."/".$hash->{helper}{VERSION}."/".$hash->{helper}{SERIAL}."?_=".int(time);
  Log3 ($name, 3, "Getting alarm volume URL ".echodevice_anonymize($hash, $url));

  HttpUtils_NonblockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{IODev}->{helper}{COOKIE},
    noshutdown => 1,
    hash => $hash,
    type => 'alarmvolume',
    callback => \&echodevice_Parse,
  });
}

sub echodevice_GetBluetooth($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/bluetooth?cached=true&_=".int(time);
  Log3 ($name, 3, "Getting bluetooth URL ".echodevice_anonymize($hash, $url));

  HttpUtils_NonblockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{IODev}->{helper}{COOKIE},
    noshutdown => 1,
    hash => $hash,
    type => 'bluetoothstate',
    callback => \&echodevice_Parse,
  });
}

sub echodevice_GetDevices($;$$) {
  my ($hash, $nonblocking, $autocreate) = @_;
  my $name = $hash->{NAME};

  my $url="https://".$hash->{helper}{SERVER}."/api/devices-v2/device?cached=true&_=".int(time);
  
  if($nonblocking) {
    Log3 ($name, 3, "Getting devices URL nonblocking ".echodevice_anonymize($hash, $url));

    HttpUtils_NonblockingGet({
      url => $url,
      header => 'Cookie: '.$hash->{helper}{COOKIE},
      noshutdown => 1,
      hash => $hash,
      type => 'devices',
      callback => \&echodevice_ParseDevices,
    });
    return undef;
  }
  
  Log3 ($name, 3, "Getting devices URL blocking ".echodevice_anonymize($hash, $url));

  my($err,$data) = HttpUtils_BlockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{helper}{COOKIE},
    noshutdown => 1,
    hash => $hash,
  });
  my $json = eval { JSON->new->utf8(0)->decode($data) };
  
  my $autocreated = 0;
  my $return = "Devices:\n\nSerial           \tFamily   \tDevicetype \tName\n\n";
  return $return if(!defined($json->{devices}));
  return $return if(ref($json->{devices}) ne "ARRAY");

  foreach my $device (@{$json->{devices}}) {
    next if($device->{deviceFamily} eq "UNKNOWN");
    next if($device->{deviceFamily} eq "FIRE_TV");
    next if($device->{deviceFamily} =~ /AMAZON/);
    $return .= $device->{serialNumber};
    $return .= " \t";
    $return .= $device->{deviceFamily};
    $return .= " \t";
    $return .= $device->{deviceType};
    $return .= " \t";
    $return .= $device->{accountName};
    $return .= "\n";
    if($autocreate && $device->{deviceFamily} eq "ECHO") {
      if( defined($modules{$hash->{TYPE}}{defptr}{"$device->{serialNumber}"}) ) {
        Log3 $name, 4, "$name: device '$device->{serialNumber}' already defined";
        next;
      }

      my $devname = "ECHO_".$device->{serialNumber};
      my $define= "$devname echodevice ".$device->{deviceType}." ".$device->{serialNumber};

      Log3 $name, 3, "$name: create new device '$devname' for echo device";
      my $cmdret= CommandDefine(undef,$define);
      if($cmdret) {
        Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for serial '$device->{serialNumber}': $cmdret";
      } else {
        $cmdret= CommandAttr(undef,"$devname alias ".encode_utf8($device->{accountName})) if( defined($device->{accountName}) );
        $cmdret= CommandAttr(undef,"$devname IODev $name");
        $autocreated++;
      }
      
      $hash->{helper}{VERSION} = $device->{softwareVersion};
      $hash->{helper}{CUSTOMER} = $device->{deviceOwnerCustomerId};

    } elsif($device->{deviceFamily} eq "ECHO") {
      if( defined($modules{$hash->{TYPE}}{defptr}{"$device->{serialNumber}"}) ) {
        my $devicehash = $modules{$hash->{TYPE}}{defptr}{"$device->{serialNumber}"};

        #$hash->{helper}{VERSION} = $device->{softwareVersion};
        #$hash->{helper}{CUSTOMER} = $device->{deviceOwnerCustomerId};
        #$hash->{model} = $device->{deviceType};

      }
    }
  }
  echodevice_ParseDevices($hash,$data);

  $return .= "\n\n$autocreated devices created" if($autocreated > 0);
  return $return;
}

sub echodevice_ParseDevices($$) {
  my ($hash, $data) = @_;
  my $name = $hash->{NAME};

  my $json = eval { JSON->new->utf8(0)->decode($data) };
  return undef if(!defined($json->{devices}));
  return undef if(ref($json->{devices}) ne "ARRAY");

  foreach my $device (@{$json->{devices}}) {
    next if($device->{deviceFamily} ne "ECHO");
    my $devicehash = $modules{$hash->{TYPE}}{defptr}{"$device->{serialNumber}"};
    next if( !defined($devicehash) );
    
    $devicehash->{model} = $device->{deviceType};
    readingsSingleUpdate($devicehash, "presence", ($device->{online}?"present":"absent"), 1);
    readingsSingleUpdate($devicehash, "state", "absent", 1) if(!$device->{online});
    readingsSingleUpdate($devicehash, "version", $device->{softwareVersion}, 1);

    $hash->{helper}{SERIAL} = $device->{serialNumber};
    $hash->{helper}{DEVICETYPE} = $device->{deviceType};
    $devicehash->{helper}{SERIAL} = $device->{serialNumber};
    $devicehash->{helper}{DEVICETYPE} = $device->{deviceType};
    $devicehash->{helper}{NAME} = $device->{accountName};
    $devicehash->{helper}{FAMILY} = $device->{deviceFamily};
    $devicehash->{helper}{VERSION} = $device->{softwareVersion};
    $devicehash->{helper}{CUSTOMER} = $device->{deviceOwnerCustomerId};

  }
  
  return undef;
}

##########################

sub echodevice_SetList($$$) {
    my ( $hash, $listtype, $value ) = @_;
    my $name   = $hash->{NAME};

    my $json = JSON->new->utf8(1)->encode( { 'type' => $listtype,
                              'text' => decode_utf8($value),
                              'createdDate' => int(time),
                              'complete' => "false",
                              'deleted' => "false" } );

    $json =~ s/\"true\"/true/g;
    $json =~ s/\"false\"/false/g;

    my $url = "https://".$hash->{helper}{SERVER}."/api/todos?deviceSerialNumber=".$hash->{helper}{SERIAL}."&deviceType=".$hash->{helper}{DEVICETYPE};
    Log3( $name, 3, "Setting listitem URL ".echodevice_anonymize($hash,$url)."\n$json");

    HttpUtils_NonblockingGet(
        {
            url    => $url,
            method => "POST",
            header => "Cookie: ".$hash->{helper}{COOKIE}."\r\ncsrf: ".$hash->{helper}{CSRF}."\r\nContent-Type: application/x-www-form-urlencoded; charset=UTF-8",#\r\nReferer: https://alexa.amazon.de/spa/index.html',
            timeout  => 10,
            data     => $json,
            hash     => $hash,
            type     => 'listitem',
            listtype => $listtype,
            callback => \&echodevice_Parse,
        }
    );
}

sub echodevice_SetReminder($$$) {
    my ( $hash, $timestamp, $value ) = @_;
    my $name   = $hash->{NAME};

    $timestamp = int($timestamp + time()) if(int($timestamp) < 1000000000);
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($timestamp);
    
    my $json = JSON->new->utf8(1)->encode( { "type" => "Reminder",
                              "status" => "ON",
                              "alarmTime" => $timestamp*1000,
                              "originalTime" => sprintf("%02d",$hour).":".sprintf("%02d",$min).":".sprintf("%02d",$sec).".000",
                              "originalDate" => sprintf("%04d",$year+1900)."-".sprintf("%02d",$mon+1)."-".sprintf("%02d",$mday),
                              "deviceSerialNumber" => $hash->{helper}{SERIAL},
                              "deviceType" => $hash->{helper}{DEVICETYPE},
                              "reminderLabel" => decode_utf8($value),
                              "isSaveInFlight" => "true",
                              "id" => "createReminder",
                              'createdDate' => int(time)*1000 } );

    $json =~ s/\"true\"/true/g;
    $json =~ s/\"false\"/false/g;

    my $url = "https://".$hash->{helper}{SERVER}."/api/notifications/createReminder";
    Log3( $name, 3, "Setting listitem URL ".echodevice_anonymize($hash,$url)."\n$json");

    HttpUtils_NonblockingGet(
        {
            url    => $url,
            method => "PUT",
            header => "Cookie: ".$hash->{helper}{COOKIE}."\r\ncsrf: ".$hash->{helper}{CSRF}."\r\nContent-Type: application/json; charset=UTF-8",#\r\nReferer: https://alexa.amazon.de/spa/index.html',
            timeout  => 10,
            data     => $json,
            hash     => $hash,
            type     => 'reminderitem',
            callback => \&echodevice_Parse,
        }
    );
}

sub echodevice_SendTextMessage($$$) {
  my ($hash,$conversationid,$parameter) = @_;
  my $name = $hash->{NAME};

  Log3 ($name, 2, "Sending text ".$parameter);

  #"time": "2017-10-16T13:52:22.151Z",

  my $json = JSON->new->pretty(1)->utf8(1)->encode([{ "type" => "message/text",
                             "payload" => {"text" => decode_utf8($parameter)} }] );

  $json =~s/\//\\\//;

  my $url="https://alexa-comms-mobile-service.amazon.com/users/".$hash->{helper}{COMMSID}."/conversations/".$conversationid."/messages";
  Log3 ($name, 3, "Setting text URL ".echodevice_anonymize($hash, $url)."\n$json");

  HttpUtils_NonblockingGet({
    url => $url,
    method => "POST",
    header => "Cookie: ".$hash->{helper}{COOKIE}."\r\nContent-Type: application/json; charset=UTF-8",#\r\nReferer: https://alexa.amazon.de/spa/index.html',
    timeout => 10,
    data => $json,
    hash => $hash,
    type => 'textmessage',
    callback => \&echodevice_Parse,
  });
  return undef;
}

sub echodevice_ConnectBluetooth($$$) {
  my ($hash,$command,$value) = @_;
  my $name = $hash->{NAME};

  $value =~ s/-/:/g;
  
  my $json = encode_json( { bluetoothDeviceAddress => $value } );
  
  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/bluetooth/pair-sink/".$hash->{helper}{DEVICETYPE}."/".$hash->{helper}{SERIAL};

  if($command =~ /disconnect/) {
    $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/bluetooth/disconnect-sink/".$hash->{helper}{DEVICETYPE}."/".$hash->{helper}{SERIAL};
  } 
  Log3 ($name, 5, "Setting bluetooth URL $command ".echodevice_anonymize($hash, $url)."\n$json");
  
  HttpUtils_NonblockingGet({
    url => $url,
    method => "POST",
    header => "Cookie: ".$hash->{IODev}->{helper}{COOKIE}."\r\ncsrf: ".$hash->{IODev}->{helper}{CSRF}."\r\nContent-Type: application/json",#\r\nReferer: https://alexa.amazon.de/spa/index.html',
    timeout => 10,
    data => $json,
    hash => $hash,
    type => 'null',
    callback => \&echodevice_Parse,
  });

  return undef;
}

sub echodevice_SetDnd($$$) {
  my ($hash,$command,$value) = @_;
  my $name = $hash->{NAME};

  my $json = encode_json( { deviceSerialNumber => $hash->{helper}{SERIAL},
                            deviceType => $hash->{helper}{DEVICETYPE},
                            enabled => ($value eq "on")?"true":"false" } );
  
  $json =~s/\"true\"/true/g;
  $json =~s/\"false\"/false/g;

  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/dnd/status";

  Log3 ($name, 3, "Setting DND $command ".echodevice_anonymize($hash, $url)."\n".echodevice_anonymize($hash, $json));
  
  HttpUtils_NonblockingGet({
    url => $url,
    method => "PUT",
    header => "Cookie: ".$hash->{IODev}->{helper}{COOKIE}."\r\ncsrf: ".$hash->{IODev}->{helper}{CSRF}."\r\nContent-Type: application/json",#\r\nReferer: https://alexa.amazon.de/spa/index.html',
    timeout => 10,
    data => $json,
    hash => $hash,
    type => 'dndset',
    callback => \&echodevice_Parse,
  });

  return undef;
}

sub echodevice_SetAlarmVolume($$) {
  my ($hash,$parameter) = @_;
  my $name = $hash->{NAME};

  my $json = encode_json( { deviceSerialNumber => $hash->{helper}{SERIAL},
                            deviceType => $hash->{helper}{DEVICETYPE},
                            softwareVersion => $hash->{helper}{VERSION},
                            volumeLevel => $parameter+0 } );

  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/device-notification-state/".$hash->{helper}{DEVICETYPE}."/".$hash->{helper}{VERSION}."/".$hash->{helper}{SERIAL}."?_=".int(time);
  Log3 ($name, 3, "Setting alarm volume URL ".echodevice_anonymize($hash, $url)."\n".echodevice_anonymize($hash, $json));

  HttpUtils_NonblockingGet({
    url => $url,
    method => "PUT",
    header => "Cookie: ".$hash->{IODev}->{helper}{COOKIE}."\r\ncsrf: ".$hash->{IODev}->{helper}{CSRF}."\r\nContent-Type: application/json",#\r\nReferer: https://alexa.amazon.de/spa/index.html',
    timeout => 10,
    data => $json,
    hash => $hash,
    type => 'setting',
    callback => \&echodevice_Parse,
  });
}

###########################

sub echodevice_GetTracks($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $url="https://".$hash->{helper}{SERVER}."/api/cloudplayer/playlists/IMPORTED-V0-OBJECTID?deviceSerialNumber=".$hash->{helper}{SERIAL}."&deviceType=".$hash->{helper}{DEVICETYPE}."&size=50&offset=&mediaOwnerCustomerId=".$hash->{helper}{CUSTOMER}."&_=".int(time);
  Log3 ($name, 3, "Getting tracks URL ".echodevice_anonymize($hash, $url));

  my($err,$data) = HttpUtils_BlockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{helper}{COOKIE},
    noshutdown => 1,
    hash => $hash,
  });
  my $json = eval { JSON->new->utf8(0)->decode($data) };
  #return Dumper($json);

  my $return = "Tracks:\n\nID                                   \tTitle\n\n";
  return $return if(!defined($json->{playlist}{entryList}));
  return $return if(ref($json->{playlist}{entryList}) ne "ARRAY");

  foreach my $track (@{$json->{playlist}{entryList}}) {
    #next if($device->{deviceFamily} eq "UNKNOWN");
    $return .= $track->{trackId};
    $return .= " \t";
    if(defined($track->{metadata}{title})){
      $return .= $track->{metadata}{title};
    } else {
      $return .= "unknown title";
    }
    $return .= "\n";
  }
  return $return;
}

sub echodevice_SearchTunein($$) {
  my ($hash,$parameter) = @_;
  my $name = $hash->{NAME};

  
  my $url="https://".$hash->{helper}{SERVER}."/api/tunein/search?query=".uri_escape_utf8(decode_utf8($parameter))."&mediaOwnerCustomerId=".$hash->{helper}{CUSTOMER}."&_=".int(time);
  Log3 ($name, 3, "Getting tunein search URL ".echodevice_anonymize($hash, $url));

  my($err,$data) = HttpUtils_BlockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{helper}{COOKIE},
    noshutdown => 1,
    hash => $hash,
  });
  my $json = eval { JSON->new->utf8(0)->decode($data) };
  
  my $return = "Results:\n\nID          \tName\n\n";
  return $return if(!defined($json->{browseList}));
  return $return if(ref($json->{browseList}) ne "ARRAY");

  foreach my $result (@{$json->{browseList}}) {
    next if(!$result->{available});
    next if($result->{contentType} ne "station");
    $return .= $result->{id};
    $return .= "     \t";
    $return .= $result->{name};
    $return .= "\n";
  }
  
  return $return;
}

sub echodevice_SetTrack($$) {
  my ($hash,$parameter) = @_;
  my $name = $hash->{NAME};

  my $json = encode_json( { trackId => $parameter,
                            playQueuePrime => "false"} );

  $json =~s/\"true\"/true/g;
  $json =~s/\"false\"/false/g;

  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/cloudplayer/queue-and-play?deviceSerialNumber=".$hash->{helper}{SERIAL}."&deviceType=".$hash->{helper}{DEVICETYPE}."&mediaOwnerCustomerId=".$hash->{IODev}->{helper}{CUSTOMER};
  Log3 ($name, 3, "Setting station URL ".echodevice_anonymize($hash, $url)."\n$json");

  HttpUtils_NonblockingGet({
    url => $url,
    method => "POST",
    header => "Cookie: ".$hash->{IODev}->{helper}{COOKIE}."\r\ncsrf: ".$hash->{IODev}->{helper}{CSRF}."\r\nContent-Type: application/json",#\r\nReferer: https://alexa.amazon.de/spa/index.html',
    timeout => 10,
    data => $json,
    hash => $hash,
    type => 'command',
    callback => \&echodevice_Parse,
  });
  return undef;
}

sub echodevice_SetTunein($$) {
  my ($hash,$parameter) = @_;
  my $name = $hash->{NAME};

  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/tunein/queue-and-play?deviceSerialNumber=".$hash->{helper}{SERIAL}."&deviceType=".$hash->{helper}{DEVICETYPE}."&guideId=".$parameter."&contentType=station&callSign=&mediaOwnerCustomerId=".$hash->{IODev}->{helper}{CUSTOMER};
  Log3 ($name, 3, "Setting station URL ".echodevice_anonymize($hash, $url));

  HttpUtils_NonblockingGet({
    url => $url,
    method => "POST",
    header => "Cookie: ".$hash->{IODev}->{helper}{COOKIE}."\r\ncsrf: ".$hash->{IODev}->{helper}{CSRF}."\r\nContent-Type: application/json",#\r\nReferer: https://alexa.amazon.de/spa/index.html',
    timeout => 10,
    hash => $hash,
    type => 'command',
    callback => \&echodevice_Parse,
  });
  return undef;
}

sub echodevice_SetPrimeMusic($$) {
  my ($hash,$parameter) = @_;
  my $name = $hash->{NAME};

  my $json = encode_json( {  asin => $parameter } );

  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/prime/prime-playlist-queue-and-play?deviceSerialNumber=".$hash->{helper}{SERIAL}."&deviceType=".$hash->{helper}{DEVICETYPE}."&mediaOwnerCustomerId=".$hash->{IODev}->{helper}{CUSTOMER};
  Log3 ($name, 3, "Setting station URL ".echodevice_anonymize($hash, $url)."\n$json");

  HttpUtils_NonblockingGet({
    url => $url,
    method => "POST",
    header => "Cookie: ".$hash->{IODev}->{helper}{COOKIE}."\r\ncsrf: ".$hash->{IODev}->{helper}{CSRF}."\r\nContent-Type: application/json",#\r\nReferer: https://alexa.amazon.de/spa/index.html',
    timeout => 10,
    data => $json,
    hash => $hash,
    type => 'command',
    callback => \&echodevice_Parse,
  });
  return undef;
}

sub echodevice_SetPandora($$) {
  my ($hash,$parameter) = @_;
  my $name = $hash->{NAME};

  my $json = encode_json( { stationToken => $parameter,
                            createStation => "false" } );

  $json =~s/\"true\"/true/g;
  $json =~s/\"false\"/false/g;

  my $url="https://".$hash->{IODev}->{helper}{SERVER}."/api/amber/queue-and-play?deviceSerialNumber=".$hash->{helper}{SERIAL}."&deviceType=".$hash->{helper}{DEVICETYPE}."&mediaOwnerCustomerId=".$hash->{IODev}->{helper}{CUSTOMER};
  Log3 ($name, 3, "Setting station URL ".echodevice_anonymize($hash, $url)."\n$json");

  HttpUtils_NonblockingGet({
    url => $url,
    method => "POST",
    header => "Cookie: ".$hash->{IODev}->{helper}{COOKIE}."\r\ncsrf: ".$hash->{IODev}->{helper}{CSRF}."\r\nContent-Type: application/json",#\r\nReferer: https://alexa.amazon.de/spa/index.html',
    timeout => 10,
    data => $json,
    hash => $hash,
    type => 'pandora',
    callback => \&echodevice_Parse,
  });
  return undef;
}

##########################

sub echodevice_CheckAuth($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return undef if($hash->{model} ne "ACCOUNT");
  echodevice_Login($hash) if(!defined($hash->{helper}{COOKIE}));
  
  my $url="https://".$hash->{helper}{SERVER}."/api/bootstrap";
  Log3 ($name, 3, "Getting auth URL ".echodevice_anonymize($hash, $url));

  HttpUtils_NonblockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{helper}{COOKIE},
    noshutdown => 1,
    hash => $hash,
    callback => \&echodevice_ParseAuth,
  });
  return undef;
}

sub echodevice_ParseAuth($$$) {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if($err){
    readingsSingleUpdate($hash, "state", "connection error", 1);
    echodevice_Login($hash) if(!defined($attr{$name}{cookie}));
    Log3 $name, 2, "$name: connection error $err";
    return undef;
  }
  
  if($data =~ /cookie is missing/) {
    readingsSingleUpdate($hash, "state", "disconnected", 1);
    echodevice_Login($hash) if(!defined($attr{$name}{cookie}));
    return undef;
  }
  
  my $json = eval { JSON->new->utf8(0)->decode($data) };
  if($@)
  {
    readingsSingleUpdate($hash, "state", "disconnected", 1);
    echodevice_Login($hash) if(!defined($attr{$name}{cookie}));
    return undef;
  }
  
  Log3 $name, 2, "$name: $data";

  if($json->{authentication}{authenticated}){
    readingsSingleUpdate($hash, "state", "connected", 1);
    $hash->{helper}{CUSTOMER} = $json->{authentication}{customerId};
  } elsif($json->{authentication}) {
    readingsSingleUpdate($hash, "state", "disconnected", 1);
    echodevice_Login($hash) if(!defined($attr{$name}{cookie}));
  }
  return undef;
}

sub echodevice_Login($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};


  #
  # get first cookie and write redirection target into referer
  #
  #curl -s -D "${TMP}.alexa.header" -c ${COOKIE} -b ${COOKIE} -A "Mozilla/5.0" -H "Accept-Language: de,en" --compressed -H "DNT: 1" -H "Connection: keep-alive" -H "Upgrade-Insecure-Requests: 1" -L\
  # https://alexa.amazon.de | grep "hidden" | sed 's/hidden/\n/g' | grep "value=\"" | sed -E 's/^.*name="([^"]+)".*value="([^"]+)".*/\1=\2\&/g' > "${TMP}.alexa.postdata"

  my $param;
  $param->{url} = "https://".$hash->{helper}{SERVER}."/";
  $param->{method} = "GET";
  $param->{ignoreredirects} = 1;
  $param->{header} = "User-Agent: Mozilla/5.0\r\nAccept-Language: de,en\r\nDNT: 1\r\nConnection: keep-alive\r\nUpgrade-Insecure-Requests: 1";

  my($err,$data) = HttpUtils_BlockingGet($param);


  my $location = $param->{httpheader};
  $location =~ /Location: (.+?)\s/;
  $location = $1;

  #Log3 $name, 5, "Referer: ".$location;


  my $param2;
  $param2->{url} = "https://".$hash->{helper}{SERVER}."/";
  $param2->{method} = "GET";
  $param2->{header} = "User-Agent: Mozilla/5.0\r\nAccept-Language: de,en\r\nDNT: 1\r\nConnection: keep-alive\r\nUpgrade-Insecure-Requests: 1";

  my($err2,$data2) = HttpUtils_BlockingGet($param2);

  my (@cookies) = ($param2->{httpheader} =~ /Set-Cookie: (.*)\s/g);
  
  my $cookiestring = "";
  foreach my $cookie (@cookies){
    next if($cookie =~ /1970/);
    $cookie =~ /(.*) (expires=|Version=|Domain)/;
    $cookiestring .= $1." ";
  } 

  #Log3 $name, 5, "Cookie: ".$cookiestring;

  my @formparams = ('appActionToken', 'appAction', 'showRmrMe', 'openid.return_to', 'prevRID', 'openid.identity', 'openid.assoc_handle', 'openid.mode', 'failedSignInCount', 'openid.claimed_id', 'pageId', 'openid.ns', 'showPasswordChecked');
  my $postdata = "";
  foreach my $formparam (@formparams){
    my $value = ($data2 =~ /type="hidden" name="$formparam" value="(.*)"/);
    $value = $1;
    $value =~ /^(.*?)"/;
    #Log3 $name, 5, "Post: ".$formparam."=".$1;
    $postdata .= $formparam."=".$1."&"
  } 

  #$formdata = $1;
  #$data =~ s/\n/ /g;
  #my (@posts) = ($data =~ /name=\"(.*)\" value=\"(.*)\"/g);

  my $param3;
  $param3->{url} = "https://www.amazon.de/ap/signin";
  $param3->{method} = "POST";
  $param3->{data} = $postdata;
  $param3->{header} = "User-Agent: Mozilla/5.0\r\nAccept-Language: de,en\r\nDNT: 1\r\nConnection: keep-alive\r\nUpgrade-Insecure-Requests: 1\r\nReferer: $location\r\nCookie: $cookiestring";

  my($err3,$data3) = HttpUtils_BlockingGet($param3);

  $postdata = "";
  foreach my $formparam (@formparams){
    my $value = ($data3 =~ /type="hidden" name="$formparam" value="(.*)"/);
    $value = $1;
    $value =~ /^(.*?)"/;
    #Log3 $name, 5, "Post: ".$formparam."=".$1;
    $postdata .= $formparam."=".$1."&"
  } 

  my (@cookies2) = ($param3->{httpheader} =~ /Set-Cookie: (.*)\s/g);
  
  my $sessionid = "";
  my $cookiestring2 = "";
  foreach my $cookie (@cookies2){
    next if($cookie =~ /1970/);
    $cookie =~ /(.*) (expires|Version|Domain)/;
    $cookiestring2 .= $1." ";
    $cookiestring2 =~ /ubid-acbde=(.*);/;
    $sessionid = $1;
  } 

  $cookiestring .= $cookiestring2;

  #
  # login empty to generate sessiion
  #
  #curl -s -c ${COOKIE} -b ${COOKIE} -A "Mozilla/5.0" -H "Accept-Language: de,en" --compressed -H "DNT: 1" -H "Connection: keep-alive" -H "Upgrade-Insecure-Requests: 1" -L\
  # -H "$(grep 'Location: ' ${TMP}.alexa.header | sed 's/Location: /Referer: /')" -d "@${TMP}.alexa.postdata" https://www.amazon.de/ap/signin | grep "hidden" | sed 's/hidden/\n/g' | grep "value=\"" | sed -E 's/^.*name="([^"]+)".*value="([^"]+)".*/\1=\2\&/g' > "${TMP}.alexa.postdata2"


  my $param4;
  $param4->{url} = "https://www.amazon.de/ap/signin";
  $param4->{method} = "POST";
  $param4->{ignoreredirects} = 1;
  $param4->{data} = $postdata."email=".uri_escape(echodevice_decrypt($hash->{helper}{USER}))."&password=".uri_escape(echodevice_decrypt($hash->{helper}{PASSWORD}));
  $param4->{header} = "User-Agent: Mozilla/5.0\r\nAccept-Language: de,en\r\nDNT: 1\r\nConnection: keep-alive\r\nUpgrade-Insecure-Requests: 1\r\nReferer: https://www.amazon.de/ap/signin/$sessionid\r\nCookie: $cookiestring";

  my($err4,$data4) = HttpUtils_BlockingGet($param4);

  my (@cookies3) = ($param4->{httpheader} =~ /Set-Cookie: (.*)\s/g);
  
  my $cookiestring3 = "";
  foreach my $cookie (@cookies3){
    #Log3 $name, 5, "Cookie: ".$cookie;
    next if($cookie =~ /1970/);
    $cookie =~ s/Version=1; //g;
    $cookie =~ /(.*) (expires|Version|Domain)/;
    $cookie = $1;
    next if($cookiestring =~ /$cookie/);
    $cookiestring3 .= $cookie." ";
  } 
  $cookiestring .= $cookiestring3;

  #Log3 $name, 5, "Cookie: ".$cookiestring;

  # login with filled out form
  #  !!! referer now contains session in URL
  #
  #curl -s -c ${COOKIE} -b ${COOKIE} -A "Mozilla/5.0" -H "Accept-Language: de,en" --compressed -H "DNT: 1" -H "Connection: keep-alive" -H "Upgrade-Insecure-Requests: 1" -L\
  # -H "Referer: https://www.amazon.de/ap/signin/$(awk '$0 ~/.amazon.de.*session-id[\s\t]/ {print $7}' ${COOKIE})" --data-urlencode "email=${EMAIL}" --data-urlencode "password=${PASSWORD}" -d "@${TMP}.alexa.postdata2" https://www.amazon.de/ap/signin > /dev/null

  my $param5;
  $param5->{url} = "https://".$hash->{helper}{SERVER}."/api/bootstrap?version=0&_=".int(time);
  $param5->{header} = "User-Agent: Mozilla/5.0\r\nAccept-Language: de,en\r\nDNT: 1\r\nConnection: keep-alive\r\nUpgrade-Insecure-Requests: 1\r\nReferer: https://".$hash->{helper}{SERVER}."/spa/index.html\r\nOrigin: https://".$hash->{helper}{SERVER}."\r\nCookie: $cookiestring";

  my($err5,$data5) = HttpUtils_BlockingGet($param5);

  my (@cookies4) = ($param5->{httpheader} =~ /Set-Cookie: (.*)\s/g);
  
  my $cookiestring4 = "";
  foreach my $cookie (@cookies4){
    #Log3 $name, 5, "Cookie: ".$cookie;
    next if($cookie =~ /1970/);
    $cookie =~ s/Version=1; //g;
    $cookie =~ /(.*) (expires|Version)/;
    $cookie = $1;
    next if($cookiestring =~ /$cookie/);
    $cookiestring4 .= $cookie." ";
  } 
  $cookiestring .= $cookiestring4;

  if($cookiestring =~ /doctype html/) {
    RemoveInternalTimer($hash);
    Log3 $name, 2, "$name: Login failed";
    readingsSingleUpdate($hash, "state", "unauthorized", 1);
    $hash->{STATE} = "LOGIN ERROR";
    return undef;
  }
  
  Log3 $name, 5, "Cookie: ".$cookiestring;
  #Log3 $name, 1, "Header: ".$param5->{httpheader};

  #
  # get CSRF
  #
  #curl -s -c ${COOKIE} -b ${COOKIE} -A "Mozilla/5.0" --compressed -H "DNT: 1" -H "Connection: keep-alive" -L\
  # -H "Referer: https://alexa.amazon.de/spa/index.html" -H "Origin: https://alexa.amazon.de"\
  # https://layla.amazon.de/api/language > /dev/null

  $hash->{helper}{COOKIE} = $cookiestring;
  $hash->{helper}{COOKIE} =~ /csrf=([-\w]+)[;\s]?(.*)?$/ if(defined($hash->{helper}{COOKIE}));
  $hash->{helper}{CSRF} = $1  if(defined($hash->{helper}{COOKIE}));

  if(defined($hash->{helper}{COOKIE}))
  {
    echodevice_GetDevices($hash,1,0);
    echodevice_GetAccount($hash) ;
  }
  
  return undef;
}

sub echodevice_GetAccount($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};


  my $url="https://alexa-comms-mobile-service.amazon.com/accounts";
  Log3 ($name, 3, "Getting accounts URL $url");

  HttpUtils_NonblockingGet({
    url => $url,
    method => "GET",
    header => "Cookie: ".$hash->{helper}{COOKIE}."\r\nContent-Type: application/json",
    timeout => 10,
    hash => $hash,
    type => 'account',
    callback => \&echodevice_Parse,
  });
  return undef;
}

sub echodevice_GetHomeGroup($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $url="https://alexa-comms-mobile-service.amazon.com/users/".$hash->{helper}{COMMSID}."/identities?includeUserName=true";
  Log3 ($name, 3, "Getting homegroup URL ".echodevice_anonymize($hash, $url));

  HttpUtils_NonblockingGet({
    url => $url,
    method => "GET",
    header => "Cookie: ".$hash->{helper}{COOKIE}."\r\nContent-Type: application/json",
    timeout => 10,
    hash => $hash,
    type => 'homegroup',
    callback => \&echodevice_Parse,
  });
  return undef;
}

sub echodevice_GetConversations($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $url="https://alexa-comms-mobile-service.amazon.com/users/".$hash->{helper}{COMMSID}."/conversations?latest=true&includeHomegroup=true&unread=false&modifiedSinceDate=1970-01-01T00:00:00.000Z&includeUserName=true";
  Log3 ($name, 3, "Getting conversations URL ".echodevice_anonymize($hash, $url));

  my($err,$data) = HttpUtils_BlockingGet({
    url => $url,
    header => 'Cookie: '.$hash->{helper}{COOKIE}."\r\nContent-Type: application/json",
    noshutdown => 1,
    hash => $hash,
  });
  my $json = eval { JSON->new->utf8(0)->decode($data) };
  #return Dumper($json);
  
  my $return = "Conversations:\n\nID                                                                  \tDate                          \tMessage\n\n";
  return $return if(!defined($json->{conversations}));
  return $return if(ref($json->{conversations}) ne "ARRAY");
  foreach my $conversation (@{$json->{conversations}}) {
    #next if($device->{deviceFamily} eq "UNKNOWN");
    $return .= $conversation->{conversationId};
    $return .= " \t";
    if(defined($conversation->{lastMessage}{payload}{text})){
      $return .= $conversation->{lastMessage}{time};
      $return .= " \t";
      $return .= $conversation->{lastMessage}{payload}{text};
    } else {
      $return .= "no previous messages";
    }
    $return .= "\n";
  }
  return $return;
}

##########################

sub echodevice_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  if( $attrName eq "cookie" ) {
    my $hash = $defs{$name};
    if( $cmd eq "set" ) {
      $attrVal =~ s/Cookie: //g;
      $hash->{helper}{COOKIE} = $attrVal;
      $hash->{helper}{COOKIE} =~ /csrf=([-\w]+)[;\s]?(.*)?$/;
      $hash->{helper}{CSRF} = $1;
      $hash->{STATE} = "INITIALIZED";
    }
  }
  if( $attrName eq "server" ) {
    my $hash = $defs{$name};
    if( $cmd eq "set" ) {
      $hash->{helper}{SERVER} = $attrVal;
    }
  }
  $attr{$name}{$attrName} = $attrVal;
  return;  
}

sub echodevice_anonymize($$) {
  my ($hash, $string) = @_;
  my $s1 = $hash->{helper}{SERIAL};
  my $s2 = $hash->{helper}{CUSTOMER};
  my $s3 = $hash->{helper}{HOMEGROUP};
  my $s4 = $hash->{helper}{COMMSID};
  my $s5;
  $s5 = echodevice_decrypt($hash->{helper}{USER}) if(defined($hash->{helper}{USER}));
  $s5 = echodevice_decrypt($hash->{IODev}->{helper}{USER}) if(defined($hash->{IODev}->{helper}{USER}));;
  $s1 = "SERIAL" if(!defined($s1));
  $s2 = "CUSTOMER" if(!defined($s2));
  $s3 = "HOMEGROUP" if(!defined($s3));
  $s4 = "COMMSID" if(!defined($s4));
  $s5 = "USER" if(!defined($s5));
  $string =~ s/$s1/SERIAL/g;
  $string =~ s/$s2/CUSTOMER/g;
  $string =~ s/$s3/HOMEGROUP/g;
  $string =~ s/$s4/COMMSID/g;
  $string =~ s/$s5/USER/g;
  return $string;
}

sub echodevice_encrypt($) {
  my ($decoded) = @_;
  my $key = getUniqueId();
  my $encoded;

  return $decoded if( $decoded =~ /crypt:/ );

  for my $char (split //, $decoded) {
    my $encode = chop($key);
    $encoded .= sprintf("%.2x",ord($char)^ord($encode));
    $key = $encode.$key;
  }

  return 'crypt:'.$encoded;
}

sub echodevice_decrypt($) {
  my ($encoded) = @_;
  my $key = getUniqueId();
  my $decoded;

  return $encoded if( $encoded !~ /crypt:/ );
  
  $encoded = $1 if( $encoded =~ /crypt:(.*)/ );

  for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
    my $decode = chop($key);
    $decoded .= chr(ord($char)^ord($decode));
    $key = $decode.$key;
  }

  return $decoded;
}


1;

=pod
=item device
=item summary Amazon Echo remote control
=begin html

<a name="echodevice"></a>
<h3>echodevice</h3>
<ul>
  Basic remote control for Amazon Echo devices
  <br/><br/>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; echodevice &lt;DeviceID&gt; [DeviceType]</code>
    <br>
    Example: <code>define echo echodevice AABBCC0011223344 AB72C64C86AW2</code>
    <br>
    Example: <code>define echo echodevice</code>
    <br>&nbsp;
    <li><code>Note:</code>
      <br>
      If defined without DeviceID and DeviceType, the module will try to auto-detect the first Echo device on startup
    </li><br>
  </ul>
  <br>
  <b>Set</b>
   <ul>
      <li><code>...</code>
      <br>
      ...
      </li><br>
  </ul>
  <b>Get</b>
   <ul>
      <li><code>update</code>
      <br>
      Manually reload data (player/media, cards)
      </li><br>
      <li><code>settings</code>
      <br>
      Manually reload setings (dnd, bluetooth, wakeword)
      </li><br>
      <li><code>devices</code>
      <br>
      Displays a list of Amazon devices connected to your account
      </li><br>
      <li><code>list TASK/SHOPPING_ITEM</code>
      <br>
      Retrieves the todo / shopping list
      </li><br>
  </ul>
  <br>
  <b>Readings</b>
   <ul>
      <li><code>...</code>
      <br>
      ...
      </li><br>
  </ul>
  <br>
   <b>Attributes</b>
   <ul>
      <li><code>interval</code>
         <br>
         Poll interval in seconds (300)
      </li><br>
      <li><code>cookie</code>
         <br>
         Amazon access cookie, has to be entered for the module to work
      </li><br>
      <li><code>server</code>
         <br>
         Amazon server used for controlling the Echo
      </li><br>
  </ul>
</ul>

=end html
=cut
