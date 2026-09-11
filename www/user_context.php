<?php
/**
 * =============================================================================
 * Třída: user_context
 * Účel: Kompaktní vizuální komponenta (logo, uživatel, organizace, role, odhlášení)
 *       zobrazená jako standardní fixovaný horní pruh na stránce.
 * 
 * Vazby na okolí:
 * - Instancuje se a vykresluje výhradně uvnitř metody render() v `abstract_page`.
 * - Spoléhá na existenci globálního pole `$dbsession`.
 * - Nově vyhodnocuje flag `change_context_allowed` pro nabídnutí změny kontextu.
 * =============================================================================
 */

declare(strict_types=1);

class user_context {

	public function __toString(): string {
		return $this->render();
	}

	public function render(): string {
		global $dbsession;

		// Pokud není relace k dispozici, pruh se nevykresluje
		if (!is_array($dbsession) || empty($dbsession['user_account'])) {
			return '';
		}

		$displayName = (string)($dbsession['display_name'] ?? $dbsession['user_name'] ?? 'Uživatel');
		$orgName = (string)($dbsession['organization_name'] ?? 'Organizace');
		
		// Určení přesného textu role a barvy štítku na základě oprávnění
		if (!empty($dbsession['right_sysadmin'])) {
			$roleText = 'System Administrator';
			$roleClass = 'sys';
		} elseif (!empty($dbsession['right_orgadmin'])) {
			$roleText = 'Administrátor';
			$roleClass = 'org';
		} else {
			$roleText = 'Uživatel';
			$roleClass = 'usr';
		}

		$safeDisplayName = htmlspecialchars($displayName, ENT_QUOTES, 'UTF-8');
		$safeOrgName = htmlspecialchars($orgName, ENT_QUOTES, 'UTF-8');

		// Vykreslení organizace s odkazem, pokud je povolená změna kontextu
		if (!empty($dbsession['change_context_allowed'])) {
			$orgHtml = '<a href="index.php?page=change_user_context" class="bcm-context-org link" title="Změnit organizaci či roli">' . $safeOrgName . ' <span style="font-size: 10px;">▼</span></a>';
		} else {
			$orgHtml = '<span class="bcm-context-org" title="Aktuální organizace">' . $safeOrgName . '</span>';
		}

		return <<<HTML
<style>
	.bcm-top-bar {
		background: #ffffff;
		border-bottom: 1px solid #cbd5e1;
		padding: 4px 12px;
		font-family: Arial, sans-serif;
		font-size: 12px;
		color: #334155;
		display: flex;
		justify-content: space-between;
		align-items: center;
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
	}
	.bcm-top-bar-left {
		display: flex;
		align-items: center;
	}
	.bcm-top-bar-right {
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.bcm-context-org { 
		font-weight: bold; 
		color: #0f172a; 
	}
	a.bcm-context-org.link {
		text-decoration: none;
		padding: 2px 6px;
		border-radius: 3px;
		transition: background 0.2s;
	}
	a.bcm-context-org.link:hover {
		background-color: #f1f5f9;
		color: #2563eb;
	}
	.bcm-context-user { 
		color: #475569; 
	}
	.ctx-role { 
		font-size: 10px; 
		font-weight: bold; 
		padding: 2px 6px; 
		border-radius: 3px; 
		color: #fff; 
		letter-spacing: 0.5px;
		text-transform: uppercase;
	}
	.ctx-role.sys { background-color: #b91c1c; }
	.ctx-role.org { background-color: #2563eb; }
	.ctx-role.usr { background-color: #64748b; }
	
	.ctx-logout {
		color: #b91c1c;
		text-decoration: none;
		font-weight: bold;
		padding: 2px 6px;
		border-left: 1px solid #e2e8f0;
		margin-left: 5px;
		transition: background 0.2s;
	}
	.ctx-logout:hover { 
		background-color: #fee2e2; 
		border-radius: 3px;
	}
	.ctx-graphic-placeholder {
		color: #94a3b8;
		font-style: italic;
		font-weight: bold;
		font-size: 14px;
	}
	
	@media print { .bcm-top-bar { display: none !important; } }
</style>

<div class="bcm-top-bar">
	<div class="bcm-top-bar-left">
		<div class="ctx-graphic-placeholder">
			[ Logo / Grafika ]
		</div>
	</div>
	<div class="bcm-top-bar-right">
		{$orgHtml}
		<span style="color: #cbd5e1;">|</span>
		<span class="bcm-context-user" title="Přihlášený uživatel">{$safeDisplayName}</span>
		<span class="ctx-role {$roleClass}">{$roleText}</span>
		<a href="index.php?page=logout" class="ctx-logout" title="Odhlásit se">Odhlásit</a>
	</div>
</div>
HTML;
	}
}