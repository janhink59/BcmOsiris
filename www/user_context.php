<?php
/**
 * =============================================================================
 * Třída: user_context
 * Účel: Kompaktní vizuální komponenta (uživatel, organizace, role a odhlášení)
 *       fixovaná v pravém horním rohu obrazovky.
 * =============================================================================
 */

declare(strict_types=1);

class user_context {

	public function __toString(): string {
		return $this->render();
	}

	public function render(): string {
		global $dbsession;

		if (!is_array($dbsession) || empty($dbsession['user_account'])) {
			return '';
		}

		$displayName = (string)($dbsession['display_name'] ?? $dbsession['user_name'] ?? 'Uživatel');
		$orgName = (string)($dbsession['organization_name'] ?? 'Organizace');
		
		$badges = [];
		if (!empty($dbsession['right_sysadmin'])) {
			$badges[] = '<span class="ctx-badge sys" title="System Administrator">SYS</span>';
		}
		if (!empty($dbsession['right_orgadmin'])) {
			$badges[] = '<span class="ctx-badge org" title="Organization Administrator">ORG</span>';
		}
		if (empty($badges)) {
			$badges[] = '<span class="ctx-badge usr" title="Standardní uživatel">USR</span>';
		}
		$badgesHtml = implode(' ', $badges);

		$safeDisplayName = htmlspecialchars($displayName, ENT_QUOTES, 'UTF-8');
		$safeOrgName = htmlspecialchars($orgName, ENT_QUOTES, 'UTF-8');

		return <<<HTML
<style>
	.bcm-context-panel {
		position: fixed;
		top: 15px;
		right: 20px;
		z-index: 9999;
		background: #ffffff;
		border: 1px solid #cbd5e1;
		border-radius: 6px;
		padding: 6px 12px;
		font-family: Arial, sans-serif;
		font-size: 12px;
		color: #334155;
		box-shadow: 0 2px 6px rgba(0, 0, 0, 0.08);
		display: flex;
		align-items: center;
		gap: 12px;
		line-height: 1.3;
	}
	.bcm-context-info {
		display: flex;
		flex-direction: column;
		text-align: right;
	}
	.bcm-context-org { font-weight: bold; color: #0f172a; }
	.bcm-context-user { color: #64748b; }
	.bcm-context-badges { 
		display: flex; 
		gap: 4px; 
		border-left: 1px solid #e2e8f0; 
		padding-left: 12px; 
	}
	.ctx-badge { 
		font-size: 9px; 
		font-weight: bold; 
		padding: 2px 5px; 
		border-radius: 3px; 
		color: #fff; 
		letter-spacing: 0.5px; 
	}
	.ctx-badge.sys { background-color: #b91c1c; }
	.ctx-badge.org { background-color: #2563eb; }
	.ctx-badge.usr { background-color: #64748b; }
	
	.ctx-logout {
		border-left: 1px solid #e2e8f0;
		padding-left: 12px;
		display: flex;
		align-items: center;
	}
	.ctx-logout a {
		color: #b91c1c;
		text-decoration: none;
		font-weight: bold;
		font-size: 12px;
		padding: 4px 8px;
		border-radius: 4px;
		transition: background 0.2s;
	}
	.ctx-logout a:hover { background-color: #fee2e2; }
	
	@media print { .bcm-context-panel { display: none !important; } }
</style>

<div class="bcm-context-panel">
	<div class="bcm-context-info">
		<span class="bcm-context-org" title="Aktuální organizace">{$safeOrgName}</span>
		<span class="bcm-context-user" title="Přihlášený uživatel">{$safeDisplayName}</span>
	</div>
	<div class="bcm-context-badges">
		{$badgesHtml}
	</div>
	<div class="ctx-logout">
		<a href="index.php?page=logout" title="Odhlásit se">Odhlásit</a>
	</div>
</div>
HTML;
	}
}