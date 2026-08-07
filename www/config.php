<?php

/* Výchozí konfigurační hodnoty, které jsou zde jen pro informaci AI pro vývoj.
	Tento soubor se neinkluduje.
	Inkluduje se modifikovaný název takto:
	
	$CONFIG_SERVER_NAME=explode(':',$_SERVER['HTTP_HOST'])[0];
	require_once "config_{$CONFIG_SERVER_NAME}.php";
*/
$dbms="sqlsrv";
$dbserver = "název serveru"; // Jméno hádám 
$charset='UTF-8';
$dblogin="uživatel";
$dbpassword="zadej heslo";
$debugmode = 1;
$use_dbname="název databáze";

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