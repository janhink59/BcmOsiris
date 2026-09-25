<?php
/**
 * =============================================================================
 * Verze: 2026-09-25 16:51
 * Stránka: page_main.php
 * Účel: Hlavní rozcestník. Kód je maximálně zredukován na byznys logiku tlačítek.
 * OPRAVA: Přidán odkaz na správu metadat objektů pro systémové administrátory.
 * =============================================================================
 */

declare(strict_types=1);

class page_main extends abstract_page {

	public function __construct() {
		$this->page_title = 'Hlavní panel - BCM Osiris';
	}

	protected function render_body(): void {
		global $dbsession;

		if (!is_array($dbsession) || empty($dbsession['user_account'])) {
			echo "<div class='msg-err'>Chyba: Nepodařilo se načíst kontext uživatele.</div>";
			return;
		}

		$isSysadmin = !empty($dbsession['right_sysadmin']);
		$isOrgadmin = !empty($dbsession['right_orgadmin']);

		$sysadminActions = '';
		if ($isSysadmin) {
			$sysadminActions = <<<HTML
				<div style="margin-top: 20px; padding-top: 15px;">
					<h3 style="margin-top: 0; font-size: 16px;">Systémová administrace</h3>
					<a href="index.php?page=organization_licence" class="btn" style="margin-right: 10px;">Správa licencí organizací</a>
					<a href="index.php?page=meta_object" class="btn">Správa metadat objektů a sloupců</a>
				</div>
HTML;
		}

		$orgadminActions = '';
		if ($isOrgadmin) {
			$orgadminActions = <<<HTML
				<div style="margin-top: 20px; padding-top: 15px; border-top: 1px solid #eee;">
					<h3 style="margin-top: 0; font-size: 16px; color: #2E7D32;">Správa organizace</h3>
					<a href="index.php?page=org_users" class="btn btn-success">Správa uživatelů</a>
				</div>
HTML;
		}

		echo <<<HTML
		<h1 class="page-heading">Vítejte v systému BCM Osiris</h1>
		<p>Vyberte požadovanou akci z níže uvedených modulů.</p>
		{$sysadminActions}
		{$orgadminActions}
HTML;
	}
}