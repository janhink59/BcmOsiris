<?php
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

/**
 * Globální funkce pro odesílání e-mailů pomocí knihovny PHPMailer.
 * Využívá konfiguraci z config.php (např. v rámci GRC/ISMS systému Ramses).
 * Nahrazuje dřívější nativní socketové řešení pro spolehlivější zpracování hlaviček,
 * příloh a okrajových případů (dle RFC) v multi-tenantní architektuře.
 *
 * @param string $to Cílová e-mailová adresa (bude přepsána, pokud je aktivní $smtp_forward)
 * @param string $subject Předmět e-mailu
 * @param string $body Tělo e-mailu (HTML nebo prostý text)
 * @param bool $is_html Určuje, zda je tělo e-mailu ve formátu HTML
 * @return bool True v případě úspěchu, jinak false
 */
function send_global_mail(string $to, string $subject, string $body, bool $is_html = true): bool {
	// Import globálních konfiguračních proměnných z config.php
	global $smtp_server, $smtp_port, $smtp_user, $smtp_password, $smtp_sender, $smtp_sender_name, $smtp_forward, $debugmode;

	// Inicializace PHPMaileru s povolenými výjimkami (předání true)
	$mail = new PHPMailer(true);

	try {
		// Konfigurace SMTP serveru
		$mail->isSMTP();
		$mail->Host       = $smtp_server;
		
		// Autentizace – pro služby jako Mailtrap se heslem myslí přístupový token
		$mail->SMTPAuth   = !empty($smtp_user);
		$mail->Username   = $smtp_user;
		$mail->Password   = $smtp_password;
		
		// Nastavení šifrování na základě definovaného portu (465 = SMTPS, jinak STARTTLS)
		$mail->SMTPSecure = ($smtp_port == 465) ? PHPMailer::ENCRYPTION_SMTPS : PHPMailer::ENCRYPTION_STARTTLS;
		$mail->Port       = $smtp_port;
		
		// Zajištění korektního kódování češtiny v předmětu i těle zprávy
		$mail->CharSet    = 'UTF-8';

		// Definice odesílatele (Fallback jména, pokud by $smtp_sender_name nebylo definováno)
		$mail->setFrom($smtp_sender, $smtp_sender_name ?? 'RAMSES ISMS');

		// Ochrana pro testovací prostředí a vývoj
		// Pokud je definován $smtp_forward, zpráva se neodešle klientovi, ale na tuto adresu.
		if (!empty($smtp_forward)) {
			$forward_info = "Původní adresát = " . $to;
			
			// Vizuální oddělení testovací informace od původního obsahu zprávy
			if ($is_html) {
				$body = "<div style=\"background:#fff3cd; color:#856404; padding:10px; margin-bottom:15px; border:1px solid #ffeeba;\"><strong>TEST FORWARD:</strong> " . htmlspecialchars($forward_info) . "</div>" . $body;
			} else {
				$body = "TEST FORWARD: " . $forward_info . "\r\n\r\n" . $body;
			}
			
			$mail->addAddress($smtp_forward);
		} else {
			// Standardní odeslání pro produkci
			$mail->addAddress($to);
		}

		// Kompletace zprávy
		$mail->isHTML($is_html);
		$mail->Subject = $subject;
		$mail->Body    = $body;

		// Vlastní odeslání
		$mail->send();
		return true;

	} catch (Exception $e) {
		$error_msg = "SMTP Error: " . $mail->ErrorInfo;
		
		// Zápis do aplikačního deníku (Ramses.log) pro auditní stopu
		if (function_exists('write_log')) {
			write_log($error_msg);
		}
		
		// Výpis chyby přímo na výstup obrazovky pro okamžité ladění (dle požadavku)
		echo "<div style=\"background-color: #f8d7da; color: #721c24; padding: 15px; margin: 20px 0; border: 1px solid #f5c6cb; font-family: sans-serif;\">";
		echo "<strong>Chyba odesílání e-mailu (send_global_mail):</strong><br>";
		echo htmlspecialchars($error_msg);
		echo "</div>";

		// Provázání do existujícího Ramses debug režimu, pokud je zapnutý
		if (!empty($debugmode) && function_exists('debugitem')) {
			debugitem('SMTP Error Detail', $e->getMessage());
		}
		
		return false;
	}
}
?>