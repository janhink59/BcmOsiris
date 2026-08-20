<?php

/* Soubor s výchozími konfiguračními hodnotami. Inkluduje se na každé stránce aplikace.
	Vzápětí se inkluduje ostrý konfigurační soubor, který výchozí hodnoty může přepsat.
	$CONFIG_SERVER_NAME=explode(':',$_SERVER['HTTP_HOST'])[0];
	require_once "config_{$CONFIG_SERVER_NAME}.php";

	Nakonec se provede připojení k databázi a další nastavení
*/
$dbms="sqlsrv";
$dbserver = "název serveru"; // Jméno hádám 
$charset=$sqlsrv_charset='UTF-8';
$dblogin="uživatel";
$dbpassword="zadej heslo";
$debugmode = 1;
$use_dbname="název databáze";
$CONFIGURATION_NAME="Výchozí konfigurace";

// Nastavení odesílání e-mailů (SMTP)
$smtp_server = 'sandbox.smtp.mailtrap.io';
$smtp_port = 2525;
$smtp_user = 'tvoje_mailtrap_jmeno';
$smtp_password = 'tvoje_mailtrap_heslo';
$smtp_sender = 'noreply@tvojedomena.cz';
$smtp_sender_name = 'RAMSES ISMS';

// Ochrana proti spamu při testování. 
// Pokud je vyplněno, všechny e-maily jdou na tuto adresu. Pro produkci nech prázdné ('').
$smtp_forward = 'jan.hink@tvojedomena.cz';
$http_allowed = 0;

// =========================================================================
// INICIALIZACE SESSION A ZÍSKÁNÍ SESSION_ID PRO P_INIT_WWWSESSION
// =========================================================================
if (session_status() === PHP_SESSION_NONE) {
	session_start();
}
// Globální proměnná $SID, kterou následně využívá initsession() v RamsesLib.php
$SID = session_id();

// 1. Načtení konfigurace a knihoven, specifické pro aktuální instanci serveru

$CONFIG_SERVER_NAME=explode(':',$_SERVER['HTTP_HOST'])[0];
require_once "config_{$CONFIG_SERVER_NAME}.php";

// Načtení společných knihoven
require_once 'RamsesLib.php';
require_once 'send_global_mail.php';

// Připojení k databázi a nastavení options

$first_command="while @@trancount>0 rollback
set xact_abort on
set ansi_padding on
set ansi_warnings on
set ansi_nulls on
set concat_null_yields_null on
set arithabort on set ansi_null_dflt_on on
set implicit_transactions off";

$dbconnection=@sqlsrv_connect($dbserver
	,array('UID'=>$dblogin
	,'PWD'=>$dbpassword
	,'APP'=>'Ramses'
	,'CharacterSet'=>$sqlsrv_charset
	//,"Authentication" => "SqlPassword"
	,"TrustServerCertificate" => true // Klíčové pro PHP 8.x
	,"MultipleActiveResultSets" => false)
	);
if (!$dbconnection)  fatal_error("Connect to SQL server failed, (SQLSRV configuration for $CONFIG_SERVER_NAME: $CONFIGURATION_NAME)","Server=$dbserver as $dblogin");
if(@$use_dbname) sqlrun("use $use_dbname");
//sqlsrv_query($dbconnection,"set transaction isolation level read uncommitted set concat_null_yields_null on set arithabort on set nocount on set ansi_null_dflt_on on");
sqlrun($first_command);