<?php
/**
 * =============================================================================
 * Verze: 2026-10-09
 * Stránka: page_main.php
 * Účel: Hlavní rozcestník. Kód je maximálně zredukován na byznys logiku tlačítek.
 * 
 * BUDOUCÍ ARCHITEKTURA (Příprava na databázové řízení rolí):
 * Jakmile bude tabulka `meta_object` rozšířena o `system_role` (nebo navázána 
 * na vlastní business-role v tenantech), tento statický kód zmizí. Tlačítka 
 * (moduly) se budou generovat dynamicky dotazem do DB. Zjistí se dostupné
 * stránky pro aktuální efektivní roli uživatele a z metadat se načtou jejich 
 * ikonky, titulky a popisky.
 * =============================================================================
 */

declare(strict_types=1);

class page_main extends abstract_page {

	public function __construct() {
		global $dbsession;

		$this->page_title = 'Hlavní panel - BCM Osiris';

		// Zajištění, že nepodepsaný uživatel neuvidí prázdnou stránku
		// (Ačkoliv by ho měl zachytit už initsession v OsirisLib)
		if (!is_array($dbsession) || empty($dbsession['user_account'])) {$this->access_denied = true;
		}
	}

	protected function render_body(): void {
		global $dbsession;

		$active_role =$dbsession['active_role'] ?? 'U';
		$isSysadmin = in_array($active_role, ['S', 'D'], true);
		$isOrgadmin = ($active_role === 'A');

		// ---------------------------------------------------------------------
		// TODO: Nahradit dynamickým generováním z meta_object.system_role
		// Místo hardcodovaných bloků se zde provede SELECT do meta_object, 
		// který vyfiltruje moduly podle $active_role.
		// ---------------------------------------------------------------------

		$sysadminActions = '';
		if ($isSysadmin) {$sysadminActions = <<<HTML
				<div style="margin-top: 20px; padding-top: 15px;">
					<h3 style="margin-top: 0; font-size: 16px;">Systémová administrace</h3>
					<a href="index.php?page=organization_licence" class="btn" style="margin-right: 10px;">Správa licencí organizací</a>
					<a href="index.php?page=meta_class" class="btn">Správa metadat tříd a sloupců</a>
				</div>
HTML;
		}

		$orgadminActions = '';
		if ($isOrgadmin) {$orgadminActions = <<<HTML
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